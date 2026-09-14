import Foundation
import Network
import Security

// A four-digit pairing code is used as the TLS PSK for this personal-LAN MVP.
// This deliberately favors convenience; it is not a high-entropy secret.
// Never send the secret as an application-level message.
enum SecureLAN {
    static let service = "_modernremote._tcp"
    static func parameters(secret: String) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let key = Data(secret.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data("ModernRemote-v1".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions,
                                                key as __DispatchData, identity as __DispatchData)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions,
                                                    tls_ciphersuite_t(rawValue: 0x00A8)!)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.includePeerToPeer = false
        return parameters
    }
    static func newCode(excluding previous: String? = nil) -> String {
        var code: String
        repeat { code = String(format: "%04d", Int.random(in: 0...9999)) } while code == previous
        return code
    }
    static func validSecret(_ secret: String) -> Bool {
        secret.count == 4 && secret.utf8.allSatisfy { (48...57).contains($0) }
    }
}

// Limit failed online handshakes. This cannot prevent offline guessing of a
// short TLS PSK from a captured handshake; use only on a trusted personal LAN.
struct PairingGate {
    private var failures: [Date] = []
    private(set) var lockedUntil: Date?
    mutating func allowsAttempt(now: Date = Date()) -> Bool {
        if let end = lockedUntil {
            guard now >= end else { return false }
            reset()
        }
        return true
    }
    mutating func failed(now: Date = Date()) {
        failures.removeAll { now.timeIntervalSince($0) >= 60 }
        failures.append(now)
        if failures.count >= 5 { lockedUntil = now.addingTimeInterval(60) }
    }
    mutating func reset() { failures = []; lockedUntil = nil }
}

// All methods and callbacks run on the main queue. At most one outstanding
// application request is allowed by the client, bounding buffers and work.
final class Wire {
    let connection: NWConnection
    var onPacket: ((Packet) -> Void)?
    var onReady: (() -> Void)?
    var onClose: ((String) -> Void)?
    private var decoder = LineDecoder()
    private var closed = false
    private var deadline: DispatchWorkItem?
    init(_ connection: NWConnection) { self.connection = connection }
    func start() {
        let timeout = DispatchWorkItem { [weak self] in self?.close("连接超时，请检查配对码并重试。") }
        deadline = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.deadline?.cancel(); self.onReady?(); self.receive()
            case .failed(let error): self.close(error.localizedDescription)
            case .cancelled: self.close("已断开连接")
            default: break
            }
        }
        connection.start(queue: .main)
    }
    func send(_ packet: Packet) {
        guard !closed else { return }
        do {
            var data = try JSONEncoder().encode(packet)
            guard data.count <= LineDecoder.maximum else { throw ProtocolError.oversized }
            data.append(10)
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error { self?.close(error.localizedDescription) }
            })
        } catch { close(error.localizedDescription) }
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self, !self.closed else { return }
            do {
                if let data { for packet in try self.decoder.append(data) { self.onPacket?(packet) } }
            } catch { self.close("收到的数据格式有误或过大，请重新连接。"); return }
            if let error { self.close(error.localizedDescription) }
            else if done { self.close("对方已断开连接") }
            else { self.receive() }
        }
    }
    func close(_ reason: String = "已断开连接") {
        guard !closed else { return }
        closed = true
        deadline?.cancel()
        connection.cancel()
        onClose?(reason)
        onPacket = nil; onReady = nil; onClose = nil
    }
}
