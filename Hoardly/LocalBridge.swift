import Foundation
import Network
import Observation
import os

/// Minimal HTTP/1.1 request, just enough for browser extensions talking to the app.
struct HTTPRequest: Equatable {
    var method: String
    var path: String
    var headers: [String: String] // keys lowercased
    var body: Data

    /// nil until `data` holds a complete request (headers plus `Content-Length` bytes of body).
    init?(_ data: Data) {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count == 3 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard data.distance(from: end.upperBound, to: data.endIndex) >= length else { return nil }
        method = String(start[0])
        path = String(start[1])
        self.headers = headers
        body = data[end.upperBound..<data.index(end.upperBound, offsetBy: length)]
    }
}

/// Loopback-only HTTP endpoint that browser extensions send downloads to.
@Observable
final class LocalBridge {
    static let port: NWEndpoint.Port = 47801 // ponytail: fixed port; add fallback ports if 47801 clashes in the wild
    static let allowedOrigins = ["chrome-extension://", "moz-extension://", "safari-web-extension://"]

    let token: String
    private(set) var status = "Starting…"
    var onAdd: (([IncomingDownload]) -> Void)?

    struct IncomingDownload: Equatable {
        let url: URL
        var headers: [String: String]
        var fileName: String?
        var isStream = false
    }

    static let maxItems = 500
    private var listener: NWListener?

    init() {
        if let saved = UserDefaults.standard.string(forKey: "bridgeToken") {
            token = saved
        } else {
            token = UUID().uuidString
            UserDefaults.standard.set(token, forKey: "bridgeToken")
        }
    }

    func start() {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: Self.port)
        do {
            let listener = try NWListener(using: params)
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    switch state {
                    case .ready: self?.status = "Listening on 127.0.0.1:\(Self.port)"
                    case .failed(let error): self?.status = "Bridge failed: \(error)"
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated {
                    connection.start(queue: .main)
                    self?.receive(connection, Data())
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            status = "Bridge failed: \(error)"
        }
    }

    private func receive(_ connection: NWConnection, _ buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                let buffer = buffer + (data ?? Data())
                if let request = HTTPRequest(buffer) {
                    self?.reply(connection, to: request)
                } else if error != nil || isComplete || buffer.count > 1 << 20 {
                    connection.cancel()
                } else {
                    self?.receive(connection, buffer)
                }
            }
        }
    }

    private func reply(_ connection: NWConnection, to request: HTTPRequest) {
        let (status, json) = handle(request)
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        let head = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))\r\n"
            + "Content-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    func handle(_ request: HTTPRequest) -> (Int, [String: Any]) {
        let origin = request.headers["origin"]
        // Web pages must never reach the bridge; only extensions (Origin) or the Safari app extension (no Origin).
        if let origin, !Self.allowedOrigins.contains(where: origin.hasPrefix) {
            return (403, ["error": "origin not allowed"])
        }
        guard request.method == "POST" else { return (405, ["error": "use POST"]) }
        let authorized = request.headers["x-hoardly-token"] == token
        let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
        let via = request.headers["x-hoardly-via"] ?? "?"
        let browser = body["userAgent"] as? String ?? origin ?? "?"

        switch request.path {
        case "/ping":
            record("ping via \(via), token \(authorized ? "ok" : "missing/wrong") — \(browser)")
            return (200, ["app": "Hoardly", "authorized": authorized, "rules": Self.rules])
        case "/add":
            guard authorized else { return (401, ["error": "pair the extension with the token shown in Hoardly"]) }
            guard let items = Self.downloads(from: body) else {
                return (400, ["error": "items must be 1–\(Self.maxItems) http(s) URLs"])
            }
            record("add via \(via): \(items.map(\.url.absoluteString).joined(separator: " "))")
            onAdd?(items)
            return (200, ["ok": true])
        default:
            return (404, ["error": "unknown path"])
        }
    }

    /// `{"items": [{"url", "cookie"?, "filename"?}], "referrer"?, "userAgent"?}`; nil if any URL isn't http(s).
    static func downloads(from body: [String: Any]) -> [IncomingDownload]? {
        guard let items = body["items"] as? [[String: Any]], (1...maxItems).contains(items.count) else { return nil }
        let shared = headers(from: body)
        var result: [IncomingDownload] = []
        for item in items {
            guard let string = item["url"] as? String, let url = URL(string: string),
                  ["http", "https"].contains(url.scheme?.lowercased()), url.host() != nil else { return nil }
            let name = (item["filename"] as? String).flatMap { $0.isEmpty ? nil : SegmentedDownload.safeName($0) }
            result.append(IncomingDownload(url: url, headers: shared.merging(headers(from: item)) { $1 }, fileName: name,
                                           isStream: item["kind"] as? String == "hls"))
        }
        return result
    }

    /// B4: which browser downloads the extensions hand over. Edited in Settings → Browsers.
    static var rules: [String: Any] {
        let extensions = (UserDefaults.standard.string(forKey: "interceptExtensions") ?? "")
            .lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        return ["extensions": extensions, "minSize": UserDefaults.standard.integer(forKey: "interceptMinSizeMB") * 1_000_000]
    }

    /// Browser context the server may need (login cookies, hotlink checks). CR/LF dropped to block header injection.
    static func headers(from body: [String: Any]) -> [String: String] {
        let fields = ["referrer": "Referer", "userAgent": "User-Agent", "cookie": "Cookie"]
        var headers: [String: String] = [:]
        for (key, field) in fields {
            if let value = body[key] as? String, !value.isEmpty, !value.contains(where: \.isNewline) {
                headers[field] = value
            }
        }
        return headers
    }

    private func record(_ text: String) {
        Logger(subsystem: "id.haonlabs.hoardly", category: "bridge").notice("\(text, privacy: .public)")
    }
}
