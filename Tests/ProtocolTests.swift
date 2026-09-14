import Foundation
import Network

@main struct Tests {
    static func main() throws {
        let packet = Packet(action: "track", track: RemoteTrack(id: "id", title: "雪 / \"song\"\n", artist: "Artist", album: "Album", duration: 180))
        var data = try JSONEncoder().encode(packet); data.append(10)
        var decoder = LineDecoder()
        var received: [Packet] = []
        for byte in data { received += try decoder.append(Data([byte])) }
        precondition(received.count == 1 && received[0].track == packet.track)
        precondition(tryCount(&decoder, data + data) == 2)
        do { _ = try decoder.append(Data(repeating: 65, count: LineDecoder.maximum + 1)); fatalError("Oversized input accepted") }
        catch ProtocolError.oversized {} catch { fatalError("Wrong error") }
        var invalid = LineDecoder()
        do { _ = try invalid.append(Data("{\"version\":2,\"id\":\"1\",\"action\":\"status\"}\n".utf8)); fatalError("Unknown version accepted") }
        catch ProtocolError.version {} catch { fatalError("Wrong error") }
        precondition(SecureLAN.validSecret("0386"))
        precondition(SecureLAN.validSecret("0000"))
        precondition(SecureLAN.validSecret("9999"))
        for invalid in ["123", "12345", "１２３４", "1a23", " 123", "123\n"] {
            precondition(!SecureLAN.validSecret(invalid))
        }
        for _ in 0..<1000 {
            let code = SecureLAN.newCode(excluding: "0386")
            precondition(SecureLAN.validSecret(code) && code != "0386")
        }
        var gate = PairingGate()
        let start = Date(timeIntervalSince1970: 1000)
        for index in 0..<5 {
            precondition(gate.allowsAttempt(now: start.addingTimeInterval(Double(index))))
            gate.failed(now: start.addingTimeInterval(Double(index)))
        }
        precondition(!gate.allowsAttempt(now: start.addingTimeInterval(63)))
        precondition(gate.allowsAttempt(now: start.addingTimeInterval(64)))
        gate.failed(now: start); gate.reset()
        precondition(gate.allowsAttempt(now: start))
        print("PASS: four digits, leading zeros, code rotation and failed-attempt cooldown")
        precondition(!SecureLAN.validSecret("short"))
        precondition(MusicBridge.quote("a\"\\b\n") == "\"a\\\"\\\\b\\n\"")
        print("PASS: fragmented/coalesced Unicode frames, size/version limits, key validation, escaping")
        tlsTest(correct: true) { tlsTest(correct: false) { print("PASS: all tests"); exit(0) } }
        dispatchMain()
    }
    static func tryCount(_ decoder: inout LineDecoder, _ data: Data) -> Int { try! decoder.append(data).count }
    static var retained: [AnyObject] = []
    static func tlsTest(correct: Bool, completion: @escaping () -> Void) {
        let secret = "0386"
        let listener = try! NWListener(using: SecureLAN.parameters(secret: secret), on: .any)
        retained.append(listener)
        var client: Wire?
        var server: Wire?
        var finished = false
        func finish() {
            guard !finished else { return }; finished = true
            listener.cancel(); client?.close(); server?.close()
            print(correct ? "PASS: TLS-PSK encrypted request/reply" : "PASS: wrong key rejected before command delivery")
            DispatchQueue.main.async { completion() }
        }
        listener.newConnectionHandler = { connection in
            let peer = Wire(connection); server = peer
            peer.onPacket = { packet in
                precondition(correct, "Unauthorized message delivered")
                peer.send(Packet(id: packet.id, action: "reply"))
            }
            peer.start()
        }
        listener.stateUpdateHandler = { state in
            guard case .ready = state, let port = listener.port else { return }
            let peer = Wire(NWConnection(host: "127.0.0.1", port: port,
                                         using: SecureLAN.parameters(secret: correct ? secret : "0387")))
            client = peer
            peer.onReady = { precondition(correct, "Wrong key authenticated"); peer.send(Packet(action: "status")) }
            peer.onPacket = { packet in precondition(packet.action == "reply"); finish() }
            peer.onClose = { _ in if !finished { precondition(!correct, "Valid connection failed"); finish() } }
            peer.start()
        }
        listener.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { if !finished { fatalError("TLS test timed out") } }
    }
}
