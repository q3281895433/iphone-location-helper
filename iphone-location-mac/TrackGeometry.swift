import Foundation
import CoreFoundation
import CoreLocation

/// Stadium geometry in metres. Rotation is clockwise from north, matching
/// route_geometry.py: at zero degrees the straight sections run north–south.
struct TrackGeometry {
    var latitude: Double
    var longitude: Double
    var lapLength: Double
    var radius: Double
    var rotation: Double {
        didSet { rotation = Self.normalizedRotation(rotation) }
    }
    var reverse: Bool

    private static let earthRadius = 6_371_008.8
    private static let minimumLap = 50.0
    private static let maximumLap = 2_000.0
    private static let minimumStraight = 1.0
    // Forms round metre values to six decimals; allow that serialization error.
    private static let straightTolerance = 0.00001
    private static let minimumResizeRadius = 1.0
    private static let maximumRadius = 300.0
    private static let tau = 2 * Double.pi

    init?(dictionary: [String: Any]) {
        func number(_ key: String, default fallback: Double? = nil) -> Double? {
            guard let raw = dictionary[key] else { return fallback }
            // JSON booleans also bridge to NSNumber, but are not coordinates.
            guard let value = raw as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite else { return nil }
            return value.doubleValue
        }
        guard let latitude = number("latitude"), abs(latitude) <= 85,
              let longitude = number("longitude"), abs(longitude) <= 180,
              let lapLength = number("lapLength"),
              (Self.minimumLap...Self.maximumLap).contains(lapLength),
              let radius = number("radius"),
              (Self.minimumResizeRadius...Self.maximumRadius).contains(radius),
              (lapLength - Self.tau * radius) / 2 >= Self.minimumStraight - Self.straightTolerance,
              let rotation = number("rotation", default: 0) else { return nil }
        if let value = dictionary["reverse"] {
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        }
        self.latitude = latitude
        self.longitude = longitude
        self.lapLength = lapLength
        self.radius = radius
        self.rotation = Self.normalizedRotation(rotation)
        self.reverse = dictionary["reverse"] as? Bool ?? false
    }

    var dictionary: [String: Any] {
        ["latitude": latitude, "longitude": longitude, "lapLength": lapLength,
         "radius": radius, "rotation": rotation, "reverse": reverse]
    }

    /// The length of each of the two straight sections, excluding both bends.
    var straightLength: Double { (lapLength - Self.tau * radius) / 2 }

    /// Project an unrotated stadium-local offset to a WGS84 coordinate.
    func coordinate(localEast: Double, localNorth: Double) -> CLLocationCoordinate2D {
        let turn = rotation * .pi / 180
        let east = localEast * cos(turn) + localNorth * sin(turn)
        let north = -localEast * sin(turn) + localNorth * cos(turn)
        let angle = hypot(east, north) / Self.earthRadius
        let bearing = atan2(east, north)
        let lat = latitude * .pi / 180
        let lon = longitude * .pi / 180
        let targetLat = asin(Self.clamp(sin(lat) * cos(angle) + cos(lat) * sin(angle) * cos(bearing), -1, 1))
        let targetLon = lon + atan2(sin(bearing) * sin(angle) * cos(lat), cos(angle) - sin(lat) * sin(targetLat))
        return CLLocationCoordinate2D(latitude: targetLat * 180 / .pi,
                                      longitude: Self.wrapLongitude(targetLon * 180 / .pi))
    }

