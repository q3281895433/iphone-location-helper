import Foundation
import CoreLocation

/// Pure conversion checks. No device connection or location changes occur.
enum CoordinateTransformCheck {
    static func run() -> [String: Bool] {
        var results: [String: Bool] = [:]
        let beijingGPS = CLLocationCoordinate2D(latitude: 39.908823, longitude: 116.397470)
        let shanghaiGPS = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
        // Fixed outputs from an independent public implementation of the
        // 6378245 / 0.00669342162296594323 forward-model constants.
        let beijingMap = CLLocationCoordinate2D(latitude: 39.91022649807321, longitude: 116.4037135824225)
        let shanghaiMap = CLLocationCoordinate2D(latitude: 31.22845773757727, longitude: 121.47822305927693)

        func same(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
            a.latitude == b.latitude && a.longitude == b.longitude
        }
        func close(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
            abs(a.latitude - b.latitude) < 1e-10 && abs(a.longitude - b.longitude) < 1e-10
        }
        func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
            let radians = Double.pi / 180
            let deltaLatitude = (a.latitude - b.latitude) * radians
            let deltaLongitude = (a.longitude - b.longitude) * radians
            let h = pow(sin(deltaLatitude / 2), 2) + cos(a.latitude * radians) *
                cos(b.latitude * radians) * pow(sin(deltaLongitude / 2), 2)
            return 6_371_008.8 * 2 * asin(sqrt(max(0, min(1, h))))
        }

        results["gcj-forward-beijing-golden"] = close(CoordinateTransform.toMap(beijingGPS, mode: .mainlandGCJ02), beijingMap)
        results["gcj-forward-shanghai-golden"] = close(CoordinateTransform.toMap(shanghaiGPS, mode: .mainlandGCJ02), shanghaiMap)
        results["gcj-inverse-beijing-under-10cm"] = distance(CoordinateTransform.toGPS(beijingMap, mode: .mainlandGCJ02), beijingGPS) < 0.1
        results["gcj-inverse-shanghai-under-10cm"] = distance(CoordinateTransform.toGPS(shanghaiMap, mode: .mainlandGCJ02), shanghaiGPS) < 0.1
        results["wgs84-forward-pass-through"] = same(CoordinateTransform.toMap(beijingGPS, mode: .wgs84), beijingGPS)
        results["wgs84-inverse-pass-through"] = same(CoordinateTransform.toGPS(shanghaiGPS, mode: .wgs84), shanghaiGPS)
        for (name, coordinate) in [
            ("paris", CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)),
            ("london", CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278))
        ] {
            results["outside-box-\(name)-pass-through"] =
                same(CoordinateTransform.toMap(coordinate, mode: .mainlandGCJ02), coordinate) &&
                same(CoordinateTransform.toGPS(coordinate, mode: .mainlandGCJ02), coordinate)
        }

        var invalidPreserved = true
        for mode in [MapCoordinateMode.mainlandGCJ02, .wgs84] {
            let invalidLatitude = CLLocationCoordinate2D(latitude: .nan, longitude: 116.4)
            let invalidLongitude = CLLocationCoordinate2D(latitude: 31.2, longitude: .nan)
            for transform in [CoordinateTransform.toMap, CoordinateTransform.toGPS] {
                let latitudeResult = transform(invalidLatitude, mode)
                let longitudeResult = transform(invalidLongitude, mode)
                invalidPreserved = invalidPreserved && latitudeResult.latitude.isNaN &&
                    latitudeResult.longitude == 116.4 && longitudeResult.latitude == 31.2 &&
                    longitudeResult.longitude.isNaN
            }
        }
        results["nan-components-remain-invalid"] = invalidPreserved
        let infinite = CLLocationCoordinate2D(latitude: .infinity, longitude: 116.4)
        results["infinity-remains-invalid"] =
            same(CoordinateTransform.toMap(infinite, mode: .mainlandGCJ02), infinite) &&
            same(CoordinateTransform.toGPS(infinite, mode: .mainlandGCJ02), infinite)
        let outOfRange = CLLocationCoordinate2D(latitude: 91, longitude: 181)
        results["out-of-range-remains-invalid"] =
            same(CoordinateTransform.toMap(outOfRange, mode: .mainlandGCJ02), outOfRange) &&
            same(CoordinateTransform.toGPS(outOfRange, mode: .mainlandGCJ02), outOfRange)

        var gridRoundTrip = true
        for latitude in [5.0, 20, 31, 40, 50] {
            for longitude in [80.0, 95, 110, 121, 130] {
                let original = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                let map = CoordinateTransform.toMap(original, mode: .mainlandGCJ02)
                gridRoundTrip = gridRoundTrip && distance(original, CoordinateTransform.toGPS(map, mode: .mainlandGCJ02)) < 0.1
            }
        }
        results["model-grid-round-trip-under-10cm"] = gridRoundTrip

        let trackValues: [String: Any] = ["latitude": shanghaiGPS.latitude, "longitude": shanghaiGPS.longitude,
                                        "lapLength": 400.0, "radius": 36.5, "rotation": 37.0, "reverse": false]
        if let track = TrackGeometry(dictionary: trackValues) {
            let original = track.points(samples: 180)
            let mapped = original.map { CoordinateTransform.toMap($0, mode: .mainlandGCJ02) }
            let restored = mapped.map { CoordinateTransform.toGPS($0, mode: .mainlandGCJ02) }
            results["track-180-samples-remain-closed"] = mapped.count == 181 && same(mapped[0], mapped[180])
            results["track-converted-points-continuous"] = zip(mapped, mapped.dropFirst()).allSatisfy {
                let step = distance($0.0, $0.1)
                return step.isFinite && step > 1 && step < 4
            }
            results["track-all-points-return-under-10cm"] = zip(original, restored).allSatisfy { distance($0.0, $0.1) < 0.1 }
            results["track-points-are-converted"] = zip(original, mapped).allSatisfy { distance($0.0, $0.1) > 100 }
        } else {
            for name in ["track-180-samples-remain-closed", "track-converted-points-continuous",
                         "track-all-points-return-under-10cm", "track-points-are-converted"] { results[name] = false }
        }
        return results
    }
}
