import Foundation
import Network

final class WLEDHTTPOutput: @unchecked Sendable {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        session = URLSession(configuration: config)
    }

    func send(pixels: [RGB], host: String, port: Int = 80, globalBrightness: Int = 255) async throws {
        guard !pixels.isEmpty else { return }
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port == 80 ? nil : port
        components.path = "/json/state"
        guard let url = components.url else { return }

        let bri = min(255, max(1, globalBrightness))

        var seg: [String: Any] = [
            "id": 0,
            "on": true,
            "bri": bri,
        ]
        let i = pixels.map { [$0.r, $0.g, $0.b] }
        seg["i"] = i

        let body: [String: Any] = [
            "on": true,
            "bri": bri,
            "seg": [seg],
        ]
        let data = try JSONSerialization.data(withJSONObject: body)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data

        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

final class WLEDUDPRealtimeOutput: @unchecked Sendable {
    private var connection: NWConnection?
    private var endpointKey: String?

    func send(pixels: [RGB], host: String, port: UInt16) {
        guard !pixels.isEmpty else { return }
        let key = "\(host):\(port)"
        if endpointKey != key {
            reset()
            endpointKey = key
        }
        var payload = [UInt8](repeating: 0, count: 2 + pixels.count * 3)
        payload[0] = 2
        payload[1] = 2
        var o = 2
        for p in pixels {
            payload[o] = p.r
            payload[o + 1] = p.g
            payload[o + 2] = p.b
            o += 3
        }
        let data = Data(payload)

        if connection == nil {
            connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .udp
            )
            connection?.start(queue: .global(qos: .userInteractive))
        }
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    func reset() {
        connection?.cancel()
        connection = nil
        endpointKey = nil
    }
}
