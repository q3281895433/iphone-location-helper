import unittest
from route_geometry import coordinate, haversine, sample, validate


def config(**changes):
    c = dict(latitude=30.87707, longitude=121.9, lapLength=400,
             radius=36.5, laps=5, pace=360, rotation=0, cadence=160)
    c.update(changes)
    return validate(c)


class RouteTests(unittest.TestCase):
    def test_workout_duration_distance_and_simulated_steps(self):
        c = config()
        p = sample(c, 99999)
        self.assertAlmostEqual(c['duration'], 720)
        self.assertAlmostEqual(p['distance'], 2000)
        self.assertEqual(p['simulatedSteps'], 1920)
        self.assertTrue(p['finished'])

    def test_closed_integer_laps(self):
        c = config()
        start, end = sample(c, 0), sample(c, c['duration'])
        self.assertAlmostEqual(start['latitude'], end['latitude'])
        self.assertAlmostEqual(start['longitude'], end['longitude'])

    def test_reverse_direction_and_rotation(self):
        forward, reverse = config(), config(reverse=True)
        origin = sample(forward, 0)
        self.assertGreater(sample(forward, 1)['latitude'], origin['latitude'])
        self.assertLess(sample(reverse, 1)['latitude'], origin['latitude'])
        rotated = sample(config(rotation=90), 0)
        self.assertNotAlmostEqual(rotated['latitude'], origin['latitude'])

    def test_pace_scales_distance(self):
        self.assertAlmostEqual(sample(config(pace=300), 60)['distance'], 200)
        self.assertAlmostEqual(sample(config(pace=600), 60)['distance'], 100)

    def test_invalid_values(self):
        for change in [dict(radius=100), dict(latitude=float('nan')), dict(pace=0), dict(laps=-1), dict(reverse='yes')]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                config(**change)


class MapRouteTests(unittest.TestCase):
    def route(self, points):
        return validate(dict(mode='polyline', points=points, pace=360, cadence=160))

    def test_route_passes_waypoint_and_finishes_at_selected_endpoint(self):
        points = [[30.877, 121.9], [30.877, 121.902], [30.879, 121.902]]
        c = self.route(points)
        self.assertEqual(coordinate(c, 0), tuple(points[0]))
        waypoint = coordinate(c, c['distances'][1])
        self.assertLess(haversine(waypoint, points[1]), 0.001)
        end = sample(c, c['duration'] + 100)
        self.assertEqual([end['latitude'], end['longitude']], points[-1])
        self.assertTrue(end['finished'])
        self.assertAlmostEqual(end['distance'], c['totalDistance'])
        self.assertAlmostEqual(c['duration'], c['totalDistance'] * 0.36)

    def test_distance_based_interpolation_on_unequal_segments(self):
        c = self.route([[0, 0], [0, 0.001], [0.003, 0.001]])
        point = coordinate(c, c['totalDistance'] / 2)
        self.assertAlmostEqual(point[0], 0.001, places=7)
        self.assertAlmostEqual(point[1], 0.001, places=7)

    def test_duplicate_points_removed_without_division_by_zero(self):
        c = self.route([[30, 121], [30, 121], [30.001, 121]])
        self.assertEqual(len(c['points']), 2)
        self.assertTrue(all(isinstance(v, float) for v in coordinate(c, c['totalDistance'] / 2)))

    def test_antimeridian_uses_short_route(self):
        c = self.route([[0, 179.999], [0, -179.999]])
        self.assertLess(c['totalDistance'], 225)
        self.assertAlmostEqual(abs(coordinate(c, c['totalDistance'] / 2)[1]), 180)

    def test_invalid_routes_rejected(self):
        for points in [[], [[30, 121]], [[30, 121], [30, 121]], [[30, 121], [float('nan'), 121]],
                       [[30, 121], [30, 181]], [[30, 121], [40, 121]], ['bad', [30, 121]]]:
            with self.subTest(points=points), self.assertRaises(ValueError):
                self.route(points)


if __name__ == '__main__':
    unittest.main()
