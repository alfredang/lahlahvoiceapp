import Foundation
import Testing

@testable import NovaVoiceCore

@MainActor
private final class FakeHandler: VoiceAPIHandler {
    var mode = VoiceMode.normal
    var sent: [String] = []
    var started = 0

    func apiStatus() -> VoiceAPIStatus {
        VoiceAPIStatus(version: "test", phase: "idle", mode: mode, lastTranscript: "hello", lahlahVideoAvailable: false)
    }
    func apiStartDictation() -> String {
        started += 1
        return "listening"
    }
    func apiStopDictation() -> String { "working" }
    func apiLastTranscript() -> DictationRecord? {
        DictationRecord(raw: "um hello", final: "Hello", durationSeconds: 1, usedAppleIntelligence: false)
    }
    func apiSetMode(_ mode: VoiceMode) { self.mode = mode }
    func apiSendToLahLahVideo(_ text: String) async -> LahLahVideoDelivery {
        sent.append(text)
        return LahLahVideoDelivery(ok: true, via: "deep-link", message: text)
    }
}

@MainActor
@Suite struct VoiceAPITests {
    private let key = "llvo_0123456789abcdef0123456789abcdef0123456789abcdef"

    private func request(_ method: String, _ path: String, body: String = "", auth: String? = nil) -> HTTPRequest {
        HTTPRequest(
            method: method, path: path,
            headers: ["Authorization": "Bearer \(auth ?? key)"], body: Data(body.utf8))
    }

    @Test func keysAreRandomAndPrefixed() {
        let a = VoiceAPI.newKey()
        #expect(a.hasPrefix("llvo_") && a.count == 53)
        #expect(a != VoiceAPI.newKey())
    }

    @Test func refusesWithoutTheKeyOrWhenOff() async {
        let handler = FakeHandler()
        let wrong = await VoiceAPI.handle(request("GET", "/v1/status", auth: "nope"), key: key, enabled: true, handler: handler)
        #expect(wrong.status == 401)
        let off = await VoiceAPI.handle(request("GET", "/v1/status"), key: key, enabled: false, handler: handler)
        #expect(off.status == 403)
        let xKey = HTTPRequest(method: "GET", path: "/v1/health", headers: ["X-API-Key": key])
        #expect(await VoiceAPI.handle(xKey, key: key, enabled: true, handler: handler).status == 200)
    }

    @Test func routesEveryEndpoint() async throws {
        let handler = FakeHandler()
        let status = await VoiceAPI.handle(request("GET", "/v1/status"), key: key, enabled: true, handler: handler)
        #expect(status.status == 200)
        #expect(String(decoding: status.body, as: UTF8.self).contains("\"lastTranscript\":\"hello\""))
        #expect(await VoiceAPI.handle(request("POST", "/v1/dictation/start"), key: key, enabled: true, handler: handler).status == 200)
        #expect(handler.started == 1)
        #expect(await VoiceAPI.handle(request("POST", "/v1/dictation/stop"), key: key, enabled: true, handler: handler).status == 200)
        let last = await VoiceAPI.handle(request("GET", "/v1/transcripts/last"), key: key, enabled: true, handler: handler)
        #expect(String(decoding: last.body, as: UTF8.self).contains("\"final\":\"Hello\""))
        let mode = await VoiceAPI.handle(request("PUT", "/v1/mode", body: #"{"mode":"lahlah-video-command"}"#), key: key, enabled: true, handler: handler)
        #expect(mode.status == 200 && handler.mode == .lahlahVideoCommand)
        let badMode = await VoiceAPI.handle(request("PUT", "/v1/mode", body: #"{"mode":"party"}"#), key: key, enabled: true, handler: handler)
        #expect(badMode.status == 400)
        let send = await VoiceAPI.handle(request("POST", "/v1/lahlah-video/send", body: #"{"text":"split here"}"#), key: key, enabled: true, handler: handler)
        #expect(send.status == 200 && handler.sent == ["split here"])
        #expect(await VoiceAPI.handle(request("GET", "/v1/nope"), key: key, enabled: true, handler: handler).status == 404)
    }

    @Test func parsesRequestsOnlyWhenComplete() {
        let raw = "POST /v1/mode?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 8\r\nX-API-Key: k\r\n\r\n{\"a\":1}"
        #expect(HTTPParser.parse(Data(raw.utf8)) == nil)  // 7 of 8 body bytes
        let full = HTTPParser.parse(Data((raw + " ").utf8))
        #expect(full?.method == "POST" && full?.path == "/v1/mode" && full?.headers["x-api-key"] == "k" && full?.body.count == 8)
        let response = HTTPResponse.error(401, "no").serialized()
        #expect(String(decoding: response, as: UTF8.self).hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
    }

    @Test func buildsTheLahLahVideoRequestFromItsControlFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "control.json")
        try Data(#"{"app":"LahLah Video","port":5123,"baseUrl":"http://127.0.0.1:5123","apiKey":"llv_abc","version":"1.1.0"}"#.utf8).write(to: file)
        let control = try #require(LahLahVideoLink.readControl(at: file))
        let request = try #require(LahLahVideoLink.commandRequest("add crossfade", control: control))
        #expect(request.url?.absoluteString == "http://127.0.0.1:5123/v1/commands")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer llv_abc")
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self) == #"{"text":"add crossfade"}"#)
        #expect(LahLahVideoLink.readControl(at: dir.appending(path: "missing.json")) == nil)
    }

    @Test func fallsBackWhenLahLahVideoIsNotRunning() async {
        let missing = FileManager.default.temporaryDirectory.appending(path: "no-such-\(UUID().uuidString).json")
        #expect(await LahLahVideoLink.sendViaAPI("split here", controlURL: missing) == nil)
    }
}
