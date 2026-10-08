import Foundation
import Network

@main struct Tests {
    static func main() throws {
        let cacheRoot = FileManager.default.temporaryDirectory.appendingPathComponent("ModernRemote-cache-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let first = LibraryDiskCache(namespace: "Mac A:Library 1", root: cacheRoot)
        let cachedTrack = RemoteTrack(id: "0123456789ABCDEF", title: "缓存歌曲", artist: "艺人", album: "专辑", duration: 180)
        let cachedSnapshot = LibrarySnapshot(revision: "r1", updatedAt: 1234, tracks: [cachedTrack], playlists: [], playlistTracks: ["playlist": [cachedTrack]])
        first.save(cachedSnapshot); first.saveArtwork(Data([1, 2, 3]), id: cachedTrack.id); first.saveArtwork(Data(), id: "missing"); first.flush()
        let reopened = LibraryDiskCache(namespace: "Mac A:Library 1", root: cacheRoot)
        precondition(reopened.snapshot()?.tracks == [cachedTrack])
        precondition(reopened.snapshot()?.playlistTracks["playlist"] == [cachedTrack])
        precondition(reopened.artwork(cachedTrack.id) == Data([1, 2, 3]))
        precondition(reopened.artwork("missing") == Data())
        precondition(LibraryDiskCache(namespace: "Mac B:Library 1", root: cacheRoot).snapshot() == nil)
        precondition(LibraryDiskCache(namespace: "Mac A:Library 2", root: cacheRoot).artwork(cachedTrack.id) == nil)
        first.removeSnapshot(); precondition(first.snapshot() == nil && first.artwork(cachedTrack.id) != nil)
        try Data("broken snapshot".utf8).write(to: first.directory.appendingPathComponent("library.json"))
        precondition(first.snapshot() == nil)
        first.save(cachedSnapshot); first.flush(); precondition(first.snapshot()?.revision == "r1")
        first.clear(); precondition(first.snapshot() == nil && first.artwork(cachedTrack.id) == nil)
        print("PASS: disk cache survives re-instantiation, isolates Mac/libraries, stores playlists and missing artwork, recovers corruption, clears safely")
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
        var addedLater = low; addedLater.dateAdded = 300
        var addedEarlier = high; addedEarlier.dateAdded = 100
        precondition(LibrarySorting.less([low, addedLater], [addedEarlier], order: .added, descending: true, context: "Recent"))
        print("PASS: recently added albums use newest track date, descending")
        var requests = RequestQueue()
        for _ in 0..<100 { requests.append(Packet(action: "artwork")) }
        requests.append(Packet(action: "route", routeID: "air:test"))
        requests.append(Packet(action: "pause"))
        precondition(requests.removeFirst().action == "route")
        precondition(requests.removeFirst().action == "pause")
        precondition(requests.removeFirst().action == "artwork")
        print("PASS: AirPlay/playback controls bypass 100 queued artwork requests, preserving control order")
        precondition(LibraryNavigation.position(0, count: 2777) == 0)
        precondition(LibraryNavigation.position(1, count: 2777) == 2776)
        precondition(LibraryNavigation.position(-1, count: 3) == 0)
        precondition(LibraryNavigation.position(2, count: 3) == 2)
        precondition(LibraryNavigation.position(0.5, count: 0) == 0)
        precondition(QuickScrollTarget(id: "a", title: "周杰伦").label == "Z")
        precondition(QuickScrollTarget(id: "a", title: "123").label == "#")
        var one = unknown; one.id = "1"; one.album = "Album"; one.genre = "New Age"; one.trackNumber = 1; one.discNumber = 1
        var two = one; two.id = "2"; two.genre = "Pop"; two.trackNumber = 2
        var disc2 = one; disc2.id = "3"; disc2.discNumber = 2
        var other = one; other.id = "4"; other.album = "Other"; other.genre = "Rock"
        precondition(LibraryNavigation.albumsInGenre([one, two, disc2, other], genre: "New Age").map(\.id) == ["1", "2", "3"])
        precondition(LibraryNavigation.albumTracks([disc2, two, one]).map(\.id) == ["1", "2", "3"])
        precondition(LibraryNavigation.albumTracks([two, one], playlist: true).map(\.id) == ["2", "1"])
        let selected = PlaybackSelection(tracks: [one, two, disc2], selectedID: two.id)!
        precondition(selected.ids == [one.id, two.id, disc2.id] && selected.start == 1)
        precondition(PlaybackSelection(tracks: [one], selectedID: other.id) == nil)
        let selectedPacket = Packet(action: "queue", offset: selected.start, trackIDs: selected.ids)
        let decodedSelection = try JSONDecoder().decode(Packet.self, from: JSONEncoder().encode(selectedPacket))
        precondition(decodedSelection.offset == 1 && decodedSelection.trackIDs == selected.ids)
        // A large song list fits one bounded frame without repeating metadata.
        let bigQueue = Packet(action: "queue", offset: 9999, trackIDs: (0..<10000).map { String(format: "%016X", $0) })
        precondition(trySize(bigQueue) < LineDecoder.maximum)
        print("PASS: contextual selection includes full ordered IDs + exact starting index; 10000-song bounded queue")
        let shufflePacket = Packet(action: "queue", value: 1, tracks: [one])
        let decodedShuffle = try JSONDecoder().decode(Packet.self, from: JSONEncoder().encode(shufflePacket))
        precondition(decodedShuffle.value == 1)
        print("PASS: genre selects full albums; multi-disc order; playlist order; quick-scroll bounds/pinyin; shuffle queue flag")
        lanTest { print("PASS: all tests"); exit(0) }
        dispatchMain()
    }
    static func trySize(_ packet: Packet) -> Int { try! JSONEncoder().encode(packet).count }
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
