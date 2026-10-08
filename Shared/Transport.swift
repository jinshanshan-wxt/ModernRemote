import Foundation
import Network
import Security

enum SecureLAN {
    static let service = "_modernremote._tcp"
    static func parameters() -> NWParameters {
        // Explicitly open LAN sharing: no account, pairing, or authentication.
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        return parameters
    }
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
        let timeout = DispatchWorkItem { [weak self] in self?.close("连接超时，请检查 Mac 是否已开启共享。") }
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
