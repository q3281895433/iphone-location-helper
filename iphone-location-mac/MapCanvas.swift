import AppKit
@preconcurrency import WebKit

final class MapCanvas: WKWebView, WKScriptMessageHandler, WKNavigationDelegate {
    var onMessage: (([String: Any]) -> Void)?
    var ready = false

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        super.init(frame: .zero, configuration: configuration)
        configuration.userContentController.add(self, name: "locationMap")
        navigationDelegate = self
        customUserAgent = "LocationHelper/0.4 (macOS; Leaflet 1.9.4)"
        wantsLayer = true; layer?.cornerRadius = 12; layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func loadMap(_ directory: URL) {
        loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
    }

    func call(_ method: String, _ argument: Any) {
        guard ready, let data = try? JSONSerialization.data(withJSONObject: [argument]),
              let json = String(data: data, encoding: .utf8) else { return }
        evaluateJavaScript("window.locationMap.\(method)((\(json))[0])", completionHandler: nil)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
              let item = message.body as? [String: Any] else { return }
        if item["type"] as? String == "ready" { ready = true }
        onMessage?(item)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.isFileURL || url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        if navigationAction.navigationType == .linkActivated, url.scheme == "https",
           ["www.openstreetmap.org", "leafletjs.com"].contains(url.host ?? "") { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }
}
