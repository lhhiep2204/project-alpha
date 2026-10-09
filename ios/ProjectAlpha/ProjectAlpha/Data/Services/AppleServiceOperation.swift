//
//  AppleServiceOperation.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 6/10/26.
//

import Foundation
import MapKit

/// One cancellable SDK operation. The injectable start/cancel closures provide deterministic tests.
@MainActor
final class AppleServiceOperation<Value: Sendable> {
    typealias Completion = @MainActor (Result<Value, PlaceServiceError>) -> Void
    private let startRequest: (@MainActor (@escaping Completion) -> Void)?
    private let asyncRequest: (@MainActor () async throws -> Value)?
    private var workerTask: Task<Void, Never>?
    private let cancelRequest: @MainActor () -> Void
    private let onRequestEnqueued: (@MainActor (Task<Void, Never>) -> Void)?
    private var continuation: CheckedContinuation<Value, any Error>?
    private var ended = false
    private var started = false

    init(
        start: @escaping @MainActor (@escaping Completion) -> Void,
        cancel: @escaping @MainActor () -> Void
    ) {
        startRequest = start
        asyncRequest = nil
        onRequestEnqueued = nil
        cancelRequest = cancel
    }

    init(
        asyncRequest: @escaping @MainActor () async throws -> Value,
        onRequestEnqueued: (@MainActor (Task<Void, Never>) -> Void)? = nil,
        cancel: @escaping @MainActor () -> Void
    ) {
        startRequest = nil
        self.asyncRequest = asyncRequest
        self.onRequestEnqueued = onRequestEnqueued
        cancelRequest = cancel
    }

    func value() async throws(PlaceServiceError) -> Value {
        do {
            let result = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                guard !ended else { throw PlaceServiceError.cancelled }
                guard !started else { throw PlaceServiceError.invalidRequest }
                started = true
                return try await withCheckedThrowingContinuation { continuation in
                    self.continuation = continuation
                    if let startRequest {
                        startRequest { [weak self] result in self?.finish(result) }
                    } else if let asyncRequest {
                        workerTask = Task { @MainActor [weak self] in
                            guard !Task.isCancelled else { return }
                            do {
                                let result = try await asyncRequest()
                                guard !Task.isCancelled else { return }
                                self?.finish(.success(result))
                            } catch {
                                guard !Task.isCancelled else { return }
                                self?.finish(.failure(AppleServiceErrorMapper.map(error)))
                            }
                        }
                        if let workerTask { onRequestEnqueued?(workerTask) }
                    }
                }
            } onCancel: {
                Task { @MainActor [weak self] in self?.cancel() }
            }
            guard !Task.isCancelled else { throw PlaceServiceError.cancelled }
            return result
        } catch let error as PlaceServiceError {
            throw error
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .providerUnavailable
        }
    }

    func cancel(reason: PlaceServiceError = .cancelled) {
        guard !ended else { return }
        ended = true
        let pending = continuation
        continuation = nil
        workerTask?.cancel()
        workerTask = nil
        cancelRequest()
        pending?.resume(throwing: reason)
    }

    private func finish(_ result: Result<Value, PlaceServiceError>) {
        guard !ended else { return }
        ended = true
        let pending = continuation
        continuation = nil
        workerTask = nil
        switch result {
        case let .success(value): pending?.resume(returning: value)
        case let .failure(error): pending?.resume(throwing: error)
        }
    }
}

@MainActor
enum AppleServiceErrorMapper {
    static func map(_ error: any Error) -> PlaceServiceError {
        if let error = error as? PlaceServiceError { return error }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return .cancelled }
            return .networkUnavailable
        }
        if let error = error as? MKError {
            switch error.code {
            case .loadingThrottled: return .rateLimited
            case .placemarkNotFound: return .notFound
            case .directionsNotFound: return .noRoute
            default: return .providerUnavailable
            }
        }
        return .providerUnavailable
    }
}
