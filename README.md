# iPhone Location Helper · 定位助手

macOS 原生窗口工具：通过 USB 连接真实 iPhone，使用开发者定位服务进行固定位置模拟和路线回放。

当前版本 **0.4**。界面使用 Swift / AppKit，地图使用 WKWebView 与 Leaflet，设备通信使用 pymobiledevice3。

![应用图标](iphone-location-mac/Assets/AppIcon.png)

## 功能

- 枚举真实 USB 设备，显示设备名称与 iOS 版本，按所选设备标识连接。
- 搜索地点，在 OpenStreetMap 底图选择和拖动起点、终点及途经点。
- 固定位置模拟，以及按配速回放手绘路线或参数化椭圆跑道。
- 暂停、继续、进度显示和恢复真实定位。
- 显示按步频估算的模拟步数；该数值不会写入 iPhone 系统计步数据。

路线按照选点顺序连线，暂不提供自动沿道路规划。运行时需要保持 Mac、应用及可信设备连接。

## 环境

- macOS 14 或更新版本。
- Xcode Command Line Tools 或 Xcode，提供 Swift 编译器与 macOS SDK。
- Python 3.11 或更新版本，推荐 Python 3.12。
- 一台已解锁、信任此 Mac 且开启开发者模式的 iPhone。

设备服务兼容性取决于 iOS、macOS 和 pymobiledevice3 的组合。当前地图和搜索已经本地检查；完整真机路线回放仍待验证。

## 安装与构建

克隆仓库后，在仓库根目录执行：

```sh
xcode-select --install
./iphone-location-mac/setup.command
./iphone-location-mac/build.command
open './定位助手.app'
```

已经安装开发工具时可跳过第一条。若系统默认 Python 版本较旧，可使用 `PYTHON=python3.12 ./iphone-location-mac/setup.command` 指定解释器。

构建输出为根目录的 `定位助手.app`。请让应用与 `iphone-location-mac` 文件夹保持相邻；应用从该文件夹读取 Python 运行环境、地图资源和设备后台。仓库不包含虚拟环境或编译后的应用。

## 使用

1. 数据线连接 iPhone，解锁并信任 Mac，刷新并连接所选手机。
2. 搜索地点，从结果列表选择位置。
3. 设置固定位置，或在地图选择起终点与途经点，再设置配速并开始路线。
4. 使用完毕后点击“恢复真实定位”，并在手机地图核对。

完整操作、异常恢复与功能限制见 [使用说明](iphone-location-mac/使用说明.md)。程序启动和地点搜索不会自动开始定位模拟。

## 测试

几何与设备状态测试只使用模拟对象，无需连接手机：

```sh
python3 -B -m unittest discover -s iphone-location-mac -p 'test_*.py'
node --check iphone-location-mac/map/map.js
```

macOS 上还可使用应用自身的 `--map-check 报告路径` 检查地图交互，或 `--search-check 报告路径` 检查公共地点搜索。两种检查模式都不会启动设备后台；搜索检查会访问在线地理编码服务。

## 地图服务与数据

地图使用 OpenStreetMap，地点搜索使用 Nominatim。保持界面中的来源署名，遵守相应服务使用政策。搜索只由用户主动提交触发，包含请求限速与会话缓存；可在 `iphone-location-mac/map/search-provider.json` 更换兼容的 HTTPS 服务。查询会发送给所配置的搜索服务，设备标识不会随查询发送。

## 许可证

本项目采用 **GPL-3.0-or-later**，见 [LICENSE](LICENSE)。Leaflet 保留其 BSD-2-Clause 许可证。依赖来源、版权说明及本地修改见 [OPEN_SOURCE.md](iphone-location-mac/OPEN_SOURCE.md)。
