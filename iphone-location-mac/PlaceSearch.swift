import Foundation

struct Place {
    let name: String
    let latitude: Double
    let longitude: Double
}

final class PlaceSearch {
    private var cache: [String: [Place]] = [:]
    private var lastRequest = -Double.infinity
    private var task: URLSessionDataTask?
    private let endpoint: String

    init(configurationURL: URL) {
        let data = try? Data(contentsOf: configurationURL)
        let settings = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
        endpoint = settings?["endpoint"] ?? "https://nominatim.openstreetmap.org/search"
    }

    static func parse(_ data: Data) throws -> [Place] {
        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NSError(domain: "Search", code: 1, userInfo: [NSLocalizedDescriptionKey: "搜索服务返回格式异常"])
        }
        return items.prefix(6).compactMap { item in
            guard let name = item["display_name"] as? String, !name.isEmpty,
                  let latText = item["lat"] as? String, let lonText = item["lon"] as? String,
                  let lat = Double(latText), let lon = Double(lonText), lat.isFinite, lon.isFinite,
                  abs(lat) <= 85, abs(lon) <= 180 else { return nil }
            return Place(name: name, latitude: lat, longitude: lon)
        }
    }

    func search(_ query: String, completion: @escaping (Result<[Place], Error>) -> Void) {
        if let stored = cache[query] { completion(.success(stored)); return }
        guard task == nil else { completion(.failure(Self.error("正在搜索，请稍候"))); return }
        guard ProcessInfo.processInfo.systemUptime - lastRequest >= 1.1 else {
            completion(.failure(Self.error("搜索间隔至少 1 秒，请稍后重试"))); return
        }
        guard var url = URLComponents(string: endpoint), url.scheme == "https", url.host != nil else {
            completion(.failure(Self.error("搜索服务配置无效，请使用 HTTPS 地址"))); return
        }
        url.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "format", value: "jsonv2"),
                          URLQueryItem(name: "limit", value: "6"), URLQueryItem(name: "accept-language", value: "zh-CN"),
                          URLQueryItem(name: "addressdetails", value: "0")]
        guard let target = url.url else { completion(.failure(Self.error("无法编码搜索地点"))); return }
        var request = URLRequest(url: target, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20)
        request.setValue("LocationHelper/0.4 (macOS personal desktop map)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        lastRequest = ProcessInfo.processInfo.systemUptime
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let result: Result<[Place], Error>
            if let error = error { result = .failure(error) }
            else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                result = .failure(Self.error(http.statusCode == 429 ? "搜索服务繁忙，请稍后重试" : "搜索服务暂不可用（\(http.statusCode)）"))
            } else if let data = data { result = Result { try Self.parse(data) } }
            else { result = .failure(Self.error("搜索服务未返回数据")) }
            DispatchQueue.main.async {
                self?.task = nil
                if case .success(let places) = result {
                    if (self?.cache.count ?? 0) >= 50 { self?.cache.removeAll() }
                    self?.cache[query] = places
                }
                completion(result)
            }
        }
        task?.resume()
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "Search", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
