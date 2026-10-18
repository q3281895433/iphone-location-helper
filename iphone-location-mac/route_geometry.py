"""Deterministic stadium-track geometry and elapsed-time workout calculations."""
import math
from bisect import bisect_right

EARTH_M = 6371008.8


def finite(value, name, lower, upper):
    if isinstance(value, bool):
        raise ValueError(f'{name}不是有效数值')
    try:
        value = float(value)
    except (TypeError, ValueError):
        raise ValueError(f'{name}不是有效数值') from None
    if not math.isfinite(value) or not lower <= value <= upper:
        raise ValueError(f'{name}应在 {lower:g}～{upper:g} 之间')
    return value


def validate(config):
    c = dict(config)
    c['pace'] = finite(c.get('pace'), '配速（秒/公里）', 120, 1800)
    c['cadence'] = finite(c.get('cadence', 160), '模拟步频', 1, 300)
    if c.get('mode') == 'polyline':
        points = c.get('points')
        if not isinstance(points, list) or not 2 <= len(points) <= 2000:
            raise ValueError('请在地图选择起点、终点，可添加途经点（最多 2000 点）')
        cleaned, distances = [], [0.0]
        for point in points:
            if not isinstance(point, (list, tuple)) or len(point) != 2:
                raise ValueError('路线坐标格式无效')
            point = (finite(point[0], '纬度', -85, 85), finite(point[1], '经度', -180, 180))
            if cleaned:
                length = haversine(cleaned[-1], point)
                if length < 0.05:
                    continue
                distances.append(distances[-1] + length)
            cleaned.append(point)
        if len(cleaned) < 2 or distances[-1] < 1:
            raise ValueError('路线长度至少为 1 米，请分开选择起点和终点')
        if distances[-1] > 200000:
            raise ValueError('地图路线不能超过 200 公里')
        c.update(points=cleaned, distances=distances, totalDistance=distances[-1],
                 lapLength=distances[-1], laps=1)
        c['duration'] = c['totalDistance'] * c['pace'] / 1000
        if c['duration'] > 86400:
            raise ValueError('一次路线时长不能超过 24 小时')
        return c
    if c.get('mode', 'stadium') != 'stadium':
        raise ValueError('未知路线模式')
    c['latitude'] = finite(c.get('latitude'), '纬度', -85, 85)
    c['longitude'] = finite(c.get('longitude'), '经度', -180, 180)
    c['lapLength'] = finite(c.get('lapLength'), '每圈长度', 50, 2000)
    c['radius'] = finite(c.get('radius'), '弯道半径', 1, 300)
    if 2 * math.pi * c['radius'] >= c['lapLength']:
        raise ValueError('弯道半径过大，无法组成指定周长的跑道')
    c['laps'] = finite(c.get('laps'), '圈数', 0.1, 100)
    c['pace'] = finite(c.get('pace'), '配速（秒/公里）', 120, 1800)
    c['rotation'] = finite(c.get('rotation', 0), '旋转角度', -360, 360)
    c['cadence'] = finite(c.get('cadence', 160), '模拟步频', 1, 300)
    if not isinstance(c.get('reverse', False), bool):
        raise ValueError('方向配置无效')
    c['reverse'] = c.get('reverse', False)
    c['totalDistance'] = c['lapLength'] * c['laps']
    c['duration'] = c['totalDistance'] * c['pace'] / 1000
    if c['duration'] > 86400:
        raise ValueError('一次跑圈时长不能超过 24 小时')
    return c


def coordinate(config, distance):
    if config.get('mode') == 'polyline':
        points, lengths = config['points'], config['distances']
        if distance <= 0:
            return points[0]
        if distance >= lengths[-1]:
            return points[-1]
        index = min(bisect_right(lengths, distance) - 1, len(points) - 2)
        ratio = (distance - lengths[index]) / (lengths[index + 1] - lengths[index])
        lat1, lon1 = map(math.radians, points[index])
        lat2, lon2 = map(math.radians, points[index + 1])
        angle = (lengths[index + 1] - lengths[index]) / EARTH_M
        a, b = math.sin((1 - ratio) * angle) / math.sin(angle), math.sin(ratio * angle) / math.sin(angle)
        x = a * math.cos(lat1) * math.cos(lon1) + b * math.cos(lat2) * math.cos(lon2)
        y = a * math.cos(lat1) * math.sin(lon1) + b * math.cos(lat2) * math.sin(lon2)
        z = a * math.sin(lat1) + b * math.sin(lat2)
        return math.degrees(math.atan2(z, math.hypot(x, y))), math.degrees(math.atan2(y, x))
    radius, length = config['radius'], config['lapLength']
    straight = (length - 2 * math.pi * radius) / 2
    d = distance % length
    if config['reverse']:
        d = (-d) % length
    if d <= straight:
        x, y = radius, -straight / 2 + d
    elif d <= straight + math.pi * radius:
        a = (d - straight) / radius
        x, y = radius * math.cos(a), straight / 2 + radius * math.sin(a)
    elif d <= 2 * straight + math.pi * radius:
        x, y = -radius, straight / 2 - (d - straight - math.pi * radius)
    else:
        a = math.pi + (d - 2 * straight - math.pi * radius) / radius
        x, y = radius * math.cos(a), -straight / 2 + radius * math.sin(a)
    turn = math.radians(config['rotation'])
    east, north = x * math.cos(turn) + y * math.sin(turn), -x * math.sin(turn) + y * math.cos(turn)
    lat, lon = math.radians(config['latitude']), math.radians(config['longitude'])
    angle, bearing = math.hypot(east, north) / EARTH_M, math.atan2(east, north)
    target_lat = math.asin(math.sin(lat) * math.cos(angle) + math.cos(lat) * math.sin(angle) * math.cos(bearing))
    target_lon = lon + math.atan2(math.sin(bearing) * math.sin(angle) * math.cos(lat), math.cos(angle) - math.sin(lat) * math.sin(target_lat))
    return math.degrees(target_lat), (math.degrees(target_lon) + 540) % 360 - 180


def haversine(first, second):
    lat1, lon1 = map(math.radians, first)
    lat2, lon2 = map(math.radians, second)
    a = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return EARTH_M * 2 * math.asin(math.sqrt(min(1, max(0, a))))


def sample(config, elapsed):
    elapsed = min(config['duration'], max(0, elapsed))
    distance = min(config['totalDistance'], elapsed * 1000 / config['pace'])
    lat, lon = coordinate(config, distance)
    return {'latitude': lat, 'longitude': lon, 'distance': distance,
            'elapsed': elapsed, 'fraction': distance / config['totalDistance'],
            'lapProgress': distance / config['lapLength'],
            'simulatedSteps': math.floor(elapsed * config['cadence'] / 60 + 1e-8),
            'finished': elapsed >= config['duration']}
