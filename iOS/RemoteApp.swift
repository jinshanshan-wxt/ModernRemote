import SwiftUI
import MusicKit
import Network

@main struct ModernRemoteApp: App {
    @StateObject private var remote = RemoteClient()
    @StateObject private var library = LibraryStore()
    @State private var selectedTab = 3
    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                LibraryView().tabItem { Label("资料库", systemImage: "music.note.house") }.tag(0)
                MacLibraryView().tabItem { Label("Mac 资料库", systemImage: "desktopcomputer") }.tag(1)
                PlayerView().tabItem { Label("正在播放", systemImage: "play.circle.fill") }.tag(2)
                ConnectionView().tabItem { Label("连接", systemImage: "wifi") }.tag(3)
            }.tint(.pink).environmentObject(remote).environmentObject(library)
                .environment(\.locale, Locale(identifier: "zh_Hans"))
        }
    }
}
struct ConnectionView: View {
    @EnvironmentObject var remote: RemoteClient
    @State private var key = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("局域网加密连接") {
                    Text("先在 Mac 端开启共享，再输入窗口中的四位配对码。")
                    TextField("四位配对码", text: $key)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .font(.system(.title2, design: .monospaced))
                        .onChange(of: key) { _, value in
                            key = String(value.filter { "0123456789".contains($0) }.prefix(4))
                        }
                    ForEach(remote.devices, id: \.endpoint) { device in
                        Button(RemoteClient.name(device)) { remote.connect(device, key: key) }
                            .disabled(!SecureLAN.validSecret(key))
                    }
                    if remote.devices.isEmpty { Text("正在寻找 Mac……请确认两台设备接入同一局域网，并已允许本地网络访问。").foregroundStyle(.secondary) }
                    Button("重新搜索") { remote.discover() }
                }
                Section { Text(remote.message).textSelection(.enabled) }
                if remote.connected { Button("断开连接", role: .destructive) { remote.disconnect() } }
            }.navigationTitle("连接").onAppear { remote.discover() }
        }
    }
}
struct LibraryView: View {
    @EnvironmentObject var remote: RemoteClient
    @EnvironmentObject var library: LibraryStore
    @State private var search = ""
    @State private var category = "Songs"
    private let categories = ["Songs", "Albums", "Artists", "Playlists"]
    private func categoryTitle(_ value: String) -> String {
        switch value {
        case "Songs": return "歌曲"
        case "Albums": return "专辑"
        case "Artists": return "艺人"
        default: return "播放列表"
        }
    }
    private var songs: [Song] {
        library.songs.filter { search.isEmpty || "\($0.title) \($0.artistName) \($0.albumTitle ?? "")".localizedCaseInsensitiveContains(search) }
    }
    private var groups: [(String, [Song])] {
        Dictionary(grouping: songs) { category == "Artists" ? $0.artistName : "\($0.albumTitle ?? "未知专辑") · \($0.artistName)" }
            .map { ($0.key, $0.value) }.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(library.message).font(.caption).foregroundStyle(.secondary)
                    Text(remote.message).font(.caption).foregroundStyle(.secondary)
                    if library.loading { ProgressView() }
                    Button(library.authorized ? "重新加载资料库" : "允许访问 Apple Music") { Task { await library.load() } }.disabled(library.loading)
                    Picker("浏览分类", selection: $category) { ForEach(categories, id: \.self) { Text(categoryTitle($0)).tag($0) } }.pickerStyle(.menu)
                }
                if category == "Songs" {
                    ForEach(songs) { SongRow(song: $0) }
                } else if category == "Playlists" {
                    ForEach(library.playlists.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { playlist in
                        NavigationLink { PlaylistView(playlist: playlist) } label: { Label(playlist.name, systemImage: "music.note.list") }
                    }
                } else {
                    ForEach(groups, id: \.0) { group in
                        NavigationLink {
                            List(group.1) { SongRow(song: $0) }.navigationTitle(group.0)
                        } label: { Label(group.0, systemImage: category == "Artists" ? "person.fill" : "square.stack.fill") }
                    }
                }
            }.navigationTitle("我的资料库").searchable(text: $search, prompt: "搜索资料库")
        }
    }
}
struct SongRow: View {
    @EnvironmentObject var remote: RemoteClient
    let song: Song
    var body: some View {
        Button { remote.play(LibraryStore.remote(song)) } label: {
            HStack(spacing: 12) {
                AsyncImage(url: song.artwork?.url(width: 96, height: 96)) { image in image.resizable().scaledToFill() }
                    placeholder: { Image(systemName: "music.note").frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary) }
                    .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading) {
                    Text(song.title).foregroundStyle(.primary)
                    Text(song.artistName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.fill").font(.caption)
            }
        }.disabled(!remote.connected || remote.busy)
    }
}
struct PlaylistView: View {
    let playlist: Playlist
    @State private var songs: [Song] = []
    @State private var message = "正在加载……"
    var body: some View {
        List {
            Text(message).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(songs.enumerated()), id: \.offset) { entry in SongRow(song: entry.element) }
        }.navigationTitle(playlist.name).task {
            do { songs = try await LibraryStore.playlistSongs(playlist); message = "共 \(songs.count) 首歌曲，点击即可在 Mac 播放。暂不显示音乐视频。" }
            catch { message = error.localizedDescription }
        }
    }
}
struct MacLibraryView: View {
    @EnvironmentObject var remote: RemoteClient
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List {
                Text("直接浏览 Mac“音乐”中的歌曲，包括未同步的本地歌曲。搜索范围为已加载的内容。").font(.caption).foregroundStyle(.secondary)
                Text(remote.message).font(.caption)
                ForEach(Array(remote.macTracks.filter { search.isEmpty || "\($0.title) \($0.artist) \($0.album)".localizedCaseInsensitiveContains(search) }.enumerated()), id: \.offset) { entry in
                    Button { remote.play(entry.element) } label: {
                        VStack(alignment: .leading) {
                            Text(entry.element.title)
                            Text("\(entry.element.artist) · \(entry.element.album)").font(.caption).foregroundStyle(.secondary)
                        }
                    }.disabled(!remote.connected || remote.busy)
                }
                if remote.hasMore {
                    Button(remote.macTracks.isEmpty ? "加载 Mac 资料库" : "继续加载 200 首歌曲") { remote.loadMacPage() }.disabled(!remote.connected || remote.busy)
                }
            }.navigationTitle("Mac 资料库").searchable(text: $search, prompt: "搜索已加载的歌曲")
        }
    }
}
struct PlayerView: View {
    @EnvironmentObject var remote: RemoteClient
    @State private var position = 0.0
    @State private var volume = 50.0
    @State private var seeking = false
    @State private var changingVolume = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "hifispeaker.fill").font(.system(size: 100)).foregroundStyle(.pink.gradient)
                Text(remote.playback.title).font(.title2.bold()).multilineTextAlignment(.center)
                Text(remote.playback.artist).foregroundStyle(.secondary)
                Slider(value: $position, in: 0...max(remote.playback.duration, 1)) { editing in
                    seeking = editing
                    if !editing { remote.command("seek", value: position) }
                }.accessibilityLabel("播放进度")
                HStack { Text(time(position)); Spacer(); Text(time(remote.playback.duration)) }.font(.caption.monospacedDigit())
                HStack(spacing: 42) {
                    Button { remote.command("previous") } label: { Image(systemName: "backward.end.fill") }.accessibilityLabel("上一首")
                    Button { remote.command(remote.playback.playing ? "pause" : "play") } label: {
                        Image(systemName: remote.playback.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 64))
                    }.accessibilityLabel(remote.playback.playing ? "暂停" : "播放")
                    Button { remote.command("next") } label: { Image(systemName: "forward.end.fill") }.accessibilityLabel("下一首")
                }.font(.title)
                HStack {
                    Image(systemName: "speaker.fill")
                    Slider(value: $volume, in: 0...100) { editing in
                        changingVolume = editing
                        if !editing { remote.command("volume", value: volume) }
                    }.accessibilityLabel("Mac“音乐”音量")
                    Image(systemName: "speaker.wave.3.fill")
                }
                Text("由 Mac 的“音乐”应用播放").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(28).disabled(!remote.connected)
                .safeAreaInset(edge: .bottom) { Text(remote.message).font(.caption).padding().textSelection(.enabled) }
                .navigationTitle("正在播放")
                .onReceive(remote.$playback) { state in
                    if !seeking { position = min(max(state.position, 0), max(state.duration, 1)) }
                    if !changingVolume { volume = state.volume }
                }
        }
    }
    private func time(_ value: Double) -> String { let n = max(0, Int(value)); return String(format: "%d:%02d", n / 60, n % 60) }
}
