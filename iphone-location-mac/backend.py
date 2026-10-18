"""JSON-lines bridge for the native Mac app. Device changes require commands."""
import asyncio
from contextlib import AsyncExitStack
import json
import math
import sys
import time

from route_geometry import finite, sample, validate


def emit(event, **data):
    print(json.dumps({'event': event, **data}, ensure_ascii=False), flush=True)


async def discover_devices():
    """Read real USB devices; do not pair or modify location during discovery."""
    from pymobiledevice3.usbmux import list_devices
    from pymobiledevice3.lockdown import create_using_usbmux
    devices = []
    for device in await asyncio.wait_for(list_devices(), 8):
        if not device.is_usb:
            continue
        info = {'udid': device.serial, 'name': 'iPhone / iPad', 'connection': 'USB'}
        try:
            client = await asyncio.wait_for(create_using_usbmux(
                serial=device.serial, connection_type='USB', autopair=False), 8)
            async with client:
                values = client.all_values
                info.update(name=values.get('DeviceName', 'iPhone / iPad'),
                            ios=values.get('ProductVersion', ''),
                            product=values.get('ProductType', ''), trusted=True)
        except Exception as error:
            info.update(trusted=False, detail=f'请解锁并信任此 Mac：{type(error).__name__}')
        devices.append(info)
    return devices


class DeviceSession:
    def __init__(self):
        self.stack = None
        self.location = None
        self.route = None
        self.config = None
        self.elapsed = 0.0
        self.paused = False
        self.modified = False
        self.resume_time = 0.0
        self.serial = None
        self.device_info = {}

    async def connect(self, serial=None):
        if self.location is not None and serial and self.serial != serial:
            if self.modified:
                raise ValueError('请先恢复当前手机的真实定位，再切换设备')
            await self.close()
        if self.location is not None:
            emit('connected', device=self.device_info)
            return
        devices = await discover_devices()
        serial = serial or self.serial
        if serial is None:
            if len(devices) != 1:
                raise ValueError('请连接并在列表中选择一台真实 USB 设备')
            serial = devices[0]['udid']
        selected = next((d for d in devices if d['udid'] == serial), None)
        if selected is None:
            raise ValueError('所选手机已断开，请重新连接 USB 并刷新设备')
        if not selected.get('trusted'):
            raise ValueError(selected.get('detail', '请解锁并信任此 Mac'))
        from pymobiledevice3.remote.native_tunnel import NativeRemotedTunnel
        from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
        from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation
        stack = AsyncExitStack()
        try:
            rsd = await asyncio.wait_for(stack.enter_async_context(NativeRemotedTunnel(serial=serial)), 25)
            if rsd.udid.replace('-', '') != serial.replace('-', ''):
                raise RuntimeError('设备身份与所选 USB 设备不一致，已取消连接')
            dvt = await asyncio.wait_for(stack.enter_async_context(DvtProvider(rsd)), 15)
            location = await asyncio.wait_for(stack.enter_async_context(LocationSimulation(dvt)), 15)
        except BaseException:
            await stack.aclose()
            raise
        self.stack, self.location = stack, location
        self.serial, self.device_info = serial, selected
        emit('connected', device=selected)

    async def stop_route(self):
        if self.route:
            task, self.route = self.route, None
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass

    async def set(self, latitude, longitude):
        lat = finite(latitude, '纬度', -90, 90)
        lon = finite(longitude, '经度', -180, 180)
        await self.connect()
        # Set before stopping a running route only after validation; the caller
        # serializes commands, and stop_route cancels in-flight route operations.
        await self.stop_route()
        self.modified = True
        await asyncio.wait_for(self.location.set(lat, lon), 10)
        emit('fixed', latitude=lat, longitude=lon)

    async def restore(self):
        await self.stop_route()
        await self.connect()
        await asyncio.wait_for(self.location.clear(), 10)
        self.modified = False
        self.config = None
        emit('restored')

    async def start(self, raw):
        config = validate(raw)
        await self.connect()
        await self.stop_route()
        self.config, self.elapsed, self.paused = config, 0.0, False
        self.resume_time = time.monotonic()
        self.route = asyncio.create_task(self.run_route())
        emit('route_started', duration=config['duration'], totalDistance=config['totalDistance'])

    async def run_route(self):
        try:
            while True:
                now = time.monotonic()
                if not self.paused:
                    point = sample(self.config, self.elapsed + now - self.resume_time)
                    self.modified = True
                    await asyncio.wait_for(self.location.set(point['latitude'], point['longitude']), 10)
                    emit('progress', **point)
                    if point['finished']:
                        emit('route_finished')
                        # Keep the connection alive at the finish until restore.
                        return
                await asyncio.sleep(1)
        except asyncio.CancelledError:
            raise
        except Exception as error:
            emit('error', message=f'路线已停止：{type(error).__name__}: {error}')
            emit('route_stopped')
            try:
                await asyncio.wait_for(self.location.clear(), 10)
                self.modified = False
                emit('restored')
            except Exception:
                emit('error', message='自动恢复未确认，请重新连接并点击“恢复真实定位”。')

    async def close(self):
        await self.stop_route()
        if self.location and self.modified:
            try:
                await asyncio.wait_for(self.location.clear(), 10)
                emit('restored')
            except Exception:
                emit('error', message='退出时未能确认恢复定位，请重新连接后恢复。')
        if self.stack:
            await self.stack.aclose()
        self.stack = self.location = None


async def main():
    session = DeviceSession()
    emit('ready')
    try:
        while True:
            line = await asyncio.to_thread(sys.stdin.readline)
            if not line:
                break
            try:
                data = json.loads(line)
                action = data.get('action')
                if action == 'devices':
                    emit('devices', devices=await discover_devices())
                elif action == 'connect':
                    await session.connect(data.get('udid'))
                elif action == 'set':
                    await session.set(data.get('latitude'), data.get('longitude'))
                elif action == 'start':
                    await session.start(data.get('config', {}))
                elif action in ('pause', 'resume'):
                    if not session.route or session.route.done():
                        raise ValueError('没有正在运行的跑圈会话')
                    if action == 'pause' and not session.paused:
                        session.elapsed += time.monotonic() - session.resume_time
                    elif action == 'resume' and session.paused:
                        session.resume_time = time.monotonic()
                    session.paused = action == 'pause'
                    emit('paused' if session.paused else 'resumed')
                elif action == 'restore':
                    await session.restore()
                elif action == 'quit':
                    break
                else:
                    raise ValueError('未知操作')
            except Exception as error:
                emit('error', message=f'{type(error).__name__}: {error}')
    finally:
        await session.close()
        emit('closed')


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
