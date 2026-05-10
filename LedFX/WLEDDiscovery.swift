import Darwin
import Foundation

final class WLEDDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var pending = [NetService]()
    private var resolved = [WLEDDiscoveredDevice]()

    var onUpdate: (([WLEDDiscoveredDevice]) -> Void)?

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        resolved.removeAll()
        pending.removeAll()
        browser.searchForServices(ofType: "_wled._tcp.", inDomain: "local.")
    }

    func stop() {
        browser.stop()
        pending.removeAll()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        pending.append(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        resolved.removeAll { $0.name == service.name }
        notify()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        pending.removeAll { $0 == sender }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        defer { notify() }
        var ipv4: String?
        if let first = sender.addresses?.first {
            ipv4 = Self.ipv4String(from: first)
        }
        let dev = WLEDDiscoveredDevice(
            name: sender.name,
            hostName: sender.hostName ?? sender.name,
            ipv4: ipv4
        )
        resolved.removeAll { $0.name == sender.name }
        resolved.append(dev)
        pending.removeAll { $0 == sender }
    }

    private static func ipv4String(from data: Data) -> String? {
        data.withUnsafeBytes { raw -> String? in
            guard raw.count >= MemoryLayout<sockaddr_in>.size else { return nil }
            let family = raw.load(as: sockaddr_storage.self).ss_family
            guard family == sa_family_t(AF_INET) else { return nil }
            let sin = raw.load(as: sockaddr_in.self)
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var addr = sin.sin_addr
            inet_ntop(AF_INET, &addr, &buf, socklen_t(buf.count))
            return String(cString: buf)
        }
    }

    private func notify() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onUpdate?(self.resolved.sorted { $0.name < $1.name })
        }
    }
}