    /// Inverse spherical projection, including inverse stadium rotation.
    func localPoint(coordinate: CLLocationCoordinate2D) -> (east: Double, north: Double) {
        let lat = latitude * .pi / 180
        let targetLat = coordinate.latitude * .pi / 180
        let deltaLat = targetLat - lat
        let deltaLon = Self.wrapLongitude(coordinate.longitude - longitude) * .pi / 180
        let haversine = pow(sin(deltaLat / 2), 2) + cos(lat) * cos(targetLat) * pow(sin(deltaLon / 2), 2)
        let distance = Self.earthRadius * 2 * asin(sqrt(Self.clamp(haversine, 0, 1)))
        let bearing = atan2(sin(deltaLon) * cos(targetLat),
                            cos(lat) * sin(targetLat) - sin(lat) * cos(targetLat) * cos(deltaLon))
        let east = distance * sin(bearing)
        let north = distance * cos(bearing)
        let turn = rotation * .pi / 180
        return (east * cos(turn) - north * sin(turn),
                east * sin(turn) + north * cos(turn))
    }

    /// Even distance samples plus an exactly closed final coordinate.
    func points(samples: Int = 180) -> [CLLocationCoordinate2D] {
        let count = max(4, min(10_000, samples))
        var result = (0..<count).map { index -> CLLocationCoordinate2D in
            var distance = Double(index) / Double(count) * lapLength
            if reverse { distance = (lapLength - distance).truncatingRemainder(dividingBy: lapLength) }
            let point = localPosition(distance: distance)
            return coordinate(localEast: point.east, localNorth: point.north)
        }
        result.append(result[0])
        return result
    }

    /// A short-axis handle changes bend radius and preserves straight length.
    /// Existing sub-metre straights are raised to the editor's 1 m minimum.
    mutating func resizeWidth(at coordinate: CLLocationCoordinate2D) {
        let point = localPoint(coordinate: coordinate)
        guard point.east.isFinite else { return }
        let maximumStraight = (Self.maximumLap - Self.tau * Self.minimumResizeRadius) / 2
        let straight = Self.clamp(straightLength, Self.minimumStraight, maximumStraight)
        let minimumRadius = max(Self.minimumResizeRadius, (Self.minimumLap - 2 * straight) / Self.tau)
        let maximumRadius = min(Self.maximumRadius, (Self.maximumLap - 2 * straight) / Self.tau)
        radius = Self.clamp(abs(point.east), minimumRadius, maximumRadius)
        lapLength = Self.clamp(2 * straight + Self.tau * radius, Self.minimumLap, Self.maximumLap)
    }

    /// A long-axis handle changes straight length and preserves bend radius.
    /// The dragged point is the outer end of the semicircle, not its centre.
    mutating func resizeLength(at coordinate: CLLocationCoordinate2D) {
        let point = localPoint(coordinate: coordinate)
        guard point.north.isFinite else { return }
        radius = Self.clamp(radius, Self.minimumResizeRadius,
                            min(Self.maximumRadius, (Self.maximumLap - 2 * Self.minimumStraight) / Self.tau))
        let minimumStraight = max(Self.minimumStraight, (Self.minimumLap - Self.tau * radius) / 2)
        let maximumStraight = (Self.maximumLap - Self.tau * radius) / 2
        let straight = Self.clamp(2 * (abs(point.north) - radius), minimumStraight, maximumStraight)
        lapLength = Self.clamp(2 * straight + Self.tau * radius, Self.minimumLap, Self.maximumLap)
    }

    static func normalizedRotation(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    private func localPosition(distance: Double) -> (east: Double, north: Double) {
        let straight = straightLength
        if distance <= straight {
            return (radius, -straight / 2 + distance)
        } else if distance <= straight + .pi * radius {
            let angle = (distance - straight) / radius
            return (radius * cos(angle), straight / 2 + radius * sin(angle))
        } else if distance <= 2 * straight + .pi * radius {
            return (-radius, straight / 2 - (distance - straight - .pi * radius))
        }
        let angle = .pi + (distance - 2 * straight - .pi * radius) / radius
        return (radius * cos(angle), -straight / 2 + radius * sin(angle))
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        max(lower, min(upper, value))
    }

    private static func wrapLongitude(_ degrees: Double) -> Double {
        let wrapped = (degrees + 180).truncatingRemainder(dividingBy: 360)
        return (wrapped < 0 ? wrapped + 360 : wrapped) - 180
    }
}
