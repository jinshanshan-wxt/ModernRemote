import Foundation
import Combine
import MusicKit

@MainActor final class LibraryStore: ObservableObject {
    @Published var songs: [Song] = []
    @Published var playlists: [Playlist] = []
    @Published var loading = false
    @Published var message = "允许访问 Apple Music 后，即可浏览这台 iPhone 的资料库。"
    @Published var authorized = false
    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let status = await MusicAuthorization.request()
        authorized = status == .authorized
        guard authorized else { message = "尚未获得授权。请在设置中允许访问“媒体与 Apple Music”。你仍可浏览 Mac 资料库。"; return }
        songs = []; playlists = []
        do {
            var offset = 0
            while true {
                try Task.checkCancellation()
                var request = MusicLibraryRequest<Song>()
                request.limit = 200; request.offset = offset
                let page = try await request.response().items
                songs.append(contentsOf: page)
                message = "已加载 \(songs.count) 首歌曲……"
                offset += page.count
                if page.count < 200 { break }
            }
            offset = 0
            while true {
                try Task.checkCancellation()
                var request = MusicLibraryRequest<Playlist>()
                request.limit = 100; request.offset = offset
                let page = try await request.response().items
                playlists.append(contentsOf: page)
                offset += page.count
                if page.count < 100 { break }
            }
            message = "\(songs.count) 首歌曲 · \(playlists.count) 个播放列表"
        } catch { message = "资料库未加载完整：\(error.localizedDescription)。请点击“重新加载资料库”重试。" }
    }
    static func remote(_ song: Song) -> RemoteTrack {
        RemoteTrack(id: song.id.rawValue, title: song.title, artist: song.artistName,
                    album: song.albumTitle ?? "", duration: song.duration ?? 0)
    }
    static func playlistSongs(_ playlist: Playlist) async throws -> [Song] {
        let detailed = try await playlist.with([.tracks], preferredSource: .library)
        guard var page = detailed.tracks else { return [] }
        var songs: [Song] = []
        while true {
            try Task.checkCancellation()
            for track in page { if case .song(let song) = track { songs.append(song) } }
            guard page.hasNextBatch, let next = try await page.nextBatch(limit: 200) else { break }
            page = next
        }
        return songs
    }
}
