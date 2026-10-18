# iPhone Location Helper · 定位助手

macOS 原生窗口工具：通过 USB 连接真实 iPhone，使用开发者定位服务进行固定位置模拟和路线回放。

当前版本 **0.5.1**。界面使用 Swift / AppKit，地图使用原生 Apple MapKit 卫星影像，设备通信使用 pymobiledevice3。

![应用图标](iphone-location-mac/Assets/AppIcon.png)

## 功能

- 枚举真实 USB 设备，显示设备名称与 iOS 版本，按所选设备标识连接。
- 搜索地点，在 Apple 卫星或混合地图上选择和拖动起点、终点及途经点。
- 固定位置模拟，以及按配速回放手绘路线或参数化椭圆跑道。
- 直接拖动跑道的中心、长轴、短轴与旋转手柄，双向同步周长、半径和旋转角。
- 手动选择“大陆底图校正 GCJ02”或“原始 WGS84”，统一地图显示与设备使用的坐标。
- 暂停、继续、进度显示和恢复真实定位。
- 显示按步频估算的模拟步数；该数值不会写入 iPhone 系统计步数据。

路线按照选点顺序连线，暂不提供自动沿道路规划。运行时需要保持 Mac、应用及可信设备连接。

## 环境

- macOS 14 或更新版本。
- Xcode Command Line Tools 或 Xcode，提供 Swift 编译器与 macOS SDK。
- Python 3.11 或更新版本，推荐 Python 3.12。
- 一台已解锁、信任此 Mac 且开启开发者模式的 iPhone。

设备服务兼容性取决于 iOS、macOS 和 pymobiledevice3 的组合。0.5.1 的坐标适配与完整真机路线回放需要分别核对；目前不能认定已消除用户手机上的位置偏移。

## 安装与构建

克隆仓库后，在仓库根目录执行：

```sh
xcode-select --install
./iphone-location-mac/setup.command
./iphone-location-mac/build.command
open './定位助手.app'
```

已经安装开发工具时可跳过第一条。若系统默认 Python 版本较旧，可使用 `PYTHON=python3.12 ./iphone-location-mac/setup.command` 指定解释器。

构建输出为根目录的 `定位助手.app`。请让应用与 `iphone-location-mac` 文件夹保持相邻；应用从该文件夹读取 Python 运行环境、搜索配置和设备后台。仓库不包含虚拟环境或编译后的应用。

## 使用

1. 数据线连接 iPhone，解锁并信任 Mac，刷新并连接所选手机。
2. 先选择底图坐标模式。默认“大陆底图校正 GCJ02”；国外或使用非大陆底图时选择“原始 WGS84”。这是手动选择，不是自动检测地图供应商或国界。
3. 搜索地点并重新选择地图上的场地。升级到 0.5.1 后请重选操场；应用不保存旧路线。先设置固定定位，在 iPhone 自带“地图”中核对实际落点，再开始跑圈。
4. 在地图选择起终点与途经点；跑圈模式可直接拖动四个手柄调整跑道，设置配速后开始。桌面蓝点表示程序发出的坐标，不是从手机读回的位置。
5. 使用完毕后点击“恢复真实定位”，并在手机地图核对。

完整操作、异常恢复与功能限制见 [使用说明](iphone-location-mac/使用说明.md)。程序启动和地点搜索不会自动开始定位模拟。

## 测试

几何与设备状态测试只使用模拟对象，无需连接手机：

```sh
python3 -B -m unittest discover -s iphone-location-mac -p 'test_*.py'
# 完成构建后执行原生地图交互与 Swift 几何检查：
'./定位助手.app/Contents/MacOS/LocationHelper' --map-check /tmp/location-helper-map-check.json
```

macOS 上的地图与搜索检查应通过原生应用的检查模式执行。检查模式不启动设备后台；搜索检查会访问在线地理编码服务。几何模型测试通过也不等于手机已采用发送的位置，真机结果需要在手机地图核对。

## 地图服务与数据

地图使用原生 [Apple MapKit](https://developer.apple.com/documentation/mapkit/mkmapview)，提供[卫星影像](https://developer.apple.com/documentation/mapkit/mkimagerymapconfiguration)与[混合地图](https://developer.apple.com/documentation/mapkit/mkhybridmapconfiguration)。地图影像需要联网，当前视图对应的地图请求由系统地图服务处理。请保留系统显示的来源署名。

地点搜索仍使用 OpenStreetMap Nominatim，只由用户主动提交触发，每次请求至少间隔 1.1 秒，并使用会话缓存；可在 `iphone-location-mac/map/search-provider.json` 更换兼容的 HTTPS 服务。查询会发送给所配置的搜索服务，设备标识不会随查询发送，搜索记录不写入本工具的日志或配置。

手工经纬度、Nominatim 搜索结果、路线配置与设备后台始终使用 WGS84；Apple 的 [`CLLocationCoordinate2D`](https://developer.apple.com/documentation/corelocation/cllocationcoordinate2d) 文档也使用 WGS84 定义。[高德坐标说明](https://developer.amap.com/api/javascript-api-v2/guide/transform/convertfrom)说明其地图使用 GCJ-02。不能将 GCJ-02 或 BD-09 数值直接填入 WGS84 输入框。

0.5.1 增加显式底图坐标选择，默认“大陆底图校正 GCJ02”。该模式下，地图点击和拖动先转换为 WGS84；绘制路线、搜索标记、模拟位置和适应路线时再转换为底图坐标。“原始 WGS84”模式不做此转换。切换选项保留已选 GPS 坐标，只重新投影；不会自动修正此前选错的位置，切换后需重新核对并重选点。

该选择由用户决定，不会检测当前 MapKit 数据源或精确国界。转换所用经纬度包围框仅是粗略适用范围，不能准确排除港澳台及邻国；这些地区或国外用户应选择“原始 WGS84”并核对底图。GCJ-02 转换采用公开近似模型，内部数值往返回归小于 0.1 米只表示模型计算相容，不等于真实地图或手机 GPS 精度。当前修复尚不能替代真机落点核验。

## 许可证

本项目采用 **GPL-3.0-or-later**，见 [LICENSE](LICENSE)。0.4 使用过 Leaflet，保留的历史资源仍附 BSD-2-Clause 许可证；0.5 运行地图使用系统 MapKit。依赖来源、版权说明及本地修改见 [OPEN_SOURCE.md](iphone-location-mac/OPEN_SOURCE.md)。
