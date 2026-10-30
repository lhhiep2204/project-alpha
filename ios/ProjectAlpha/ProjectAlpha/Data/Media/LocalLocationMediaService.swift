//
//  LocalLocationMediaService.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 18/10/26.
//

import Foundation
import UniformTypeIdentifiers

nonisolated struct LocalMediaConfiguration: Sendable {
    var longestSide = 1_600
    var jpegQuality = 0.78
    var thumbnailLongestSide = 320
    var thumbnailCacheByteLimit = 4 * 1_024 * 1_024
    var orphanGracePeriod: TimeInterval = 24 * 60 * 60
    var cleanupRetryDelay: TimeInterval = 60
}

/// A deterministic failure seam; production uses the no-op default.
nonisolated enum LocalMediaFileOperation: Sendable {
    case createDirectory, writeJournal, writePhoto, readPhoto, enumerateFiles
    case removeFile(URL)
}

/// One app-owned instance. Its actor executor serializes decoding and disk work
/// away from MainActor and bounds image work to one decode at a time.
actor LocalLocationMediaService: LocationMediaService {
    private nonisolated enum Token {
        static let root = "LocationMedia"
        static let photos = "photos"
        static let drafts = "drafts"
        static let jpegExtension = "jpg"
        static let journalExtension = "plist"
    }

    private nonisolated struct Ownership: Codable, Sendable {
        let assetID: UUID
        let draftID: UUID
        let token: String
        let createdAt: Date

        var reference: LocalAssetReference {
            get throws { try LocalAssetReference(assetID: assetID, relativeFileToken: token) }
        }
    }

    private nonisolated struct Draft {
        var assets: [UUID: Ownership] = [:]
        var preparing: Set<UUID> = []
        var retired = false
    }

    private let store: LibraryStore
    private let baseDirectory: URL?
    private let configuration: LocalMediaConfiguration
    private let currentDate: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private let beforeFileOperation: @Sendable (LocalMediaFileOperation) throws -> Void
    private let files = FileManager()
    private var drafts: [UUID: Draft] = [:]
    private var thumbnailCache: [String: Data] = [:]
    private var thumbnailOrder: [String] = []
    private var thumbnailBytes = 0
    private var maintenanceInProgress = false

    init(
        store: LibraryStore,
        baseDirectory: URL? = nil,
        configuration: LocalMediaConfiguration = LocalMediaConfiguration(),
        currentDate: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init,
        beforeFileOperation: @escaping @Sendable (LocalMediaFileOperation) throws -> Void = { _ in }
    ) {
        self.store = store
        self.baseDirectory = baseDirectory
        self.configuration = configuration
        self.currentDate = currentDate
        self.makeID = makeID
        self.beforeFileOperation = beforeFileOperation
    }

    /// Explicit lifecycle work after the library opens. Failures leave durable
    /// journals/cleanup tasks intact for the next foreground/startup retry.
    /// Independent work finishes before the first failure is reported.
    func startMaintenance() async throws {
        try Task.checkCancellation()
        guard !maintenanceInProgress else { return }
        maintenanceInProgress = true
        defer { maintenanceInProgress = false }
        try createDirectories()
        var firstFailure: (any Error)?
        do { try await reconcileJournals() }
        catch { try recordMaintenanceFailure(error, firstFailure: &firstFailure) }
        do { try await reconcileOrphanFiles() }
        catch { try recordMaintenanceFailure(error, firstFailure: &firstFailure) }
        let cleanupTasks: [MediaCleanupTask]
        do { cleanupTasks = try await store.dueCleanupTasks(at: currentDate()) }
        catch {
            try recordMaintenanceFailure(error, firstFailure: &firstFailure)
            cleanupTasks = []
        }
        for task in cleanupTasks {
            try Task.checkCancellation()
            do { try await consumeCleanup(task, checkingCancellation: true) }
            catch { try recordMaintenanceFailure(error, firstFailure: &firstFailure) }
        }
        try Task.checkCancellation()
        if let firstFailure { throw firstFailure }
    }

    func preparePhoto(data: Data, draftID: UUID) async throws -> LocalAssetReference {
        guard drafts[draftID]?.retired != true else { throw CancellationError() }
        guard (drafts[draftID]?.assets.count ?? 0) < LocationDraftPolicy.maximumPhotoCount else {
            throw LocationMediaError.photoLimit
        }
        let assetID = makeID()
        guard !drafts.values.contains(where: { $0.assets[assetID] != nil }) else {
            throw LocationMediaError.storageFailure
        }
        let token = Token.photos + URLPath.separator + assetID.uuidString + URLPath.dot + Token.jpegExtension
        let ownership = Ownership(assetID: assetID, draftID: draftID, token: token, createdAt: currentDate())
        drafts[draftID, default: Draft()].assets[assetID] = ownership
        drafts[draftID]?.preparing.insert(assetID)
        var ownsFiles = false
        do {
            try Task.checkCancellation()
            // Even a deterministic/reused ID must never overwrite an older
            // file or retire another draft's registration on the failure path.
            guard !files.fileExists(atPath: try fileURL(token).path),
                  try await store.assetToken(id: assetID) == nil else {
                throw LocationMediaError.storageFailure
            }
            guard drafts[draftID]?.retired == false else { throw CancellationError() }
            let encoded = try LocalMediaImageEncoder.encode(
                data, longestSide: max(1, configuration.longestSide),
                quality: min(1, max(0, configuration.jpegQuality))
            )
            try createDirectories()
            // Persist ownership first: interruption before or after the atomic
            // final-file write is recoverable without touching committed media.
            try beforeFileOperation(.writeJournal)
            try PropertyListEncoder().encode(ownership).write(to: journalURL(assetID), options: .atomic)
            ownsFiles = true
            try beforeFileOperation(.writePhoto)
            try encoded.data.write(to: fileURL(token), options: .atomic)
            try await store.registerAsset(PreparedLocalAsset(
                id: assetID, relativeFileToken: token, contentType: UTType.jpeg.identifier,
                pixelWidth: encoded.width, pixelHeight: encoded.height, createdAt: ownership.createdAt
            ))
            try Task.checkCancellation()
            guard drafts[draftID]?.retired == false,
                  drafts[draftID]?.assets[assetID] != nil else { throw CancellationError() }
            drafts[draftID]?.preparing.remove(assetID)
            return try ownership.reference
        } catch {
            drafts[draftID]?.preparing.remove(assetID)
            // Failed cleanup remains journalled for maintenance; another photo
            // import is still allowed and the rest of the draft is unchanged.
            if ownsFiles { try? await retire(ownership, retiringActiveOwnership: true) }
            removeOwnership(ownership)
            if error is CancellationError { throw CancellationError() }
            if let mediaError = error as? LocationMediaError { throw mediaError }
            throw LocationMediaError.storageFailure
        }
    }

    func photoData(for asset: LocalAssetReference, thumbnail: Bool) async throws -> Data {
        try Task.checkCancellation()
        do {
            let url = try fileURL(asset.relativeFileToken)
            if thumbnail, let cached = thumbnailCache[asset.relativeFileToken] { return cached }
            try beforeFileOperation(.readPhoto)
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            if thumbnail {
                let encoded = try LocalMediaImageEncoder.encode(
                    data, longestSide: max(1, configuration.thumbnailLongestSide), quality: configuration.jpegQuality
                ).data
                cache(encoded, token: asset.relativeFileToken)
                return encoded
            }
            try LocalMediaImageEncoder.validate(data, longestSide: max(1, configuration.longestSide))
            try Task.checkCancellation()
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LocationMediaError {
            throw error
        } catch {
            throw LocationMediaError.storageFailure
        }
    }

    func discardPhoto(_ asset: LocalAssetReference, draftID: UUID) async {
        guard let ownership = drafts[draftID]?.assets[asset.assetID],
              ownership.token == asset.relativeFileToken else { return }
        try? await retire(ownership, retiringActiveOwnership: true)
        removeOwnership(ownership)
    }

    func cancelDraft(id: UUID) async { await retireDraft(id) }
    func finishDraft(id: UUID) async { await retireDraft(id) }

    private func retireDraft(_ id: UUID) async {
        guard drafts[id] != nil else { return }
        drafts[id]?.retired = true
        let assets = drafts[id].map { Array($0.assets.values) } ?? []
        for ownership in assets where drafts[id]?.preparing.contains(ownership.assetID) != true {
            try? await retire(ownership, retiringActiveOwnership: true)
            removeOwnership(ownership)
        }
        pruneDraft(id)
    }

    /// Maintenance stops cooperatively; explicit draft retirement keeps its
    /// best-effort cleanup even when the importing task was already cancelled.
    private func retire(_ ownership: Ownership, retiringActiveOwnership: Bool = false,
                        checkingCancellation: Bool = false) async throws {
        if checkingCancellation { try Task.checkCancellation() }
        let exclusion = retiringActiveOwnership ? ownership.assetID : nil
        guard !isActive(token: ownership.token, excluding: exclusion) else { return }
        let task = try await store.discardUnreferencedAsset(id: ownership.assetID)
        if checkingCancellation { try Task.checkCancellation() }
        if let task {
            try await consumeCleanup(task, retiringAssetID: exclusion, checkingCancellation: checkingCancellation)
        } else {
            let references = try await store.referencedAssetIDsAndTokens()
            if checkingCancellation { try Task.checkCancellation() }
            if references[ownership.assetID] == nil,
               !references.values.contains(ownership.token) {
                let registeredToken = try await store.assetToken(id: ownership.assetID)
                if checkingCancellation { try Task.checkCancellation() }
                if registeredToken == nil {
                    guard !isActive(token: ownership.token, excluding: exclusion) else { return }
                    try removeFile(fileURL(ownership.token))
                    evict(ownership.token)
                }
            }
        }
        if checkingCancellation { try Task.checkCancellation() }
        try removeFile(journalURL(ownership.assetID))
    }

    private func consumeCleanup(_ task: MediaCleanupTask, retiringAssetID: UUID? = nil,
                                checkingCancellation: Bool = false) async throws {
        if checkingCancellation { try Task.checkCancellation() }
        guard !isActive(token: task.relativeFileToken, excluding: retiringAssetID) else { return }
        let references = try await store.referencedAssetIDsAndTokens()
        if checkingCancellation { try Task.checkCancellation() }
        guard !references.values.contains(task.relativeFileToken),
              !isActive(token: task.relativeFileToken, excluding: retiringAssetID) else { return }
        do {
            try removeFile(fileURL(task.relativeFileToken))
            evict(task.relativeFileToken)
            try await store.markCleanupSucceeded(id: task.id)
        } catch {
            if checkingCancellation {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
            }
            try? await store.markCleanupFailed(
                id: task.id, nextAttemptAt: currentDate().addingTimeInterval(max(1, configuration.cleanupRetryDelay))
            )
            throw error
        }
    }

    private func reconcileJournals() async throws {
        let urls = try contents(of: directory(Token.drafts))
        var firstFailure: (any Error)?
        for url in urls where url.pathExtension == Token.journalExtension {
            try Task.checkCancellation()
            // A corrupt journal cannot authorize deletion. The orphan scan can
            // independently recover its photo using the conservative grace rule.
            guard let data = try? Data(contentsOf: url),
                  let ownership = try? PropertyListDecoder().decode(Ownership.self, from: data),
                  (try? ownership.reference) != nil,
                  !isActive(token: ownership.token) else { continue }
            do {
                let references = try await store.referencedAssetIDsAndTokens()
                try Task.checkCancellation()
                guard !isActive(token: ownership.token) else { continue }
                if references.values.contains(ownership.token) {
                    try removeFile(url)
                } else if currentDate().timeIntervalSince(ownership.createdAt) >= max(0, configuration.orphanGracePeriod) {
                    try await retire(ownership, checkingCancellation: true)
                }
            } catch {
                try recordMaintenanceFailure(error, firstFailure: &firstFailure)
            }
        }
        if let firstFailure { throw firstFailure }
    }

    private func reconcileOrphanFiles() async throws {
        // One projection skips committed files before expensive per-deletion checks.
        // A file becoming referenced later is protected again by retire/consumeCleanup.
        let referencedTokens = Set(try await store.referencedAssetIDsAndTokens().values)
        var firstFailure: (any Error)?
        for url in try contents(of: directory(Token.photos)) where url.pathExtension == Token.jpegExtension {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            let token = Token.photos + URLPath.separator + url.lastPathComponent
            try Task.checkCancellation()
            guard !referencedTokens.contains(token), !isActive(token: token) else { continue }
            do {
                guard let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      currentDate().timeIntervalSince(date) >= max(0, configuration.orphanGracePeriod) else { continue }
                let ownership = Ownership(assetID: id, draftID: id, token: token, createdAt: date)
                guard !isActive(token: token) else { continue }
                try await retire(ownership, checkingCancellation: true)
            } catch {
                try recordMaintenanceFailure(error, firstFailure: &firstFailure)
            }
        }
        if let firstFailure { throw firstFailure }
    }

    private func recordMaintenanceFailure(_ error: any Error, firstFailure: inout (any Error)?) throws {
        try Task.checkCancellation()
        if error is CancellationError { throw error }
        if firstFailure == nil { firstFailure = error }
    }

    private func isActive(token: String, excluding assetID: UUID? = nil) -> Bool {
        drafts.values.contains { draft in
            draft.assets.values.contains { $0.token == token && $0.assetID != assetID }
        }
    }

    private func removeOwnership(_ ownership: Ownership) {
        drafts[ownership.draftID]?.assets.removeValue(forKey: ownership.assetID)
        pruneDraft(ownership.draftID)
    }

    private func pruneDraft(_ id: UUID) {
        if drafts[id]?.retired == true, drafts[id]?.assets.isEmpty == true,
           drafts[id]?.preparing.isEmpty == true { drafts.removeValue(forKey: id) }
    }

    private nonisolated enum URLPath {
        static let separator = "/"
        static let dot = "."
    }

    private func rootDirectory() throws -> URL {
        if let baseDirectory { return baseDirectory }
        guard let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw LocationMediaError.storageFailure
        }
        return support.appendingPathComponent(Token.root, isDirectory: true)
    }

    private func directory(_ name: String) throws -> URL {
        try rootDirectory().appendingPathComponent(name, isDirectory: true)
    }

    private func journalURL(_ id: UUID) throws -> URL {
        try directory(Token.drafts).appendingPathComponent(id.uuidString).appendingPathExtension(Token.journalExtension)
    }

    private func fileURL(_ token: String) throws -> URL {
        let root = try rootDirectory().standardizedFileURL
        let url = root.appendingPathComponent(token).standardizedFileURL
        guard url.path.hasPrefix(root.path + URLPath.separator) else { throw LocationMediaError.storageFailure }
        return url
    }

    private func createDirectories() throws {
        for name in [Token.photos, Token.drafts] {
            try beforeFileOperation(.createDirectory)
            try files.createDirectory(at: directory(name), withIntermediateDirectories: true)
        }
    }

    private func contents(of url: URL) throws -> [URL] {
        try beforeFileOperation(.enumerateFiles)
        return try files.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey])
    }

    private func removeFile(_ url: URL) throws {
        try beforeFileOperation(.removeFile(url))
        if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
    }

    private func cache(_ data: Data, token: String) {
        let limit = max(0, configuration.thumbnailCacheByteLimit)
        guard data.count <= limit else { return }
        evict(token)
        while thumbnailBytes + data.count > limit, let oldest = thumbnailOrder.first { evict(oldest) }
        thumbnailCache[token] = data
        thumbnailOrder.append(token)
        thumbnailBytes += data.count
    }

    private func evict(_ token: String) {
        if let data = thumbnailCache.removeValue(forKey: token) { thumbnailBytes -= data.count }
        thumbnailOrder.removeAll { $0 == token }
    }
}
