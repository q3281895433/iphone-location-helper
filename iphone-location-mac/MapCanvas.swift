import AppKit
import MapKit

fileprivate struct MapHandle {
    let id: String
    let point: NSPoint
    let title: String
    let color: NSColor
}

/// Captures only editing handles; all other gestures reach Apple's map.
private final class MapEditorOverlay: NSView {
    weak var canvas: MapCanvas?
    private var dragging: String?
    private var initialTrack: TrackGeometry?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let canvas = canvas, !canvas.locked else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return canvas.handles().contains { hypot($0.point.x-local.x, $0.point.y-local.y) < 15 } ? self : nil
    }
    override func mouseDown(with event: NSEvent) {
        guard let canvas = canvas, !canvas.locked else { return }
        let point = convert(event.locationInWindow, from: nil)
        dragging = canvas.handles().min { hypot($0.point.x-point.x, $0.point.y-point.y) < hypot($1.point.x-point.x, $1.point.y-point.y) }?.id
        initialTrack = canvas.track
    }
    override func mouseDragged(with event: NSEvent) {
        guard let canvas = canvas, !canvas.locked, let id = dragging else { return }
        canvas.dragHandle(id, to: convert(event.locationInWindow, from: nil), initial: initialTrack)
    }
    override func mouseUp(with event: NSEvent) { mouseDragged(with: event); dragging = nil; initialTrack = nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let canvas = canvas else { return }
        let handles = canvas.handles()
        if let center = handles.first(where: { $0.id == "center" }), let rotate = handles.first(where: { $0.id == "rotate" }) {
            let line = NSBezierPath(); line.move(to: center.point); line.line(to: rotate.point)
            line.setLineDash([4, 4], count: 2, phase: 0); line.lineWidth = 1.5
            NSColor.white.withAlphaComponent(0.85).setStroke(); line.stroke()
        }
        for handle in handles {
            let size: CGFloat = canvas.locked ? 5 : 9
            let dot = NSBezierPath(ovalIn: NSRect(x: handle.point.x-size, y: handle.point.y-size, width: 2*size, height: 2*size))
            handle.color.setFill(); dot.fill(); NSColor.white.setStroke(); dot.lineWidth = 2.5; dot.stroke()
            if !canvas.locked {
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white]
                let text = NSString(string: handle.title), textSize = text.size(withAttributes: attrs)
                var rect = NSRect(x: handle.point.x+13, y: handle.point.y-9, width: textSize.width+12, height: 20)
                if handle.id == "length" || handle.id == "width", let center = handles.first(where: { $0.id == "center" }) {
                    let dx = handle.point.x-center.point.x, dy = handle.point.y-center.point.y, distance = max(1, hypot(dx, dy))
                    rect.origin = NSPoint(x: handle.point.x-dy/distance*30-rect.width/2, y: handle.point.y+dx/distance*30-rect.height/2)
                }
                if rect.maxX > bounds.maxX-4 { rect.origin.x = handle.point.x-rect.width-13 }
                NSColor.black.withAlphaComponent(0.72).setFill(); NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
                text.draw(at: NSPoint(x: rect.minX+6, y: rect.minY+3), withAttributes: attrs)
            }
        }
        if let point = canvas.currentPosition {
            let p = canvas.screen(point), dot = NSBezierPath(ovalIn: NSRect(x: p.x-7, y: p.y-7, width: 14, height: 14))
            NSColor.systemBlue.setFill(); dot.fill(); NSColor.white.setStroke(); dot.lineWidth = 3; dot.stroke()
        }
        if let point = canvas.searchPosition {
            let p = canvas.screen(point), dot = NSBezierPath(ovalIn: NSRect(x: p.x-6, y: p.y-6, width: 12, height: 12))
            NSColor.systemOrange.setFill(); dot.fill(); NSColor.white.setStroke(); dot.lineWidth = 2; dot.stroke()
        }
    }
}

final class MapCanvas: NSView, MKMapViewDelegate, NSGestureRecognizerDelegate {
    var onMessage: (([String: Any]) -> Void)?
    private(set) var ready = false
    fileprivate var locked = false
    fileprivate var track: TrackGeometry?
    fileprivate var currentPosition: CLLocationCoordinate2D?
    fileprivate var searchPosition: CLLocationCoordinate2D?
    private let map = MKMapView()
    private let editor = MapEditorOverlay()
    private let picker = NSSegmentedControl(labels: ["选起点", "选终点", "加途经点", "固定点 / 中心"], trackingMode: .selectOne, target: nil, action: nil)
    private let imagery = NSSegmentedControl(labels: ["卫星", "卫星 + 标注"], trackingMode: .selectOne, target: nil, action: nil)
    private let hint = NSTextField(labelWithString: "Apple 卫星地图 · 选择跑道中心后可拖动把手调整")
    private var editButtons: [NSButton] = []
    private var mode = "polyline"
    private var start: CLLocationCoordinate2D?
    private var end: CLLocationCoordinate2D?
    private var waypoints: [CLLocationCoordinate2D] = []
    private var center: CLLocationCoordinate2D?
    private var routeOverlay: MKPolyline?

