import Foundation
import CoreLocation

/// Pure geometry checks; this file has no entry point and is not part of the app.
enum TrackGeometryCheck {
    static func run() -> [String: Bool] {
        let base: [String: Any] = ["latitude": 39.99, "longitude": 116.39,
                                   "lapLength": 400.0, "radius": 36.5,
                                   "rotation": 0.0, "reverse": false]
        var results: [String: Bool] = [:]
        guard var track = TrackGeometry(dictionary: base) else { return ["initialization": false] }
        func close(_ a: Double, _ b: Double, tolerance: Double = 1e-8) -> Bool { abs(a - b) < tolerance }
        func valid(_ track: TrackGeometry) -> Bool {
            TrackGeometry(dictionary: track.dictionary) != nil && track.straightLength >= 1 - 1e-8 &&
                (50...2_000).contains(track.lapLength) && (1...300).contains(track.radius)
        }
        let points = track.points()
        results["closed-181-points"] = points.count == 181 &&
            points.first!.latitude == points.last!.latitude && points.first!.longitude == points.last!.longitude
        // Golden coordinates from the independent Python runtime geometry.
        results["python-zero-degrees"] = close(points[0].latitude, 39.989616295777815) &&
            close(points[0].longitude, 116.39042843732045) &&
            close(points[45].latitude, 39.99051209422178) && close(points[45].longitude, 116.39039430995763)
        track.rotation = 90
        let rotated = track.points()
        results["python-ninety-degrees"] = close(rotated[0].latitude, 39.98967174698955) &&
            close(rotated[0].longitude, 116.38949918648484) &&
            close(rotated[45].latitude, 39.98969789716137) && close(rotated[45].longitude, 116.39066839156942)
        var inverseOK = true
        for rotation in [0.0, 37.0, 90.0, 270.0] {
            track.rotation = rotation
            for (east, north) in [(0.0, 0.0), (36.5, -42.66593443177294), (-500.0, 840.0)] {
                let result = track.localPoint(coordinate: track.coordinate(localEast: east, localNorth: north))
                inverseOK = inverseOK && close(result.east, east, tolerance: 1e-5) && close(result.north, north, tolerance: 1e-5)
            }
        }
        results["spherical-rotation-round-trip"] = inverseOK
        track.rotation = 90
        let northEnd = track.coordinate(localEast: 0, localNorth: 100)
        results["positive-rotation-clockwise"] = northEnd.longitude > track.longitude && abs(northEnd.latitude - track.latitude) < 1e-6
        track.rotation = -450
        results["rotation-normalized"] = track.rotation == 270
        track.reverse = true
        let reversed = track.points()
        track.reverse = false
        let forward = track.points()
        results["reverse-same-outline"] = close(reversed[45].latitude, forward[135].latitude) && close(reversed[45].longitude, forward[135].longitude)
        let originalStraight = track.straightLength
        track.resizeWidth(at: track.coordinate(localEast: 50, localNorth: 0))
        results["resize-width-preserves-straight"] = close(track.radius, 50, tolerance: 1e-5) && close(track.straightLength, originalStraight, tolerance: 1e-5)
        let originalRadius = track.radius
        track.resizeLength(at: track.coordinate(localEast: 0, localNorth: 120))
        results["resize-length-preserves-radius"] = close(track.radius, originalRadius) && close(track.straightLength, 140, tolerance: 1e-5)
        var boundsOK = true
        for offset in [0.0, 1.0, 100.0, 50_000.0] {
            track.resizeWidth(at: track.coordinate(localEast: offset, localNorth: 0))
            boundsOK = boundsOK && valid(track)
            track.resizeLength(at: track.coordinate(localEast: 0, localNorth: offset))
            boundsOK = boundsOK && valid(track)
        }
        results["resize-valid-clamps"] = boundsOK
        var invalidOK = true
        for (key, value) in [("latitude", Double.nan as Any), ("latitude", 86.0),
                             ("longitude", 181.0), ("lapLength", 49.0),
                             ("lapLength", 2_001.0), ("radius", 0.0),
                             ("radius", 0.5), ("radius", 301.0),
                             ("radius", 100.0), ("latitude", true), ("reverse", 1)] {
            var invalid = base
            invalid[key] = value
            invalidOK = invalidOK && TrackGeometry(dictionary: invalid) == nil
        }
        results["reject-invalid-geometry"] = invalidOK
        var shortStraight = base
        shortStraight["lapLength"] = 2 * Double.pi * 36.5 + 1
        results["reject-submetre-straight"] = TrackGeometry(dictionary: shortStraight) == nil
        var roundedBoundary = base
        let boundaryRadius = 36.506
        roundedBoundary["radius"] = (boundaryRadius * 1_000_000).rounded() / 1_000_000
        roundedBoundary["lapLength"] = ((2 * .pi * boundaryRadius + 2) * 1_000_000).rounded() / 1_000_000
        results["accept-six-decimal-boundary"] = TrackGeometry(dictionary: roundedBoundary) != nil
        roundedBoundary["lapLength"] = 2 * .pi * boundaryRadius + 1
        results["reject-half-metre-straight"] = TrackGeometry(dictionary: roundedBoundary) == nil
        var boundary = base
        boundary["latitude"] = 85.0
        boundary["longitude"] = 179.999
        boundary["rotation"] = 90.0
        if let nearDateline = TrackGeometry(dictionary: boundary) {
            let target = nearDateline.coordinate(localEast: 0, localNorth: 1_000)
            let inverse = nearDateline.localPoint(coordinate: target)
            results["dateline-round-trip"] = target.longitude < 0 && close(inverse.east, 0, tolerance: 1e-5) && close(inverse.north, 1_000, tolerance: 1e-5)
        } else { results["dateline-round-trip"] = false }
        return results
    }
}
