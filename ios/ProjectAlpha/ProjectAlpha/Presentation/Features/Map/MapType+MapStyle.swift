import MapKit
import SwiftUI

/// The set of map display styles available for the embedded MapKit map.
extension MapType {
    /// The MapKit `MapStyle` corresponding to this type.
    var mapStyle: MapStyle {
        switch self {
        case .standard: .standard
        case .satellite: .imagery
        case .hybrid: .hybrid
        }
    }
}
