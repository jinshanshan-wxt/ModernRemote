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
    var favorite: Bool? = nil
    var albumFavorite: Bool? = nil
    var playCount: Int? = nil
    var year: Int? = nil
    var rating: Int? = nil
    var albumRating: Int? = nil
    var downloaded: Bool? = nil
    var discNumber: Int? = nil
    var macID: String? = nil
}
struct RemotePlaylist: Codable, Identifiable {
    var id: String
    var name: String
    var trackCount: Int? = nil
    var favorite: Bool? = nil
}
struct AudioRoute: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var kind: String
    var selected: Bool
    var available: Bool
    var requiresPassword: Bool = false
    var active: Bool? = nil
    var isSystem: Bool { id.hasPrefix("core:") }
}
struct Playback: Codable {
    var trackID: String? = nil
    var title = "尚未播放"
    var artist = ""
    var playing = false
    var position: Double = 0
    var duration: Double = 0
    var volume: Double = 50
    var shuffle: Bool? = nil
    var repeatMode: Int? = nil
}
struct Packet: Codable {
    var cacheInfo: LibraryCacheInfo? = nil
    var refresh: Bool? = nil
    var clearArtwork: Bool? = nil
    var version = 1
    var id = UUID().uuidString
    var action: String
    var track: RemoteTrack? = nil
    var value: Double? = nil
    var offset: Int? = nil
    var tracks: [RemoteTrack]? = nil
    var trackIDs: [String]? = nil
    var hasMore: Bool? = nil
    var playback: Playback? = nil
    var artworkID: String? = nil
    var artwork: Data? = nil
    var routes: [AudioRoute]? = nil
    var routeID: String? = nil
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

// Unknown metadata stays last in either direction; ties have a stable ID order.
enum LibrarySort: String, CaseIterable {
    case title, plays, genre, duration, favorite, artist, downloaded, album, year, rating, added
    var title: String {
        switch self {
        case .title: return "标题"
        case .plays: return "播放次数"
        case .genre: return "类型"
        case .duration: return "时长"
        case .favorite: return "喜爱"
        case .artist: return "艺人"
        case .downloaded: return "云端下载"
        case .album: return "专辑"
        case .year: return "年份"
        case .rating: return "评分"
        case .added: return "添加日期"
        }
    }
    static func options(for category: String) -> [Self] {
        switch category {
        case "Albums": return [.title, .artist, .year, .rating]
        case "Artists": return [.title]
        case "Genres", "Playlists": return [.title]
        case "Recent": return [.added, .title, .artist, .year]
        default: return [.title, .plays, .genre, .duration, .favorite, .artist, .downloaded, .album]
        }
    }
}
enum LibrarySorting {
    static func less(_ left: [RemoteTrack], _ right: [RemoteTrack], order: LibrarySort, descending: Bool,
                     context: String, leftTitle: String? = nil, rightTitle: String? = nil) -> Bool {
        func text(_ tracks: [RemoteTrack], _ groupTitle: String?) -> String {
            guard let first = tracks.first else { return "" }
            switch order {
            case .artist: return first.albumArtist.isEmpty ? first.artist : first.albumArtist
            case .album: return first.album
            case .genre: return first.genre
            default: return groupTitle ?? first.title
            }
        }
        func numeric(_ tracks: [RemoteTrack]) -> Double? {
            switch order {
            case .plays:
                let values = tracks.compactMap(\.playCount); return values.isEmpty ? nil : Double(values.reduce(0, +))
            case .duration: return tracks.reduce(0) { $0 + $1.duration }
            case .favorite:
                let values = tracks.compactMap { context == "Albums" ? $0.albumFavorite : $0.favorite }
                return values.isEmpty ? nil : (values.contains(true) ? 1 : 0)
            case .downloaded:
                let values = tracks.compactMap(\.downloaded); return values.isEmpty ? nil : (values.allSatisfy { $0 } ? 1 : 0)
            case .year: return tracks.compactMap(\.year).filter { $0 > 0 }.min().map(Double.init)
            case .rating: return tracks.compactMap { context == "Albums" ? $0.albumRating : $0.rating }.max().map(Double.init)
            case .added: return tracks.map(\.dateAdded).max()
            default: return nil
            }
        }
        let comparison: ComparisonResult
        if [.plays, .duration, .favorite, .downloaded, .year, .rating, .added].contains(order) {
            let a = numeric(left), b = numeric(right)
            if a == nil && b != nil { return false }
            if a != nil && b == nil { return true }
            comparison = a == b ? .orderedSame : ((a ?? 0) < (b ?? 0) ? .orderedAscending : .orderedDescending)
        } else {
            comparison = text(left, leftTitle).localizedStandardCompare(text(right, rightTitle))
        }
        if comparison == .orderedSame {
            let a = leftTitle ?? left.first?.title ?? "", b = rightTitle ?? right.first?.title ?? ""
            let titleOrder = a.localizedStandardCompare(b)
            if titleOrder == .orderedSame { return (left.first?.id ?? "") < (right.first?.id ?? "") }
            return titleOrder == .orderedAscending
        }
        return comparison == (descending ? .orderedDescending : .orderedAscending)
    }
}

// Playback and output changes must not wait behind a screenful of artwork requests.
struct RequestQueue {
    private var packets: [Packet] = []
    var isEmpty: Bool { packets.isEmpty }
    mutating func append(_ packet: Packet) {
        if packet.action == "status", packets.contains(where: { $0.action == "status" }) { return }
        packets.append(packet)
    }
    mutating func removeFirst() -> Packet {
        let background = Set(["library", "artwork", "playlists"])
        let index = packets.firstIndex { !background.contains($0.action) } ?? 0
        return packets.remove(at: index)
    }
}

struct QuickScrollTarget {
    let id: String
    let title: String
    let label: String
    init(id: String, title: String) {
        self.id = id; self.title = title
        // Chinese names use their pinyin initial; numbers and punctuation use #.
        let latin = title.applyingTransform(.toLatin, reverse: false)?
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "zh_CN")) ?? title
        let initial = latin.trimmingCharacters(in: .whitespaces).uppercased().prefix(1)
        label = initial.first.map { $0.isASCII && $0.isLetter ? String($0) : "#" } ?? "#"
    }
}
enum LibraryNavigation {
    static func albumsInGenre(_ library: [RemoteTrack], genre: String) -> [RemoteTrack] {
        func key(_ track: RemoteTrack) -> String { track.album + "\u{0}" + (track.albumArtist.isEmpty ? track.artist : track.albumArtist) }
        let albums = Set(library.filter { ($0.genre.isEmpty ? "未分类" : $0.genre) == genre }.map(key))
        return library.filter { albums.contains(key($0)) }
    }
    static func position(_ fraction: Double, count: Int) -> Int {
        guard count > 0, fraction.isFinite else { return 0 }
        return min(count - 1, max(0, Int((min(1, max(0, fraction)) * Double(count - 1)).rounded())))
    }
    static func albumTracks(_ tracks: [RemoteTrack], playlist: Bool = false) -> [RemoteTrack] {
        if playlist { return tracks }
        return tracks.sorted {
            if $0.album != $1.album { return $0.album.localizedStandardCompare($1.album) == .orderedAscending }
            if $0.discNumber != $1.discNumber { return ($0.discNumber ?? 1) < ($1.discNumber ?? 1) }
            if $0.trackNumber != $1.trackNumber { return $0.trackNumber < $1.trackNumber }
            return $0.id < $1.id
        }
    }
}


