import Foundation
import CoreLocation

/// The map's coordinate system is selected explicitly. The mainland option
/// uses a bounding box, not a precise country border. For locations within that
/// box which do not use GCJ-02, select WGS84 instead.
enum MapCoordinateMode: Int {
    case mainlandGCJ02 = 0
    case wgs84 = 1
}

/// Coordinates sent to the phone are WGS84; map coordinates use the selected
/// mode. Convert once when crossing this boundary, never repeatedly in storage.
///
/// GCJ-02 uses a widely published approximate mathematical model (constants and
/// formula reference: https://github.com/wandergis/coordtransform). Its inverse
/// converges against that model; sub-metre internal round trips do not establish
/// the accuracy of a map provider or a real phone. Verify the actual phone fix.
///
/// Both methods preserve invalid inputs unchanged, including NaN, infinity, and
/// out-of-range latitude/longitude. Callers must reject invalid coordinates
/// before rendering or sending them to a device; this helper never sanitizes
/// invalid values into a valid location. Valid coordinates outside the common
/// GCJ approximation box also pass through unchanged in either direction.
enum CoordinateTransform {
    private static let semiMajorAxis = 6_378_245.0
    private static let eccentricitySquared = 0.00669342162296594323

    static func toMap(_ gps: CLLocationCoordinate2D, mode: MapCoordinateMode) -> CLLocationCoordinate2D {
        guard mode == .mainlandGCJ02, valid(gps), withinApproximationBox(gps) else { return gps }
        return forwardModel(gps)
    }

    static func toGPS(_ map: CLLocationCoordinate2D, mode: MapCoordinateMode) -> CLLocationCoordinate2D {
        guard mode == .mainlandGCJ02, valid(map), withinApproximationBox(map) else { return map }
        // Subtract the forward-model residual rather than using a single
        // approximate offset. This keeps an edited route consistent in both
        // directions, including when each individual route point is converted.
        var estimate = map
        for _ in 0..<16 {
            let projected = forwardModel(estimate)
            let latitudeError = projected.latitude - map.latitude
            let longitudeError = projected.longitude - map.longitude
            estimate.latitude -= latitudeError
            estimate.longitude -= longitudeError
            if max(abs(latitudeError), abs(longitudeError)) < 1e-11 { break }
        }
        return estimate
    }

    private static func valid(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude.isFinite && coordinate.longitude.isFinite &&
            (-90...90).contains(coordinate.latitude) && (-180...180).contains(coordinate.longitude)
    }

    private static func withinApproximationBox(_ coordinate: CLLocationCoordinate2D) -> Bool {
        (0.8293...55.8271).contains(coordinate.latitude) &&
            (72.004...137.8347).contains(coordinate.longitude)
    }

    private static func forwardModel(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let x = coordinate.longitude - 105
        let y = coordinate.latitude - 35
        let sharedWave = (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        var latitudeDelta = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        latitudeDelta += sharedWave
        latitudeDelta += (20 * sin(y * .pi) + 40 * sin(y / 3 * .pi)) * 2 / 3
        latitudeDelta += (160 * sin(y / 12 * .pi) + 320 * sin(y * .pi / 30)) * 2 / 3
        var longitudeDelta = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        longitudeDelta += sharedWave
        longitudeDelta += (20 * sin(x * .pi) + 40 * sin(x / 3 * .pi)) * 2 / 3
        longitudeDelta += (150 * sin(x / 12 * .pi) + 300 * sin(x / 30 * .pi)) * 2 / 3

        let latitudeRadians = coordinate.latitude * .pi / 180
        let latitudeSine = sin(latitudeRadians)
        let meridianFactor = 1 - eccentricitySquared * latitudeSine * latitudeSine
        let root = sqrt(meridianFactor)
        latitudeDelta *= 180 / (semiMajorAxis * (1 - eccentricitySquared) / (meridianFactor * root) * .pi)
        longitudeDelta *= 180 / (semiMajorAxis / root * cos(latitudeRadians) * .pi)
        return CLLocationCoordinate2D(latitude: coordinate.latitude + latitudeDelta,
                                      longitude: coordinate.longitude + longitudeDelta)
    }
}
