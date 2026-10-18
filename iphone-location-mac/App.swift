import AppKit

func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    return field
}

func column(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = spacing
    return stack
}

func row(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = spacing
    return stack
}

func cardPanel(_ title: String, _ contents: [NSView]) -> NSView {
    let inner = column([label(title, size: 15, weight: .semibold)] + contents, spacing: 8)
    let box = NSView()
    box.wantsLayer = true
    box.layer?.backgroundColor = NSColor.white.cgColor
    box.layer?.cornerRadius = 14
    box.addSubview(inner)
    inner.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        inner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 18),
        inner.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -18),
        inner.topAnchor.constraint(equalTo: box.topAnchor, constant: 18),
        inner.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -18)
    ])
    return box
}

final class TrackView: NSView {
    var lapLength = 400.0
    var radius = 36.5
    var rotation = 0.0
    var reverse = false
    var progress = 0.0
    var isActive = false

    func point(_ fraction: Double) -> NSPoint {
        let safeRadius = max(1, min(radius, lapLength / (2 * .pi) - 0.1))
        let straight = max(1, (lapLength - 2 * .pi * safeRadius) / 2)
        var d = fraction.truncatingRemainder(dividingBy: 1) * lapLength
        if reverse { d = (lapLength - d).truncatingRemainder(dividingBy: lapLength) }
        var x: Double, y: Double
        if d <= straight {
            x = safeRadius; y = -straight / 2 + d
        } else if d <= straight + .pi * safeRadius {
            let a = (d - straight) / safeRadius
            x = safeRadius * cos(a); y = straight / 2 + safeRadius * sin(a)
        } else if d <= 2 * straight + .pi * safeRadius {
            x = -safeRadius; y = straight / 2 - (d - straight - .pi * safeRadius)
        } else {
            let a = .pi + (d - 2 * straight - .pi * safeRadius) / safeRadius
            x = safeRadius * cos(a); y = -straight / 2 + safeRadius * sin(a)
        }
        let angle = rotation * .pi / 180
        let east = x * cos(angle) + y * sin(angle)
        let north = -x * sin(angle) + y * cos(angle)
        let extent = max(safeRadius, straight / 2 + safeRadius)
        let scale = min(bounds.width - 90, bounds.height - 70) / (2 * extent)
        return NSPoint(x: bounds.midX + east * scale, y: bounds.midY + north * scale)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.98, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        NSColor.separatorColor.withAlphaComponent(0.3).setStroke()
        let grid = NSBezierPath()
        for x in stride(from: CGFloat(20), through: bounds.width, by: 28) {
            grid.move(to: NSPoint(x: x, y: 0)); grid.line(to: NSPoint(x: x, y: bounds.height))
        }
        for y in stride(from: CGFloat(20), through: bounds.height, by: 28) {
            grid.move(to: NSPoint(x: 0, y: y)); grid.line(to: NSPoint(x: bounds.width, y: y))
        }
        grid.lineWidth = 0.5; grid.stroke()
        let track = NSBezierPath()
        for i in 0...240 {
            let p = point(Double(i) / 240)
            if i == 0 { track.move(to: p) } else { track.line(to: p) }
        }
        track.close()
        NSColor.systemBlue.withAlphaComponent(0.12).setStroke(); track.lineWidth = 23; track.stroke()
        NSColor.white.setStroke(); track.lineWidth = 1; track.stroke()
        NSColor.systemBlue.withAlphaComponent(0.7).setStroke(); track.lineWidth = 2; track.stroke()
        let start = point(0)
        NSColor.systemTeal.setFill()
        NSBezierPath(ovalIn: NSRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10)).fill()
        let current = point(progress)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: current.x - 9, y: current.y - 9, width: 18, height: 18)).fill()
        (isActive ? NSColor.systemBlue : NSColor.systemGray).setFill()
        NSBezierPath(ovalIn: NSRect(x: current.x - 6, y: current.y - 6, width: 12, height: 12)).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]
        "北 ↑".draw(at: NSPoint(x: 18, y: bounds.height - 28), withAttributes: attrs)
        "几何预览 · 非地图".draw(at: NSPoint(x: 18, y: 14), withAttributes: attrs)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    var window: NSWindow!
    var backend: Process?
    var input: Pipe?
    var outputBuffer = Data()
    let outputQueue = DispatchQueue(label: "location.backend.output")
    var isQuitting = false
    var routeActive = false
    var paused = false
    var assertion: NSObjectProtocol?
    var connectedUDID: String?
    var autoConnect = true
    var routePoints: [[Double]] = []
    let devicePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    let deviceDetails = label("正在检测 USB 设备…", size: 11, color: .secondaryLabelColor)
    let routeMode = NSSegmentedControl(labels: ["地图路线", "椭圆跑圈"], trackingMode: .selectOne, target: nil, action: nil)
    let routeSummary = label("请在地图选择起点与终点。", size: 11, color: .secondaryLabelColor)
    let mapCanvas = MapCanvas()
    let placeSearchField = NSSearchField(string: "")
    let placeResults = NSPopUpButton(frame: .zero, pullsDown: false)
    var searchButton: NSButton!
    var foundPlaces: [Place] = []
    var searching = false
    lazy var placeSearch = PlaceSearch(configurationURL: supportURL.appendingPathComponent("map/search-provider.json"))

    let latitude = NSTextField(string: "")
    let longitude = NSTextField(string: "")
    let lapLength = NSTextField(string: "400")
    let radius = NSTextField(string: "36.5")
    let laps = NSTextField(string: "5")
    let pace = NSTextField(string: "6:00")
    let rotation = NSTextField(string: "0")
    let cadence = NSTextField(string: "160")
    let direction = NSSegmentedControl(labels: ["正向", "反向"], trackingMode: .selectOne, target: nil, action: nil)
    let status = label("未连接设备", size: 14, weight: .medium, color: .secondaryLabelColor)
    let deviceHint = label("连接 iPhone，解锁并信任此 Mac。", size: 12, color: .secondaryLabelColor)
    let distanceMetric = label("0 m", size: 23, weight: .semibold)
    let timeMetric = label("00:00", size: 23, weight: .semibold)
    let lapMetric = label("0%", size: 23, weight: .semibold)
    let stepMetric = label("0", size: 23, weight: .semibold)
    let track = TrackView()
    let progressBar = NSProgressIndicator()
    let log = NSTextView()
    var pauseButton: NSButton!
    var startButton: NSButton!

    var supportURL: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("iphone-location-mac")
    }

    func button(_ title: String, _ action: Selector, prominent: Bool = false) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        if prominent { b.bezelColor = .systemBlue; b.contentTintColor = .white }
        return b
    }

    func fields(_ items: [(String, NSTextField)]) -> NSGridView {
        let grid = NSGridView(views: items.map { [label($0.0, color: .secondaryLabelColor), $0.1] })
        grid.rowSpacing = 9; grid.columnSpacing = 14
        grid.heightAnchor.constraint(equalToConstant: CGFloat(items.count * 22 + max(0, items.count - 1) * 9)).isActive = true
        grid.yPlacement = .center
        for index in items.indices { grid.row(at: index).height = 22 }
        grid.column(at: 0).width = 86
        for (_, field) in items {
            field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            field.delegate = self
            field.widthAnchor.constraint(equalToConstant: 188).isActive = true
        }
        return grid
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .aqua)
        buildMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "定位助手"
        window.minSize = NSSize(width: 1140, height: 800)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor.windowBackgroundColor
        if let icon = NSImage(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")) { NSApp.applicationIconImage = icon }

        let title = column([label("定位助手", size: 27, weight: .bold), label("真实设备 · 地图选点 · 路线回放", size: 13, color: .secondaryLabelColor)], spacing: 4)
        let header = row([title, NSView(), status])

        devicePicker.addItem(withTitle: "尚未检测到设备")
        devicePicker.widthAnchor.constraint(equalToConstant: 215).isActive = true
        devicePicker.target = self; devicePicker.action = #selector(deviceSelectionChanged)
        deviceDetails.maximumNumberOfLines = 2; deviceDetails.preferredMaxLayoutWidth = 325
        let devices = cardPanel("真实连接设备", [row([devicePicker, button("刷新", #selector(refreshDevices))]),
            row([button("连接所选手机", #selector(connect)), deviceDetails])])

        let coordinates = fields([("纬度", latitude), ("经度", longitude)])
        latitude.placeholderString = "搜索地点或在地图选点"
        longitude.placeholderString = "WGS84 经度"
        let reference = label("手机接收 WGS84。大陆底图请启用 GCJ-02 校正；先核对固定点，再启动跑圈。", size: 11, color: .secondaryLabelColor)
        reference.maximumNumberOfLines = 2
        reference.preferredMaxLayoutWidth = 320
        let fixed = cardPanel("目标位置 · WGS84", [coordinates, reference,
            row([button("设置固定定位", #selector(setFixed), prominent: true), button("恢复真实定位", #selector(restore))])])

        direction.selectedSegment = 0
        direction.target = self; direction.action = #selector(updatePreviewAction)
        let routeItems: [[NSView]] = [
            [label("周长 m", size: 12), lapLength, label("半径 m", size: 12), radius],
            [label("圈数", size: 12), laps, label("配速", size: 12), pace],
            [label("旋转 °", size: 12), rotation, label("步频", size: 12), cadence]
        ]
        let routeFields = NSGridView(views: routeItems)
        routeFields.rowSpacing = 10; routeFields.columnSpacing = 9
        routeFields.heightAnchor.constraint(equalToConstant: 86).isActive = true
        routeFields.yPlacement = .center
        for index in 0..<3 { routeFields.row(at: index).height = 22 }
        for field in [lapLength, radius, laps, pace, rotation, cadence] {
            field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            field.delegate = self; field.widthAnchor.constraint(equalToConstant: 76).isActive = true
        }
        routeMode.selectedSegment = 0; routeMode.target = self; routeMode.action = #selector(updatePreviewAction)
        routeSummary.maximumNumberOfLines = 2; routeSummary.preferredMaxLayoutWidth = 325
        startButton = button("开始路线", #selector(startRoute), prominent: true)
        pauseButton = button("暂停", #selector(togglePause)); pauseButton.isEnabled = false
        let route = cardPanel("路线与配速", [routeMode, routeSummary, routeFields, label("配速：分:秒 / km · 步频：模拟步 / 分", size: 11, color: .secondaryLabelColor), row([direction, startButton, pauseButton])])
        let left = column([devices, fixed, route], spacing: 14)
        left.widthAnchor.constraint(equalToConstant: 368).isActive = true
        fixed.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true
        devices.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true
        route.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true
        devices.heightAnchor.constraint(equalToConstant: 124).isActive = true
        fixed.heightAnchor.constraint(equalToConstant: 196).isActive = true
        route.heightAnchor.constraint(equalToConstant: 274).isActive = true

        placeSearchField.placeholderString = "搜索城市、地址或地点，例如：北京 奥林匹克公园"
        placeSearchField.target = self; placeSearchField.action = #selector(searchPlace)
        placeSearchField.sendsSearchStringImmediately = false
        placeSearchField.sendsWholeSearchString = true
        searchButton = button("搜索", #selector(searchPlace), prominent: true)
        searchButton.widthAnchor.constraint(equalToConstant: 64).isActive = true
        let searchRow = row([placeSearchField, searchButton])
        placeSearchField.widthAnchor.constraint(equalTo: searchRow.widthAnchor, constant: -74).isActive = true
        placeResults.addItem(withTitle: "输入地点后回车搜索 · OpenStreetMap")
        placeResults.target = self; placeResults.action = #selector(selectPlace)
        placeResults.isEnabled = false
        mapCanvas.heightAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        progressBar.isIndeterminate = false; progressBar.minValue = 0; progressBar.maxValue = 1
        progressBar.style = .bar
        let metrics = row([
            column([label("累计距离", size: 11, color: .secondaryLabelColor), distanceMetric], spacing: 4),
            column([label("运动时间", size: 11, color: .secondaryLabelColor), timeMetric], spacing: 4),
            column([label("路线进度", size: 11, color: .secondaryLabelColor), lapMetric], spacing: 4),
            column([label("模拟步数", size: 11, color: .secondaryLabelColor), stepMetric], spacing: 4)
        ], spacing: 24)
        log.isEditable = false; log.isSelectable = true
        log.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        log.textContainerInset = NSSize(width: 8, height: 8)
        log.backgroundColor = .textBackgroundColor
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.documentView = log
        scroll.heightAnchor.constraint(equalToConstant: 76).isActive = true
        let explanation = label("先设置固定点，在 iPhone 自带地图核对操场，再开始跑圈。桌面蓝点为已发送位置，不能验证手机实际落点。", size: 12, color: .secondaryLabelColor)
        explanation.maximumNumberOfLines = 3; explanation.preferredMaxLayoutWidth = 570
        let right = column([label("地点搜索与路线选点", size: 15, weight: .semibold), searchRow, placeResults, mapCanvas, progressBar, metrics, explanation, label("运行记录", size: 13, weight: .medium), scroll])
        for v in [searchRow, placeResults, mapCanvas, progressBar, scroll] { v.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true }
        let body = NSStackView(views: [left, right])
        body.orientation = .horizontal; body.alignment = .top; body.spacing = 22
        let footer = row([deviceHint, NSView(), label("USB 连接 · Mac 保持唤醒", size: 11, color: .secondaryLabelColor)])
        let root = column([header, body, footer], spacing: 18)
        let content = window.contentView!
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
        content.addSubview(root)
        root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            header.widthAnchor.constraint(equalTo: root.widthAnchor), body.widthAnchor.constraint(equalTo: root.widthAnchor),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor),
            right.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -390)
        ])
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        mapCanvas.onMessage = { [weak self] item in self?.handleMap(item) }
        mapCanvas.loadMap(supportURL.appendingPathComponent("map"))
        updatePreview()
        if CommandLine.arguments.contains("--map-check") { return }
        if CommandLine.arguments.contains("--search-check") { return }
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > index + 1 {
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                content.layoutSubtreeIfNeeded()
                if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                    content.cacheDisplay(in: content.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
                }
                self.isQuitting = true; NSApp.terminate(nil)
            }
            return
        }
        launchBackend()
    }

    func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出定位助手", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        editItem.submenu = edit; menu.addItem(editItem); NSApp.mainMenu = menu
    }

    func launchBackend() {
        let python = supportURL.appendingPathComponent(".venv/bin/python3")
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            status.stringValue = "缺少运行环境"; appendLog("请保留应用旁的 iphone-location-mac 支持文件夹。")
            return
        }
        let process = Process(); let stdinPipe = Pipe(); let stdoutPipe = Pipe(); let stderrPipe = Pipe()
        process.executableURL = python
        process.arguments = ["-u", supportURL.appendingPathComponent("backend.py").path]
        process.currentDirectoryURL = supportURL
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONDONTWRITEBYTECODE"] = "1"; environment["NO_COLOR"] = "1"
        process.environment = environment
        process.standardInput = stdinPipe; process.standardOutput = stdoutPipe; process.standardError = stderrPipe
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            self?.outputQueue.async { [weak self] in
                guard let self = self else { return }
                self.outputBuffer.append(data)
                while let end = self.outputBuffer.firstIndex(of: 10) {
                    let line = self.outputBuffer.prefix(upTo: end)
                    self.outputBuffer.removeSubrange(...end)
                    if let item = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                        DispatchQueue.main.async { self.handle(item) }
                    }
                }
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            if let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DispatchQueue.main.async { self?.appendLog(String(text.suffix(700))) }
            }
        }
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.endAwake()
                if self.isQuitting { NSApp.terminate(nil) }
                else { self.status.stringValue = "连接进程已停止"; self.appendLog("后台进程结束（\(process.terminationStatus)），如曾设置定位，请重开应用并恢复真实定位。") }
            }
        }
        do { try process.run(); backend = process; input = stdinPipe }
        catch { appendLog("无法启动后台：\(error.localizedDescription)") }
    }

    func send(_ item: [String: Any]) {
        guard let backend = backend, backend.isRunning, let input = input else { appendLog("后台未运行，请重新打开应用。"); return }
        do {
            var data = try JSONSerialization.data(withJSONObject: item)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        } catch { appendLog("发送失败：\(error.localizedDescription)") }
    }

    func handle(_ item: [String: Any]) {
        let event = item["event"] as? String ?? ""
        switch event {
        case "ready": appendLog("已就绪，正在读取真实 USB 设备。启动应用不会修改手机位置。"); refreshDevices()
        case "devices":
            let previous = devicePicker.selectedItem?.representedObject as? String
            devicePicker.removeAllItems()
            let devices = item["devices"] as? [[String: Any]] ?? []
            for device in devices {
                let name = device["name"] as? String ?? "iPhone / iPad"
                let version = device["ios"] as? String ?? "未信任"
                let udid = device["udid"] as? String ?? ""
                devicePicker.addItem(withTitle: "\(name) · iOS \(version) · \(udid.suffix(4))")
                devicePicker.lastItem?.representedObject = udid
                if udid == previous { devicePicker.select(devicePicker.lastItem) }
            }
            if devices.isEmpty {
                connectedUDID = nil
                devicePicker.addItem(withTitle: "未发现 USB 设备")
                deviceDetails.stringValue = "连接、解锁并信任手机"
                status.stringValue = "未检测到真实设备"; status.textColor = .secondaryLabelColor
            } else {
                deviceDetails.stringValue = "检测到 \(devices.count) 台 USB 设备"
                appendLog("已检测到 \(devices.count) 台真实 USB 设备。")
                if autoConnect && devices.count == 1 { autoConnect = false; connect() }
            }
        case "connected":
            let device = item["device"] as? [String: Any] ?? [:]
            connectedUDID = device["udid"] as? String
            let name = device["name"] as? String ?? "设备"
            let version = device["ios"] as? String ?? ""
            status.stringValue = "已连接：\(name)"; status.textColor = .systemGreen
            deviceDetails.stringValue = "iOS \(version) · USB"
            deviceHint.stringValue = "\(name) · \(device["product"] as? String ?? "") · 原生定位服务已连接"
            appendLog("真实设备 \(name) 的定位服务已连接。")
        case "fixed":
            setRouteControls(true)
            routeActive = false; pauseButton.isEnabled = false; startButton.isEnabled = true
            status.stringValue = "固定定位保持中"; track.isActive = false; beginAwake(); appendLog("固定定位命令已执行，请在手机地图核对。")
            if let lat = item["latitude"] as? Double, let lon = item["longitude"] as? Double { mapCanvas.call("position", [lat, lon]) }
        case "route_started":
            setRouteControls(false)
            routeActive = true; paused = false; pauseButton.title = "暂停"; pauseButton.isEnabled = true; startButton.isEnabled = false
            status.stringValue = "路线回放中"; track.isActive = true; beginAwake(); appendLog("开始路线，按设定配速每秒更新位置。")
        case "progress":
            let distance = item["distance"] as? Double ?? 0
            let elapsed = Int(item["elapsed"] as? Double ?? 0)
            distanceMetric.stringValue = String(format: "%.0f m", distance)
            timeMetric.stringValue = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
            lapMetric.stringValue = routeMode.selectedSegment == 0 ? String(format: "%.0f%%", (item["fraction"] as? Double ?? 0) * 100) : String(format: "%.2f 圈", item["lapProgress"] as? Double ?? 0)
            stepMetric.stringValue = "\(item["simulatedSteps"] as? Int ?? 0)"
            track.progress = item["lapProgress"] as? Double ?? 0; track.needsDisplay = true
            progressBar.doubleValue = item["fraction"] as? Double ?? 0
            if let lat = item["latitude"] as? Double, let lon = item["longitude"] as? Double { mapCanvas.call("position", [lat, lon]) }
        case "paused": paused = true; pauseButton.title = "继续"; status.stringValue = "路线已暂停"; appendLog("暂停：保持当前位置，距离与模拟步数停止累计。")
        case "resumed": paused = false; pauseButton.title = "暂停"; status.stringValue = "路线回放中"; appendLog("继续路线。")
        case "route_finished":
            setRouteControls(true)
            routeActive = false; pauseButton.isEnabled = false; startButton.isEnabled = true
            status.stringValue = "已完成，停留在终点"; appendLog("路线完成。点击“恢复真实定位”结束模拟。")
        case "route_stopped":
            routeActive = false; paused = false; setRouteControls(true)
            pauseButton.isEnabled = false; startButton.isEnabled = true
            status.stringValue = "路线已停止，请核对定位"; status.textColor = .systemOrange
        case "restored":
            setRouteControls(true)
            routeActive = false; pauseButton.isEnabled = false; startButton.isEnabled = true
            status.stringValue = "已发送恢复真实定位命令"; status.textColor = .systemGreen
            track.isActive = false; track.needsDisplay = true; endAwake(); appendLog("模拟定位已清除，请在手机地图核对真实位置。")
            mapCanvas.call("position", NSNull())
        case "error":
            status.stringValue = "操作未完成"; status.textColor = .systemOrange
            appendLog(item["message"] as? String ?? "未知错误")
        case "closed": if isQuitting { NSApp.terminate(nil) }
        default: break
        }
    }

    func appendLog(_ text: String) {
        let line = "\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))  \(text)\n"
        log.string = String((log.string + line).suffix(9000))
        log.scrollToEndOfDocument(nil)
    }

    func parseNumber(_ field: NSTextField, _ name: String) throws -> Double {
        guard let value = Double(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else {
            throw NSError(domain: "Location", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(name)请输入有效数值"])
        }
        return value
    }

    func config() throws -> [String: Any] {
        let parts = pace.stringValue.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Int(parts[1]), minutes >= 0, seconds >= 0, seconds < 60 else {
            throw NSError(domain: "Location", code: 1, userInfo: [NSLocalizedDescriptionKey: "配速格式应为分:秒，例如 6:00"])
        }
        if routeMode.selectedSegment == 0 {
            guard routePoints.count >= 2 else { throw NSError(domain: "Location", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先在地图选择起点和终点，必要时添加途经点。"] ) }
            return ["mode": "polyline", "points": routePoints, "pace": minutes * 60 + seconds,
                    "cadence": try parseNumber(cadence, "模拟步频")]
        }
        return ["latitude": try parseNumber(latitude, "纬度"), "longitude": try parseNumber(longitude, "经度"),
                "lapLength": try parseNumber(lapLength, "每圈长度"), "radius": try parseNumber(radius, "半径"),
                "laps": try parseNumber(laps, "圈数"), "pace": minutes * 60 + seconds,
                "rotation": try parseNumber(rotation, "旋转角度"), "cadence": try parseNumber(cadence, "模拟步频"),
                "reverse": direction.selectedSegment == 1]
    }

    func beginAwake() {
        if assertion == nil { assertion = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "保持 iPhone 定位会话") }
    }
    func setRouteControls(_ enabled: Bool) {
        for field in [latitude, longitude, pace, cadence] { field.isEnabled = enabled }
        for field in [lapLength, radius, laps, rotation] { field.isEnabled = enabled && routeMode.selectedSegment == 1 }
        direction.isEnabled = enabled && routeMode.selectedSegment == 1
        routeMode.isEnabled = enabled; devicePicker.isEnabled = enabled
        placeSearchField.isEnabled = enabled && !searching
        searchButton?.isEnabled = enabled && !searching
        placeResults.isEnabled = enabled && !searching && !foundPlaces.isEmpty
        mapCanvas.call("lock", !enabled)
    }
    func endAwake() { if let token = assertion { ProcessInfo.processInfo.endActivity(token); assertion = nil } }

    @objc func refreshDevices() { send(["action": "devices"]) }
    @objc func deviceSelectionChanged() { deviceDetails.stringValue = "请点击“连接所选手机”" }
    @objc func connect() {
        guard let udid = devicePicker.selectedItem?.representedObject as? String else { appendLog("未发现真实 USB 手机，请连接后刷新。"); return }
        status.stringValue = "正在连接真实设备…"; send(["action": "connect", "udid": udid])
    }
    func requireDevice() -> Bool {
        guard let selected = devicePicker.selectedItem?.representedObject as? String, selected == connectedUDID else {
            appendLog("请先连接列表中选定的真实手机。"); return false
        }
        return true
    }
    @objc func searchPlace() {
        guard !routeActive, !searching else { return }
        let query = placeSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, query.count <= 200 else { appendLog("请输入 2～200 个字符的地点名称，建议加上城市。"); return }
        searching = true; setRouteControls(true)
        placeResults.removeAllItems(); placeResults.addItem(withTitle: "正在搜索地点…")
        placeSearch.search(query) { [weak self] result in
            guard let self = self else { return }
            self.searching = false; self.placeResults.removeAllItems(); self.foundPlaces = []
            switch result {
            case .success(let places):
                self.foundPlaces = places
                self.placeResults.addItem(withTitle: places.isEmpty ? "未找到地点，请补充城市或换一个名称" : "找到 \(places.count) 个地点，请选择结果")
                for place in places {
                    self.placeResults.addItem(withTitle: String(place.name.prefix(90)))
                    self.placeResults.lastItem?.toolTip = place.name
                }
            case .failure(let error):
                self.placeResults.addItem(withTitle: "搜索失败，请检查网络后重试")
                self.appendLog("地点搜索失败：\(error.localizedDescription)")
            }
            self.setRouteControls(!self.routeActive)
        }
    }

    @objc func selectPlace() {
        let index = placeResults.indexOfSelectedItem - 1
        guard !routeActive, foundPlaces.indices.contains(index) else { return }
        let place = foundPlaces[index]
        latitude.stringValue = String(format: "%.7f", place.latitude)
        longitude.stringValue = String(format: "%.7f", place.longitude)
        mapCanvas.call("searchResult", ["point": [place.latitude, place.longitude], "name": place.name])
        updatePreview()
        appendLog("已定位到搜索结果。请在地图选择起点、终点或固定点。")
    }
    @objc func setFixed() {
        guard requireDevice() else { return }
        do { send(["action": "set", "latitude": try parseNumber(latitude, "纬度"), "longitude": try parseNumber(longitude, "经度")]); status.stringValue = "正在设置…" }
        catch { appendLog(error.localizedDescription) }
    }
    @objc func restore() { status.stringValue = "正在恢复…"; send(["action": "restore"]) }
    @objc func startRoute() {
        guard requireDevice() else { return }
        do { let c = try config(); updatePreview(); send(["action": "start", "config": c]); status.stringValue = "正在启动路线…" }
        catch { appendLog(error.localizedDescription) }
    }
    @objc func togglePause() { send(["action": paused ? "resume" : "pause"]) }
    @objc func updatePreviewAction() { updatePreview() }
    func controlTextDidChange(_ obj: Notification) { if !routeActive { updatePreview() } }
    func updatePreview() {
        if !routeActive { setRouteControls(true) }
        startButton.title = routeMode.selectedSegment == 0 ? "开始路线" : "开始跑圈"
        if routeMode.selectedSegment == 1 { routeSummary.stringValue = "拖动地图把手，调整跑道大小、方向与中心。" }
        else if routePoints.count < 2 { routeSummary.stringValue = "请在地图选择起点与终点。" }
        if progressBar.doubleValue == 0 { lapMetric.stringValue = routeMode.selectedSegment == 0 ? "0%" : "0.00 圈" }
        mapCanvas.call("update", ["mode": routeMode.selectedSegment == 0 ? "polyline" : "stadium"])
        guard let length = Double(lapLength.stringValue), let r = Double(radius.stringValue), let turn = Double(rotation.stringValue), length.isFinite, r.isFinite, turn.isFinite, length >= 50, r > 0, 2 * .pi * r < length else { return }
        track.lapLength = length; track.radius = r; track.rotation = turn; track.reverse = direction.selectedSegment == 1; track.needsDisplay = true
        if let lat = Double(latitude.stringValue), let lon = Double(longitude.stringValue), lat.isFinite, lon.isFinite, abs(lat) <= 85, abs(lon) <= 180 {
            mapCanvas.call("update", ["mode": routeMode.selectedSegment == 0 ? "polyline" : "stadium", "track": ["latitude": lat, "longitude": lon, "lapLength": length, "radius": r, "rotation": turn, "reverse": direction.selectedSegment == 1]])
        }
    }

    func handleMap(_ item: [String: Any]) {
        switch item["type"] as? String {
        case "ready":
            updatePreview()
            if let index = CommandLine.arguments.firstIndex(of: "--search-check"), CommandLine.arguments.count > index + 1 {
                let report = CommandLine.arguments[index + 1]
                let invalid = Data("[{\"lat\":\"NaN\",\"lon\":\"0\",\"display_name\":\"invalid\"}]".utf8)
                self.placeSearch.search("Beijing Olympic Park") { result in
                    var summary: [String: Any] = ["invalidCoordinatesRejected": (try? PlaceSearch.parse(invalid).isEmpty) ?? false]
                    switch result {
                    case .success(let places):
                        summary["resultCount"] = places.count
                        if let place = places.first {
                            summary["name"] = place.name
                            self.foundPlaces = places
                            self.placeResults.removeAllItems(); self.placeResults.addItem(withTitle: "选择结果")
                            for p in places { self.placeResults.addItem(withTitle: p.name) }
                            self.placeResults.selectItem(at: 1); self.selectPlace()
                            summary["map"] = self.mapCanvas.searchCheck()
                            if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted]) { try? data.write(to: URL(fileURLWithPath: report)) }
                            self.isQuitting = true; NSApp.terminate(nil)
                            return
                        }
                    case .failure(let error): summary["error"] = error.localizedDescription
                    }
                    if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted]) { try? data.write(to: URL(fileURLWithPath: report)) }
                    self.isQuitting = true; NSApp.terminate(nil)
                }
            }
            if let index = CommandLine.arguments.firstIndex(of: "--map-check"), CommandLine.arguments.count > index + 1 {
                let report = CommandLine.arguments[index + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    var data = self.mapCanvas.runChecks()
                    self.routeMode.selectedSegment = 1
                    if let geometry = data["track"] as? [String: Any] { self.handleMap(["type": "track", "track": geometry]) }
                    if let geometry = data["track"] as? [String: Any], let expected = TrackGeometry(dictionary: geometry) {
                        data["formSync"] = abs((Double(self.radius.stringValue) ?? -1)-expected.radius) < 0.01 && abs((Double(self.rotation.stringValue) ?? -1)-expected.rotation) < 0.01 && abs((Double(self.lapLength.stringValue) ?? -1)-expected.lapLength) < 0.01
                        data["allPassed"] = (data["allPassed"] as? Bool ?? false) && (data["formSync"] as? Bool ?? false)
                        let deviceConfig = try? self.config()
                        data["deviceConfigWGS84"] = abs((deviceConfig?["latitude"] as? Double ?? -1)-39.9905)<1e-7 && abs((deviceConfig?["longitude"] as? Double ?? -1)-116.3905)<1e-7
                        data["allPassed"] = (data["allPassed"] as? Bool ?? false) && (data["deviceConfigWGS84"] as? Bool ?? false)
                    }
                    if let json = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) { try? json.write(to: URL(fileURLWithPath: report)) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if let png = self.mapCanvas.snapshotPNG() { try? png.write(to: URL(fileURLWithPath: report + ".png")) }
                        if let content = self.window.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: bitmap)
                            if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: report + ".window.png")) }
                        }
                        self.isQuitting = true; NSApp.terminate(nil)
                    }
                }
            }
        case "route":
            guard !routeActive else { return }
            routePoints = item["points"] as? [[Double]] ?? []
            let distance = item["distance"] as? Double ?? 0
            routeSummary.stringValue = routePoints.count >= 2 ? String(format: "地图路线 %.0f 米 · %d 个途经点", distance, max(0, routePoints.count - 2)) : "请在地图选择起点与终点。"
        case "coordinate":
            guard !routeActive, let point = item["point"] as? [Double], point.count == 2 else { return }
            latitude.stringValue = String(format: "%.7f", point[0]); longitude.stringValue = String(format: "%.7f", point[1]); updatePreview()
        case "track":
            guard !routeActive, let values = item["track"] as? [String: Any], let geometry = TrackGeometry(dictionary: values) else { return }
            latitude.stringValue = String(format: "%.7f", geometry.latitude)
            longitude.stringValue = String(format: "%.7f", geometry.longitude)
            lapLength.stringValue = String(format: "%.6f", geometry.lapLength)
            radius.stringValue = String(format: "%.6f", geometry.radius)
            rotation.stringValue = String(format: "%.2f", geometry.rotation)
            updatePreview()
        case "mapCoordinateMode":
            appendLog("地图坐标模式已切换，已选 GPS 坐标保持不变。请重新核对地图选点，并先用固定定位在手机自带地图确认。")
        default: break
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isQuitting { return .terminateNow }
        guard let backend = backend, backend.isRunning else { return .terminateNow }
        isQuitting = true; status.stringValue = "正在恢复定位并退出…"; send(["action": "quit"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self = self, self.backend?.isRunning == true else { return }
            let alert = NSAlert(); alert.messageText = "恢复定位尚未完成"
            alert.informativeText = "可继续等待，或强制退出后重新连接手机恢复定位。"
            alert.addButton(withTitle: "继续等待"); alert.addButton(withTitle: "强制退出")
            if alert.runModal() == .alertSecondButtonReturn { self.backend?.terminate(); NSApp.terminate(nil) }
        }
        return .terminateCancel
    }
}

@main
struct LocationHelperMain {
    static func main() {
        let app = NSApplication.shared
        if let index = CommandLine.arguments.firstIndex(of: "--make-icon"), CommandLine.arguments.count > index + 1 {
            do { try IconPainter.writeIconSet(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { fputs("Icon generation failed: \(error)\n", stderr); exit(1) }
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
