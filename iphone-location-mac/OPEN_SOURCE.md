# 定位助手 0.5.1 · 上游来源与本地修改

本项目在 macOS AppKit 窗口中使用系统 MapKit 与开源设备库；不属于下列项目的官方发行版。

## Apple MapKit

- 0.5 运行地图使用系统原生 [MKMapView](https://developer.apple.com/documentation/mapkit/mkmapview)，支持 [MKImageryMapConfiguration 卫星影像](https://developer.apple.com/documentation/mapkit/mkimagerymapconfiguration)与 [MKHybridMapConfiguration 混合地图](https://developer.apple.com/documentation/mapkit/mkhybridmapconfiguration)。不复制 Apple 地图库或影像数据；保留系统地图的来源署名。
- 本地 `MapCanvas.swift` 实现起终点、途经点、路线显示和跑道编辑。紫色手柄移动中心，两个橙色手柄调整长轴与短轴，青色手柄调整朝向；与周长、半径、旋转角输入双向同步，运行时锁定编辑。旋转角 0° 为长轴朝北，90° 为长轴朝东。
- 后端、手工坐标输入、Nominatim 搜索结果与路线配置始终使用 WGS84。Apple 的 [CLLocationCoordinate2D 定义](https://developer.apple.com/documentation/corelocation/cllocationcoordinate2d)采用 WGS84；[高德坐标说明](https://developer.amap.com/api/javascript-api-v2/guide/transform/convertfrom)说明其地图使用 GCJ-02。仅凭类型名称不能替代当前底图与真机落点核对。

## 0.5.1 坐标适配修改

- 新增显式手动选项“大陆底图校正 GCJ02”（默认）和“原始 WGS84”，不声称自动检测 MapKit 当前数据源、用户所在地区或国界。
- 校正模式下，地图点击和拖动在进入应用数据前转换为 WGS84；绘制路线、搜索标记、发送位置回显与适应路线时，再转换到地图坐标。原始模式不做这些坐标转换。固定定位和路线后台只接收 WGS84。
- 切换模式保留已选 GPS 坐标，只重新投影；不会自动更正先前的错误选点。应用不保存旧路线，升级后需重新选操场；先用固定定位在 iPhone 自带“地图”中核对，再开始跑圈。
- GCJ-02 转换采用本地实现的公开近似模型，不是 Apple 或高德提供的坐标精度承诺。经纬度包围框只是粗略适用范围，不能准确排除港澳台及邻国；国外与非大陆底图应使用“原始 WGS84”。
- 内部数值往返回归小于 0.1 米，只证明近似模型的正反计算相容，不证明真实地图、手机 GPS 或第三方应用的精度。桌面蓝点是已发送值，不是手机实际位置读回；本版不能声称已经消除用户报告的真机偏移。

## Leaflet 1.9.4（0.4 历史集成）

- GitHub：https://github.com/Leaflet/Leaflet/tree/v1.9.4
- 已检查源码标签 `v1.9.4`，提交 `d15112c9e8ac339f0f74f563959d0423d291308d`。
- 0.4 使用的资源来自官方 npm 包 `leaflet@1.9.4`，npm shasum `23fae724e282fa25745aff82ca4d394748db7d8d`。
- 原始 BSD-2-Clause 许可证保存在 `map/vendor/LICENSE`。库文件未经修改；0.4 的本地 `map/index.html`、`map/map.js`、`map/map.css` 和当时的 `MapCanvas.swift` 增加了起终点、途经点、拖动编辑、锁定、轨迹显示及原生窗口通信。
- 0.4 使用 OpenStreetMap 底图与 WKWebView。0.5 已迁移至原生 MapKit；`map/vendor` 中的历史资源及其许可证保留，不参与当前运行地图。

## pymobiledevice3 11.34.1

- GitHub：https://github.com/doronz88/pymobiledevice3/tree/v11.34.1
- requirements.txt 固定依赖版本，setup.command 将其安装到本地 `.venv`；虚拟环境不提交到仓库。遵循其 GPL-3.0-or-later 许可证；运行库保留发行包许可证和元数据。
- 本地 `backend.py` 调用真实 USB 枚举、lockdown 只读设备信息、按所选设备标识连接 `NativeRemotedTunnel`，再使用 DVT 位置模拟服务。
- 没有添加演示设备或伪造“已连接”状态。未连接时明确显示无设备；自动测试中的替代对象不会用于正式运行。

## 地点搜索与本地资源

地点搜索仍使用 OpenStreetMap Nominatim 的标准 HTTPS Search API。仅提交用户主动输入的查询，每次请求至少间隔 1.1 秒，使用独立应用 User-Agent、HTTP 缓存与会话缓存；搜索结果保留 OpenStreetMap 来源说明。服务地址可以在 `map/search-provider.json` 中修改。查询会发送给所配置的搜索服务，设备标识不会随查询发送，搜索记录不写入本工具的日志或配置。

应用图标由本地 `IconPainter.swift` 使用 AppKit 几何图形绘制，构建时生成 16～1024 像素多分辨率 ICNS，不包含下载的第三方图标素材。

## 本地校验

在此文件夹运行 `.venv/bin/python3 -B -m unittest test_route_geometry test_backend`。这些测试使用模拟对象，不要求连接手机。

地图编辑应通过原生窗口检查，几何与坐标转换测试不能替代手柄交互及手机实际落点核验。0.5.1 的完整真机路线回放仍待验证。
