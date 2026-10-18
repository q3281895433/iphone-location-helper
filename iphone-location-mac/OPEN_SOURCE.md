# 上游来源与本地修改

本项目将开源地图库与设备库集成到现有 macOS AppKit 窗口中；不属于下列项目的官方发行版。

## Leaflet 1.9.4

- GitHub：https://github.com/Leaflet/Leaflet/tree/v1.9.4
- 已检查源码标签 `v1.9.4`，提交 `d15112c9e8ac339f0f74f563959d0423d291308d`。
- 本地运行资源来自官方 npm 包 `leaflet@1.9.4`，npm shasum `23fae724e282fa25745aff82ca4d394748db7d8d`。
- 原始 BSD-2-Clause 许可证保存在 `map/vendor/LICENSE`。库文件未经修改；本地 `map/index.html`、`map/map.js`、`map/map.css` 和 `MapCanvas.swift` 增加了起终点、途经点、拖动编辑、锁定、轨迹显示及原生窗口通信。
- 底图由 OpenStreetMap 提供，界面保留版权署名。使用标准 HTTPS 瓦片 URL、独立应用 User-Agent 与 WebKit 默认 HTTP 缓存，仅加载当前地图视口，不预抓取或批量下载。

## pymobiledevice3 11.34.1

- GitHub：https://github.com/doronz88/pymobiledevice3/tree/v11.34.1
- requirements.txt 固定依赖版本，setup.command 将其安装到本地 `.venv`；虚拟环境不提交到仓库。遵循其 GPL-3.0-or-later 许可证；运行库保留发行包许可证和元数据。
- 本地 `backend.py` 调用真实 USB 枚举、lockdown 只读设备信息、按所选设备标识连接 `NativeRemotedTunnel`，再使用 DVT 位置模拟服务。
- 没有添加演示设备或伪造“已连接”状态。未连接时明确显示无设备；自动测试中的替代对象不会用于正式运行。

## 本地校验

地点搜索使用 OpenStreetMap Nominatim 的标准 HTTPS Search API。仅提交用户主动输入的查询，每次请求至少间隔 1.1 秒，使用独立应用 User-Agent、HTTP 缓存与会话缓存；结果和地图均保留 OpenStreetMap 来源说明。服务地址可以在 `map/search-provider.json` 中修改。

应用图标由本地 `IconPainter.swift` 使用 AppKit 几何图形绘制，构建时生成 16～1024 像素多分辨率 ICNS，不包含下载的第三方图标素材。

在此文件夹运行 `.venv/bin/python3 -B -m unittest test_route_geometry test_backend`。
原生窗口运行 `--map-check 报告路径` 时只加载地图并进行选点、途经点、锁定、撤销、模式切换检查，不启动设备后台。
