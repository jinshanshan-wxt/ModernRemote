import Foundation
import CryptoKit

struct LibrarySnapshot: Codable {
    var schema = 1
    var revision: String
    var updatedAt: Double
    var tracks: [RemoteTrack]
    var playlists: [RemotePlaylist]
    var playlistTracks: [String: [RemoteTrack]] = [:]
}
struct LibraryCacheInfo: Codable {
    var serverID: String
    var revision: String?
    var updatedAt: Double?
    var needsRefresh: Bool
}

// Application Support is deliberately used instead of the purgeable Caches directory.
// Files are namespaced by the Mac installation AND Music library, never by host name.
final class LibraryDiskCache {
    let directory: URL
    private let queue = DispatchQueue(label: "ModernRemote.disk-cache", qos: .utility)
    private var artworkWrites = 0
    init(namespace: String, root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ModernRemote/LibraryCache-v1", isDirectory: true)
        directory = base.appendingPathComponent(Self.key(namespace), isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
    }
    static func key(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    func snapshot() -> LibrarySnapshot? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("library.json")),
              let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data), snapshot.schema == 1 else { return nil }
        return snapshot
    }
    func save(_ snapshot: LibrarySnapshot) {
        queue.async { [directory] in
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: directory.appendingPathComponent("library.json"), options: .atomic)
        }
    }
    func artwork(_ id: String) -> Data? {
        try? Data(contentsOf: artworkURL(id))
    }
    func loadArtwork(_ id: String, completion: @escaping (Data?) -> Void) {
        queue.async { completion(self.artwork(id)) }
    }
    func saveArtwork(_ data: Data, id: String) {
        queue.async {
            let folder = self.directory.appendingPathComponent("ArtworkOriginal-v2", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: self.artworkURL(id), options: .atomic)
            self.artworkWrites += 1
            if self.artworkWrites % 50 == 0 { self.trimArtwork(folder) }
        }
    }
    func removeSnapshot() { queue.sync { try? FileManager.default.removeItem(at: directory.appendingPathComponent("library.json")) } }
    func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var excluded = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try? excluded.setResourceValues(values)
        }
    }
    func flush() { queue.sync {} }
    private func artworkURL(_ id: String) -> URL {
        directory.appendingPathComponent("ArtworkOriginal-v2", isDirectory: true).appendingPathComponent(Self.key(id) + ".image")
    }
    private func trimArtwork(_ folder: URL) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        let entries = files.map { url -> (URL, Int, Date) in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return (url, values?.fileSize ?? 0, values?.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var bytes = entries.reduce(0) { $0 + $1.1 }
        for entry in entries where bytes > 256 * 1024 * 1024 {
            try? FileManager.default.removeItem(at: entry.0); bytes -= entry.1
        }
    }
}
