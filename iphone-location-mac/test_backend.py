import asyncio
from unittest import IsolatedAsyncioTestCase
from unittest.mock import AsyncMock, patch

import backend

CONFIG = dict(latitude=30.87707, longitude=121.9, lapLength=400,
              radius=36.5, laps=1, pace=360, rotation=0, cadence=160)


class SessionTests(IsolatedAsyncioTestCase):
    async def test_invalid_input_never_connects_or_changes_device(self):
        session = backend.DeviceSession()
        session.connect = AsyncMock()
        with self.assertRaises(ValueError):
            await session.set(float('nan'), 121)
        with self.assertRaises(ValueError):
            await session.start(dict(CONFIG, radius=100))
        session.connect.assert_not_awaited()

    async def test_restoring_cancels_pending_route_before_clear(self):
        entered = asyncio.Event()
        writes = []

        async def set_location(*args):
            writes.append('set')
            entered.set()
            await asyncio.Event().wait()

        async def clear():
            writes.append('clear')

        session = backend.DeviceSession()
        session.location = AsyncMock()
        session.location.set.side_effect = set_location
        session.location.clear.side_effect = clear
        with patch.object(backend, 'emit'):
            await session.start(CONFIG)
            await asyncio.wait_for(entered.wait(), 1)
            await session.restore()
            await asyncio.sleep(0)
        self.assertEqual(writes, ['set', 'clear'])
        self.assertIsNone(session.route)
        self.assertFalse(session.modified)

    async def test_location_failure_stops_and_attempts_restore(self):
        session = backend.DeviceSession()
        session.location = AsyncMock()
        session.location.set.side_effect = RuntimeError('disconnected')
        with patch.object(backend, 'emit') as emit:
            await session.start(CONFIG)
            await asyncio.wait_for(session.route, 1)
        session.location.clear.assert_awaited_once()
        self.assertFalse(session.modified)
        self.assertIn('error', [c.args[0] for c in emit.call_args_list])

    async def test_quit_clears_only_if_simulation_was_modified(self):
        session = backend.DeviceSession()
        session.location = AsyncMock()
        location = session.location
        with patch.object(backend, 'emit'):
            await session.close()
        location.clear.assert_not_awaited()
        session.location = location
        session.modified = True
        with patch.object(backend, 'emit'):
            await session.close()
        location.clear.assert_awaited_once()

    async def test_missing_selected_device_cannot_report_connected(self):
        session = backend.DeviceSession()
        with patch.object(backend, 'discover_devices', AsyncMock(return_value=[])), patch.object(backend, 'emit') as emit:
            with self.assertRaises(ValueError):
                await session.connect('not-connected')
            emit.assert_not_called()
        self.assertIsNone(session.location)

    async def test_switching_devices_during_simulation_requires_restore(self):
        session = backend.DeviceSession()
        session.location = AsyncMock()
        session.serial = 'first-phone'
        session.modified = True
        with self.assertRaises(ValueError):
            await session.connect('second-phone')
        self.assertEqual(session.serial, 'first-phone')
        session.location.clear.assert_not_awaited()

    async def test_map_route_invalid_input_never_reaches_device(self):
        session = backend.DeviceSession()
        session.connect = AsyncMock()
        with self.assertRaises(ValueError):
            await session.start(dict(mode='polyline', points=[[30, 121]], pace=360))
        session.connect.assert_not_awaited()
