import Foundation

struct RemoteTrack: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var dateAdded: Double = 0
    var genre: String = ""
    var albumArtist: String = ""
    var trackNumber: Int = 0
    var macID: String? = nil
}
struct RemotePlaylist: Codable, Identifiable {
    var id: String
    var name: String
}
struct Playback: Codable {
    var trackID: String? = nil
    var title = "尚未播放"
    var artist = ""
    var playing = false
    var position: Double = 0
    var duration: Double = 0
    var volume: Double = 50
}
struct Packet: Codable {
    var version = 1
    var id = UUID().uuidString
    var action: String
    var track: RemoteTrack? = nil
    var value: Double? = nil
    var offset: Int? = nil
    var tracks: [RemoteTrack]? = nil
    var hasMore: Bool? = nil
    var playback: Playback? = nil
    var artworkID: String? = nil
    var artwork: Data? = nil
    var queue: [RemoteTrack]? = nil
    var playlists: [RemotePlaylist]? = nil
    var playlistID: String? = nil
    var error: String? = nil
}
struct LineDecoder {
    static let maximum = 1_048_576
    private var buffer = Data()
    mutating func append(_ data: Data) throws -> [Packet] {
        buffer.append(data)
        var packets: [Packet] = []
        while let index = buffer.firstIndex(of: 10) {
            let line = buffer[..<index]
            guard line.count <= Self.maximum else { throw ProtocolError.oversized }
            let packet = try JSONDecoder().decode(Packet.self, from: line)
            guard packet.version == 1 else { throw ProtocolError.version }
            packets.append(packet)
            buffer.removeSubrange(...index)
        }
        guard buffer.count <= Self.maximum else { throw ProtocolError.oversized }
        return packets
    }
}
enum ProtocolError: Error { case oversized, version }