    init() {
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 12; layer?.masksToBounds = true; layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
        map.delegate = self; map.isRotateEnabled = false; map.isPitchEnabled = false
        map.showsCompass = true; map.showsScale = true; map.showsZoomControls = true
        map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35, longitude: 105), span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 80)), animated: false)
        let click = NSClickGestureRecognizer(target: self, action: #selector(mapClicked(_:)))
        click.delegate = self; map.addGestureRecognizer(click)
        picker.selectedSegment = 0; picker.target = self; picker.action = #selector(pickChanged)
        imagery.selectedSegment = 0; imagery.target = self; imagery.action = #selector(imageryChanged)
        let fit = NSButton(title: "适应路线", target: self, action: #selector(fitRoute))
        let undo = NSButton(title: "撤销", target: self, action: #selector(undoPoint))
        let clear = NSButton(title: "清空", target: self, action: #selector(clearPoints))
        editButtons = [undo, clear]
        let first = NSStackView(views: [picker, fit, undo, clear]); first.spacing = 6
        let second = NSStackView(views: [imagery, hint]); second.spacing = 10
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail; hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in [first, second, map] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        addSubview(editor); editor.canvas = self; editor.wantsLayer = true
        NSLayoutConstraint.activate([
            first.topAnchor.constraint(equalTo: topAnchor, constant: 6), first.heightAnchor.constraint(equalToConstant: 26), first.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6), first.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            second.topAnchor.constraint(equalTo: first.bottomAnchor, constant: 6), second.heightAnchor.constraint(equalToConstant: 24), second.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6), second.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            map.topAnchor.constraint(equalTo: second.bottomAnchor, constant: 6), map.leadingAnchor.constraint(equalTo: leadingAnchor), map.trailingAnchor.constraint(equalTo: trailingAnchor), map.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); editor.frame = map.frame; editor.needsDisplay = true }
    func loadMap(_ directory: URL) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }; self.ready = true; self.onMessage?(["type": "ready"])
        }
    }
    func call(_ method: String, _ argument: Any) {
        switch method {
        case "update":
            guard let data = argument as? [String: Any] else { return }
            if let value = data["mode"] as? String { mode = value }
            if let value = data["track"] as? [String: Any], let geometry = TrackGeometry(dictionary: value) { track = geometry; center = geometry.coordinate(localEast: 0, localNorth: 0) }
            for index in 0...2 { picker.setEnabled(mode != "stadium", forSegment: index) }
            if mode == "stadium" { picker.selectedSegment = 3 }
            redraw()
        case "lock": locked = argument as? Bool ?? false; picker.isEnabled = !locked; editButtons.forEach { $0.isEnabled = !locked }; redraw()
        case "position": currentPosition = coordinate(argument); editor.needsDisplay = true
        case "clearPosition": currentPosition = nil; editor.needsDisplay = true
        case "center": if let point = coordinate(argument) { focus(point) }
        case "searchResult": if let data = argument as? [String: Any], let point = coordinate(data["point"]) { searchPosition = point; focus(point); editor.needsDisplay = true }
        default: break
        }
    }
    private func coordinate(_ value: Any?) -> CLLocationCoordinate2D? {
        guard let p = value as? [Double], p.count == 2, p.allSatisfy({ $0.isFinite }), abs(p[0]) <= 85, abs(p[1]) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: p[0], longitude: p[1])
    }
    private func focus(_ point: CLLocationCoordinate2D) { map.setRegion(MKCoordinateRegion(center: point, latitudinalMeters: 1100, longitudinalMeters: 1100), animated: false) }
    fileprivate func screen(_ coordinate: CLLocationCoordinate2D) -> NSPoint { map.convert(coordinate, toPointTo: editor) }
    private var routePoints: [CLLocationCoordinate2D] { guard let start = start, let end = end else { return [] }; return [start] + waypoints + [end] }
    @objc private func pickChanged() { hint.stringValue = mode == "stadium" ? "点击场地中心 · 拖动中心 / 长轴 / 短轴 / 旋转把手" : "点击地图选点 · 拖动标记可微调位置" }
    @objc private func imageryChanged() { map.preferredConfiguration = imagery.selectedSegment == 0 ? MKImageryMapConfiguration(elevationStyle: .flat) : MKHybridMapConfiguration(elevationStyle: .flat) }
    @objc private func mapClicked(_ gesture: NSClickGestureRecognizer) {
        guard !locked else { return }
        let point = map.convert(gesture.location(in: map), toCoordinateFrom: map)
        guard CLLocationCoordinate2DIsValid(point), abs(point.latitude) <= 85 else { return }; select(point)
    }
    private func select(_ point: CLLocationCoordinate2D) {
        guard !locked else { return }
        if mode == "stadium" || picker.selectedSegment == 3 {
            center = point
            if var geometry = track { geometry.latitude = point.latitude; geometry.longitude = point.longitude; track = geometry }
            onMessage?(["type": "coordinate", "point": [point.latitude, point.longitude]])
        } else {
            switch picker.selectedSegment { case 1: end = point; case 2: waypoints.append(point); default: start = point }
            onMessage?(["type": "coordinate", "point": [point.latitude, point.longitude]]); emitRoute()
        }
        redraw()
    }
    @objc private func undoPoint() {
        guard !locked, mode != "stadium" else { return }
        if !waypoints.isEmpty { waypoints.removeLast() } else if end != nil { end = nil } else { start = nil }; emitRoute(); redraw()
    }
    @objc private func clearPoints() { guard !locked else { return }; start = nil; end = nil; waypoints = []; emitRoute(); redraw() }
    @objc private func fitRoute() {
        let points = mode == "stadium" ? (track?.points() ?? []) : routePoints
        guard let first = points.first else { if let point = searchPosition ?? center { focus(point) }; return }
        var rect = MKMapRect(origin: MKMapPoint(first), size: MKMapSize(width: 1, height: 1))
        for point in points.dropFirst() { rect = rect.union(MKMapRect(origin: MKMapPoint(point), size: MKMapSize(width: 1, height: 1))) }
        map.setVisibleMapRect(rect, edgePadding: NSEdgeInsets(top: 65, left: 70, bottom: 65, right: 100), animated: false)
    }
    fileprivate func handles() -> [MapHandle] {
        if mode == "stadium", let geometry = track {
            let c = screen(geometry.coordinate(localEast: 0, localNorth: 0)), width = screen(geometry.coordinate(localEast: geometry.radius, localNorth: 0)), length = screen(geometry.coordinate(localEast: 0, localNorth: geometry.straightLength/2+geometry.radius))
            let dx = length.x-c.x, dy = length.y-c.y, distance = max(1, hypot(dx, dy))
            let rotation = NSPoint(x: length.x+dx/distance*42, y: length.y+dy/distance*42)
            return [MapHandle(id: "center", point: c, title: "移动", color: .systemPurple), MapHandle(id: "width", point: width, title: "短轴", color: .systemOrange), MapHandle(id: "length", point: length, title: "长轴", color: .systemOrange), MapHandle(id: "rotate", point: rotation, title: String(format: "旋转 %.0f°", geometry.rotation), color: .systemTeal)]
        }
        var result: [MapHandle] = []
        if let point = start { result.append(MapHandle(id: "start", point: screen(point), title: "起点", color: .systemGreen)) }
        for (index, point) in waypoints.enumerated() { result.append(MapHandle(id: "waypoint:\(index)", point: screen(point), title: "途经 \(index+1)", color: .systemBlue)) }
        if let point = end { result.append(MapHandle(id: "end", point: screen(point), title: "终点", color: .systemRed)) }
        if picker.selectedSegment == 3, let point = center { result.append(MapHandle(id: "center", point: screen(point), title: "固定点", color: .systemPurple)) }; return result
    }
    fileprivate func dragHandle(_ id: String, to point: NSPoint, initial: TrackGeometry?) {
        guard !locked else { return }
        let coordinate = map.convert(point, toCoordinateFrom: editor)
        guard CLLocationCoordinate2DIsValid(coordinate), abs(coordinate.latitude) <= 85 else { return }
        if mode == "stadium", var geometry = initial ?? track {
            switch id {
            case "center": geometry.latitude = coordinate.latitude; geometry.longitude = coordinate.longitude
            case "width": geometry.resizeWidth(at: coordinate)
            case "length": geometry.resizeLength(at: coordinate)
            case "rotate": let local = geometry.localPoint(coordinate: coordinate); guard hypot(local.east, local.north) > 1 else { return }; geometry.rotation = (geometry.rotation + atan2(local.east, local.north)*180 / .pi + 720).truncatingRemainder(dividingBy: 360)
            default: return
            }
            track = geometry; center = geometry.coordinate(localEast: 0, localNorth: 0)
            onMessage?(["type": "track", "track": geometry.dictionary]); redraw(); return
        }
        switch id {
        case "center": center = coordinate
        case "start": start = coordinate
        case "end": end = coordinate
        default: if id.hasPrefix("waypoint:"), let index = Int(id.dropFirst(9)), waypoints.indices.contains(index) { waypoints[index] = coordinate }
        }
        onMessage?(["type": "coordinate", "point": [coordinate.latitude, coordinate.longitude]]); emitRoute(); redraw()
    }
    private func emitRoute() {
        let points = routePoints; var distance = 0.0
        for index in 1..<max(1, points.count) { distance += MKMapPoint(points[index-1]).distance(to: MKMapPoint(points[index])) }
        onMessage?(["type": "route", "points": points.map { [$0.latitude, $0.longitude] }, "distance": distance])
    }
    private func redraw() {
        editButtons.forEach { $0.isEnabled = !locked && mode != "stadium" }
        if let overlay = routeOverlay { map.removeOverlay(overlay) }
        let points = mode == "stadium" ? (track?.points() ?? []) : routePoints
        if points.count > 1 { let line = MKPolyline(coordinates: points, count: points.count); routeOverlay = line; map.addOverlay(line) } else { routeOverlay = nil }
        hint.stringValue = locked ? "位置模拟进行中 · 地图编辑已锁定" : mode == "stadium" ? "拖动紫色中心移动 · 橙色调大小 · 青色调方向" : "Apple 卫星地图 · 点击选点，拖动标记微调"; editor.needsDisplay = true
    }
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer { let renderer = MKPolylineRenderer(overlay: overlay); renderer.strokeColor = mode == "stadium" ? .systemPurple : .systemBlue; renderer.lineWidth = 4; return renderer }
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { editor.needsDisplay = true }
    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) { editor.needsDisplay = true }
    func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) { hint.stringValue = "Apple 地图加载失败，请检查网络后重试" }
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool { true }
    func searchCheck() -> [String: Any] { ["point": searchPosition.map { [$0.latitude, $0.longitude] } ?? [], "provider": "Apple MapKit", "satellite": imagery.selectedSegment == 0] }
    /// Integration checks follow real selection/drag paths without a device backend.
    func runChecks() -> [String: Any] {
        let callback = onMessage; onMessage = nil
        defer { onMessage = callback }
        var results: [String: Bool] = [:]
        let a = CLLocationCoordinate2D(latitude: 39.99, longitude: 116.39), b = CLLocationCoordinate2D(latitude: 39.991, longitude: 116.393)
        mode = "polyline"; locked = false; picker.selectedSegment = 0; select(a); picker.selectedSegment = 1; select(b); results["startEnd"] = routePoints.count == 2
        picker.selectedSegment = 2; select(CLLocationCoordinate2D(latitude: 39.992, longitude: 116.391)); results["waypoint"] = routePoints.count == 3
        undoPoint(); results["undo"] = routePoints.count == 2
        locked = true; select(a); results["locked"] = routePoints.count == 2
        locked = false; clearPoints(); results["clear"] = routePoints.isEmpty
        track = TrackGeometry(dictionary: ["latitude": a.latitude, "longitude": a.longitude, "lapLength": 400.0, "radius": 36.5, "rotation": 0.0, "reverse": false]); mode = "stadium"; redraw(); fitRoute()
        if let initial = track {
            let handle = handles().first { $0.id == "rotate" }!
            results["handleHitTesting"] = editor.hitTest(editor.convert(handle.point, to: self)) === editor
            results["mapGesturesPassThrough"] = editor.hitTest(NSPoint(x: 3, y: 3)) == nil
            dragHandle("rotate", to: screen(initial.coordinate(localEast: 100, localNorth: 0)), initial: initial); results["rotate90"] = abs((track?.rotation ?? -1)-90) < 0.2
            let rotated = track!; dragHandle("width", to: screen(rotated.coordinate(localEast: 45, localNorth: 0)), initial: rotated); results["resizeWidth"] = abs((track?.radius ?? -1)-45) < 0.2
            let wider = track!; dragHandle("length", to: screen(wider.coordinate(localEast: 0, localNorth: 120)), initial: wider); results["resizeLength"] = abs((track!.straightLength/2+track!.radius)-120) < 0.3
            let before = track!; locked = true; dragHandle("rotate", to: screen(a), initial: before); results["lockedDrag"] = track!.rotation == before.rotation; locked = false
            let moved = CLLocationCoordinate2D(latitude: 39.9905, longitude: 116.3905); dragHandle("center", to: screen(moved), initial: track)
            results["moveCenter"] = abs(track!.latitude-moved.latitude)<0.00001 && abs(track!.longitude-moved.longitude)<0.00001
        }
        redraw(); fitRoute()
        let geometryChecks = TrackGeometryCheck.run()
        return ["checks": results, "geometryChecks": geometryChecks, "allPassed": results.count == 12 && results.values.allSatisfy { $0 } && geometryChecks.values.allSatisfy { $0 }, "mapProvider": "Apple MapKit satellite", "track": track?.dictionary ?? [:]]
    }
    func snapshotPNG() -> Data? {
        guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: bitmap); return bitmap.representation(using: .png, properties: [:])
    }
}
