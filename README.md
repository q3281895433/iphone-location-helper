# iPhone Location Helper · 定位助手

macOS 原生窗口工具：通过 USB 连接真实 iPhone，使用开发者定位服务进行固定位置模拟和路线回放。

当前版本 **0.5**。界面使用 Swift / AppKit，地图使用原生 Apple MapKit 卫星影像，设备通信使用 pymobiledevice3。

![应用图标](iphone-location-mac/Assets/AppIcon.png)

## 功能

- 枚举真实 USB 设备，显示设备名称与 iOS 版本，按所选设备标识连接。
- 搜索地点，在 Apple 卫星或混合地图上选择和拖动起点、终点及途经点。
- 固定位置模拟，以及按配速回放手绘路线或参数化椭圆跑道。
- 直接拖动跑道的中心、长轴、短轴与旋转手柄，双向同步周长、半径和旋转角。
- 暂停、继续、进度显示和恢复真实定位。
- 显示按步频估算的模拟步数；该数值不会写入 iPhone 系统计步数据。

路线按照选点顺序连线，暂不提供自动沿道路规划。运行时需要保持 Mac、应用及可信设备连接。

## 环境

- macOS 14 或更新版本。
- Xcode Command Line Tools 或 Xcode，提供 Swift 编译器与 macOS SDK。
- Python 3.11 或更新版本，推荐 Python 3.12。
- 一台已解锁、信任此 Mac 且开启开发者模式的 iPhone。

设备服务兼容性取决于 iOS、macOS 和 pymobiledevice3 的组合。0.5 的地图编辑与完整真机路线回放需要分别核对；不保证不同系统和地图服务区域下的实际落点一致。

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
2. 搜索地点，从结果列表选择位置。
3. 设置固定位置，或在地图选择起终点与途经点；跑圈模式可直接拖动四个手柄调整跑道。确认配速后开始路线。
4. 使用完毕后点击“恢复真实定位”，并在手机地图核对。

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

后端与坐标输入使用 WGS84；Apple 的 [`CLLocationCoordinate2D`](https://developer.apple.com/documentation/corelocation/cllocationcoordinate2d) 文档也使用 WGS84 定义。中国区域的地图服务与底图显示可能存在坐标兼容差异；地图中的位置、实际场地及手机真实落点均需核对，不能将 GCJ-02 或 BD-09 坐标直接当作 WGS84 输入。本版本不声称已完成该区域的完整真机验证。

## 许可证

本项目采用 **GPL-3.0-or-later**，见 [LICENSE](LICENSE)。0.4 使用过 Leaflet，保留的历史资源仍附 BSD-2-Clause 许可证；0.5 运行地图使用系统 MapKit。依赖来源、版权说明及本地修改见 [OPEN_SOURCE.md](iphone-location-mac/OPEN_SOURCE.md)。
