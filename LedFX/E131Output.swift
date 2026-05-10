import Foundation
import Network

final class E131Output: @unchecked Sendable {
    private var connection: NWConnection?
    private var sequence: UInt8 = 0
    private var routeKey: String?
    private let cid: UUID
    private var packet: [UInt8]

    init() {
        cid = UUID()
        packet = [UInt8](repeating: 0, count: 638)
        Self.writeHeader(into: &packet, cid: cid)
    }

    private static func writeHeader(into packet: inout [UInt8], cid: UUID) {
        var o = 0
        packet[o] = 0x00
        packet[o + 1] = 0x10
        o += 2
        packet[o] = 0x00
        packet[o + 1] = 0x00
        o += 2
        let acn: [UInt8] = [0x41, 0x53, 0x43, 0x2d, 0x45, 0x31, 0x2e, 0x31, 0x37, 0x00, 0x00, 0x00]
        for b in acn {
            packet[o] = b
            o += 1
        }

        packet[o] = 0x02
        packet[o + 1] = 0x6c
        o += 2
        packet[o] = 0x00
        packet[o + 1] = 0x00
        packet[o + 2] = 0x00
        packet[o + 3] = 0x04
        o += 4

        var uuid = cid.uuid
        withUnsafeBytes(of: &uuid) { buf in
            for i in 0..<16 {
                packet[o + i] = buf[i]
            }
        }
        o += 16

        packet[o] = 0x02
        packet[o + 1] = 0x56
        o += 2
        packet[o] = 0x00
        packet[o + 1] = 0x00
        packet[o + 2] = 0x00
        packet[o + 3] = 0x02
        o += 4

        let name = "LedFX iOS"
        for b in name.utf8 {
            packet[o] = b
            o += 1
        }
        while o < 108 {
            packet[o] = 0
            o += 1
        }

        packet[o] = 100
        o += 1
        packet[o] = 0
        packet[o + 1] = 0
        o += 2
        packet[o] = 0
        o += 1
        packet[o] = 0
        o += 1

        packet[o] = 0x00
        packet[o + 1] = 0x01
        o += 2

        packet[o] = 0x02
        packet[o + 1] = 0x09
        o += 2
        packet[o] = 0x02
        o += 1
        packet[o] = 0xa1
        o += 1
        packet[o] = 0x00
        packet[o + 1] = 0x00
        o += 2
        packet[o] = 0x00
        packet[o + 1] = 0x01
        o += 2
        packet[o] = 0x02
        packet[o + 1] = 0x01
        o += 2
        packet[o] = 0x00
        o += 1
        while o < 638 {
            packet[o] = 0
            o += 1
        }
    }

    func send(pixels: [RGB], host: String, port: UInt16, universe: UInt16, useMulticast: Bool) {
        let key = "\(useMulticast ? "m" : "u")|\(host)|\(port)|\(universe)"
        if routeKey != key {
            connection?.cancel()
            connection = nil
            routeKey = key
        }

        let endpointHost: NWEndpoint.Host
        if useMulticast {
            let hi = Int((universe >> 8) & 0xff)
            let lo = Int(universe & 0xff)
            endpointHost = NWEndpoint.Host("239.255.\(hi).\(lo)")
        } else {
            endpointHost = NWEndpoint.Host(host)
        }

        if connection == nil {
            connection = NWConnection(
                host: endpointHost,
                port: NWEndpoint.Port(rawValue: port)!,
                using: .udp
            )
            connection?.start(queue: .global(qos: .userInteractive))
        }

        sequence &+= 1
        let u = Int(universe)
        packet[113] = UInt8((u >> 8) & 0xff)
        packet[114] = UInt8(u & 0xff)
        packet[111] = sequence

        let dmxOffset = 125
        var c = 0
        for px in pixels {
            if c + 3 > 510 { break }
            packet[dmxOffset + c] = px.r
            packet[dmxOffset + c + 1] = px.g
            packet[dmxOffset + c + 2] = px.b
            c += 3
        }
        if c < 512 {
            for j in c..<512 {
                packet[dmxOffset + j] = 0
            }
        }

        let data = Data(packet)
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    func reset() {
        connection?.cancel()
        connection = nil
        routeKey = nil
    }
}
