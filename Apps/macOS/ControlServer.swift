import AppKit
import Network
import NovaVoiceCore
import Security

/// The API key, kept in the login Keychain (never in a file or a log).
enum APIKeychain {
    private static let service = "com.tertiaryinfotech.lahlahvoice.api"
    private static let account = "local-api-key"

    static func key() -> String {
        if let existing = read() { return existing }
        let key = VoiceAPI.newKey()
        save(key)
        return key
    }

    @discardableResult
    static func regenerate() -> String {
        let key = VoiceAPI.newKey()
        save(key)
        return key
    }

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func save(_ key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrLabel as String] = "LahLah Voice API key"
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// HTTP on 127.0.0.1 for LahLah Voice's local API (routes in NovaVoiceCore/VoiceAPI.swift).
@MainActor
@Observable
final class ControlServer {
    private(set) var port: UInt16 = 0
    private(set) var key: String = ""
    private var listener: NWListener?
    @ObservationIgnored weak var handler: VoiceAPIHandler?
    @ObservationIgnored var isEnabled: () -> Bool = { true }

    var baseURL: String { port == 0 ? "Not running" : "http://127.0.0.1:\(port)" }

    /// ~/Library/Application Support/NovaVoice/control.json: the port only. The key stays in the Keychain.
    static var controlFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appending(path: "NovaVoice/control.json")
    }

    func start() {
        key = APIKeychain.key()
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        guard let listener = try? NWListener(using: parameters) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.serve(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                if case .ready = state, let port = listener.port?.rawValue {
                    self.port = port
                    self.publish()
                }
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
        try? FileManager.default.removeItem(at: Self.controlFile)
    }

    func regenerateKey() {
        key = APIKeychain.regenerate()
    }

    /// Re-reads the toggle: writes or removes control.json.
    func publish() {
        let file = Self.controlFile
        guard isEnabled(), port != 0 else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let doc: [String: Any] = [
            "app": "LahLah Voice", "port": Int(port), "baseUrl": baseURL,
            "keyLocation": "Keychain: LahLah Voice API key (copy it from Settings › API)",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            MainActor.assumeIsolated {
                guard let self else { return connection.cancel() }
                var buffer = buffer
                if let data { buffer.append(data) }
                if let request = HTTPParser.parse(buffer) {
                    Task { @MainActor in
                        let response: HTTPResponse
                        if let handler = self.handler {
                            response = await VoiceAPI.handle(request, key: self.key, enabled: self.isEnabled(), handler: handler)
                        } else {
                            response = .error(500, "LahLah Voice is still starting")
                        }
                        connection.send(content: response.serialized(), completion: .contentProcessed { _ in connection.cancel() })
                    }
                } else if done || error != nil || buffer.count > (1 << 20) {
                    connection.cancel()
                } else {
                    self.receive(connection, buffer: buffer)
                }
            }
        }
    }
}
