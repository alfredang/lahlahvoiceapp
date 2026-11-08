import Foundation

/// LahLah Voice's local control API: HTTP on 127.0.0.1, every call needs the API key.
/// The routing and HTTP parsing live here so they can be tested without the app.
///
/// GET  /v1/health                 is the app up
/// GET  /v1/status                 phase, mode, last transcript
/// POST /v1/dictation/start        start hands-free dictation
/// POST /v1/dictation/stop         stop and insert (or send) the text
/// GET  /v1/transcripts/last       the last dictation
/// PUT  /v1/mode                   {"mode": "normal" | "lahlah-video-command"}
/// POST /v1/lahlah-video/send      {"text": "split here"}: forward a command to LahLah Video
public enum VoiceMode: String, Codable, Sendable, CaseIterable {
    case normal
    case lahlahVideoCommand = "lahlah-video-command"
}

public struct HTTPRequest: Sendable, Equatable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        self.body = body
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }

    public static func json<T: Encodable>(_ status: Int, _ value: T) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return HTTPResponse(status: status, body: (try? encoder.encode(value)) ?? Data("{}".utf8))
    }

    public static func error(_ status: Int, _ message: String) -> HTTPResponse {
        json(status, ["error": message])
    }

    /// The bytes to write back on the socket.
    public func serialized() -> Data {
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 500: "Internal Server Error", 502: "Bad Gateway"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json; charset=utf-8\r\n"
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

public enum HTTPParser {
    /// One complete request from the start of `data`, or nil while bytes are still arriving.
    public static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.count - bodyStart >= length else { return nil }
        let path = String(start[1]).components(separatedBy: "?").first ?? "/"
        return HTTPRequest(
            method: String(start[0]).uppercased(), path: path, headers: headers,
            body: data.subdata(in: bodyStart..<(bodyStart + length)))
    }
}

/// What the app does for each route. The app's DictationController implements it.
@MainActor
public protocol VoiceAPIHandler: AnyObject {
    func apiStatus() -> VoiceAPIStatus
    func apiStartDictation() -> String
    func apiStopDictation() -> String
    func apiLastTranscript() -> DictationRecord?
    func apiSetMode(_ mode: VoiceMode)
    func apiSendToLahLahVideo(_ text: String) async -> LahLahVideoDelivery
}

public struct VoiceAPIStatus: Codable, Sendable, Equatable {
    public var app = "LahLah Voice"
    public var version: String
    public var phase: String
    public var mode: VoiceMode
    public var lastTranscript: String?
    public var lahlahVideoAvailable: Bool

    public init(version: String, phase: String, mode: VoiceMode, lastTranscript: String?, lahlahVideoAvailable: Bool) {
        self.version = version
        self.phase = phase
        self.mode = mode
        self.lastTranscript = lastTranscript
        self.lahlahVideoAvailable = lahlahVideoAvailable
    }
}

public enum VoiceAPI {
    public static let routes = [
        "GET /v1/health", "GET /v1/status", "POST /v1/dictation/start", "POST /v1/dictation/stop",
        "GET /v1/transcripts/last", "PUT /v1/mode", "POST /v1/lahlah-video/send",
    ]

    /// 48 random hex characters with a recognisable prefix.
    public static func newKey() -> String {
        var generator = SystemRandomNumberGenerator()
        let hex = (0..<24).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }.joined()
        return "llvo_" + hex
    }

    /// Checks the Bearer or X-API-Key header without stopping at the first different byte.
    public static func authorized(_ request: HTTPRequest, key: String) -> Bool {
        var supplied = request.headers["x-api-key"] ?? ""
        if let auth = request.headers["authorization"], auth.hasPrefix("Bearer ") {
            supplied = String(auth.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        let a = Array(supplied.utf8)
        let b = Array(key.utf8)
        guard !b.isEmpty, a.count == b.count else { return false }
        return zip(a, b).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private struct ModeBody: Decodable { let mode: String }
    private struct TextBody: Decodable { let text: String }

    @MainActor
    public static func handle(_ request: HTTPRequest, key: String, enabled: Bool, handler: VoiceAPIHandler) async -> HTTPResponse {
        guard enabled else { return .error(403, "API control is off. Turn it on in LahLah Voice › Settings › API.") }
        guard authorized(request, key: key) else {
            return .error(401, "Missing or wrong API key. Send: Authorization: Bearer <key>")
        }
        switch (request.method, request.path) {
        case ("GET", "/v1/health"):
            return .json(200, ["ok": "true", "app": "LahLah Voice"])
        case ("GET", "/v1/status"):
            return .json(200, handler.apiStatus())
        case ("POST", "/v1/dictation/start"):
            return .json(200, ["phase": handler.apiStartDictation()])
        case ("POST", "/v1/dictation/stop"):
            return .json(200, ["phase": handler.apiStopDictation()])
        case ("GET", "/v1/transcripts/last"):
            guard let last = handler.apiLastTranscript() else { return .error(404, "No dictation yet") }
            return .json(200, last)
        case ("PUT", "/v1/mode"), ("POST", "/v1/mode"):
            guard let body = try? JSONDecoder().decode(ModeBody.self, from: request.body),
                let mode = VoiceMode(rawValue: body.mode)
            else { return .error(400, "Send {\"mode\": \"normal\"} or {\"mode\": \"lahlah-video-command\"}") }
            handler.apiSetMode(mode)
            return .json(200, ["mode": mode.rawValue])
        case ("POST", "/v1/lahlah-video/send"):
            guard let body = try? JSONDecoder().decode(TextBody.self, from: request.body),
                !body.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return .error(400, "Send {\"text\": \"split here\"}") }
            let delivery = await handler.apiSendToLahLahVideo(body.text)
            return .json(delivery.ok ? 200 : 502, delivery)
        default:
            return .error(404, "No route \(request.method) \(request.path). Routes: \(routes.joined(separator: ", "))")
        }
    }
}

// MARK: - Talking to LahLah Video

/// How a command reached LahLah Video.
public struct LahLahVideoDelivery: Codable, Sendable, Equatable {
    public var ok: Bool
    public var via: String  // "api" or "deep-link"
    public var message: String

    public init(ok: Bool, via: String, message: String) {
        self.ok = ok
        self.via = via
        self.message = message
    }
}

/// LahLah Video's control.json: written while it runs with its API on.
public struct LahLahVideoControl: Decodable, Sendable, Equatable {
    public let baseUrl: String
    public let apiKey: String
}

public enum LahLahVideoLink {
    public static var controlFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return support.appending(path: "\(LahLahVideoCommands.bundleID)/control.json")
    }

    public static func readControl(at url: URL = controlFileURL) -> LahLahVideoControl? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LahLahVideoControl.self, from: data)
    }

    public static func commandRequest(_ text: String, control: LahLahVideoControl) -> URLRequest? {
        guard let url = URL(string: control.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/commands") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("Bearer \(control.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["text": text])
        return request
    }

    private struct CommandAnswer: Decodable {
        let ok: Bool?
        let message: String?
        let error: String?
    }

    /// Sends through LahLah Video's API. Nil means "not reachable": use the deep link instead.
    public static func sendViaAPI(_ text: String, controlURL: URL = controlFileURL, session: URLSession = .shared) async -> LahLahVideoDelivery? {
        guard let control = readControl(at: controlURL), let request = commandRequest(text, control: control),
            let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }
        let answer = try? JSONDecoder().decode(CommandAnswer.self, from: data)
        let ok = answer?.ok ?? true
        return LahLahVideoDelivery(ok: ok, via: "api", message: answer?.message ?? answer?.error ?? text)
    }
}