struct PlaybackSelection {
    let ids: [String]
    let start: Int
    init?(tracks: [RemoteTrack], selectedID: String) {
        guard let index = tracks.firstIndex(where: { $0.id == selectedID }) else { return nil }
        ids = tracks.map(\.id); start = index
    }
}


// Large original covers travel in bounded chunks; only complete originals enter
// the image cache. Offset checks reject missing, duplicated or reordered chunks.
enum ArtworkTransfer {
    static let chunkSize = 192 * 1024
    static let maximum = 64 * 1024 * 1024
    static func chunk(_ data: Data, offset: Int) throws -> Data {
        guard data.count <= maximum, offset >= 0, offset <= data.count else {
            throw NSError(domain: "ArtworkTransfer", code: 1, userInfo: [NSLocalizedDescriptionKey: "封面传输位置无效。"])
        }
        return data.subdata(in: offset..<min(data.count, offset + chunkSize))
    }
}
struct ArtworkAssembly {
    private(set) var data = Data()
    mutating func append(_ bytes: Data, offset: Int, hasMore: Bool) throws -> Data? {
        guard offset == data.count, bytes.count <= ArtworkTransfer.maximum - data.count, !hasMore || !bytes.isEmpty else {
            throw NSError(domain: "ArtworkTransfer", code: 2, userInfo: [NSLocalizedDescriptionKey: "封面分块不完整。"])
        }
        data.append(bytes)
        return hasMore ? nil : data
    }
}
