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
        precondition(MusicBridge.quote("a\"\\b\n") == "\"a\\\"\\\\b\\n\"")
        let unknown = RemoteTrack(id: "u", title: "Unknown", artist: "A", album: "X", duration: 100)
        var low = unknown; low.id = "l"; low.playCount = 1; low.year = 1999; low.downloaded = false
        var high = unknown; high.id = "h"; high.playCount = 99; high.year = 2020; high.downloaded = true
        precondition(LibrarySorting.less([low], [high], order: .plays, descending: false, context: "Songs"))
        precondition(LibrarySorting.less([high], [low], order: .plays, descending: true, context: "Songs"))
        for direction in [false, true] {
            precondition(LibrarySorting.less([low], [unknown], order: .plays, descending: direction, context: "Songs"))
            precondition(!LibrarySorting.less([unknown], [low], order: .plays, descending: direction, context: "Songs"))
        }
        precondition(LibrarySorting.less([low], [high], order: .year, descending: false, context: "Albums"))
        precondition(LibrarySorting.less([high], [low], order: .downloaded, descending: true, context: "Songs"))
        print("PASS: real metadata ordering, ascending/descending and unknowns last")
        print("PASS: fragmented/coalesced Unicode frames, size/version limits, escaping")
        lanTest { print("PASS: all tests"); exit(0) }
        dispatchMain()
    }
    static func tryCount(_ decoder: inout LineDecoder, _ data: Data) -> Int { try! decoder.append(data).count }
    static var retained: [AnyObject] = []
    static func lanTest(completion: @escaping () -> Void) {
        let listener = try! NWListener(using: SecureLAN.parameters(), on: .any)
        retained.append(listener)
        var peers: [Wire] = []
        var replies = 0
        var started = false
        listener.newConnectionHandler = { connection in
            let peer = Wire(connection); peers.append(peer)
            peer.onPacket = { [weak peer] packet in peer?.send(Packet(id: packet.id, action: "reply")) }
            peer.start()
        }
        listener.stateUpdateHandler = { state in
            guard case .ready = state, !started, let port = listener.port else { return }
            started = true
            for _ in 0..<2 {
                let peer = Wire(NWConnection(host: "127.0.0.1", port: port, using: SecureLAN.parameters()))
                peers.append(peer)
                peer.onReady = { [weak peer] in peer?.send(Packet(action: "status")) }
                peer.onPacket = { packet in
                    precondition(packet.action == "reply"); replies += 1
                    if replies == 2 {
                        listener.cancel(); for p in peers { p.close() }
                        print("PASS: two simultaneous LAN controllers, no pairing")
                        completion()
                    }
                }
                peer.start()
            }
        }
        listener.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { if replies != 2 { fatalError("LAN test timed out") } }
    }
}
