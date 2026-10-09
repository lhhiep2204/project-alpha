//
//  DistanceUnit+Formatting.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 20/9/26.
//

import Foundation

extension DistanceUnit {
    /// Call with the scene's locale. Each invocation owns its formatter.
    func formatted(_ metres: Double, locale: Locale = .current) -> String {
        let unit: UnitLength
        switch self {
        case .kilometre: unit = metres >= 1_000 ? .kilometers : .meters
        case .mile: unit = metres >= 1_609.344 ? .miles : .yards
        }
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = (unit == .kilometers || unit == .miles) ? 1 : 0
        return formatter.string(from: Measurement(value: metres, unit: UnitLength.meters).converted(to: unit))
    }
}
