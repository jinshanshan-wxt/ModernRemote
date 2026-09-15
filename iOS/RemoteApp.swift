import SwiftUI
import MusicKit
import Network

@main struct ModernRemoteApp: App {
    @StateObject private var remote = RemoteClient()
    @StateObject private var library = LibraryStore()
    var body: some Scene {
        WindowGroup {
            AdaptiveRemoteView()
                .tint(.pink).environmentObject(remote).environmentObject(library)
                .environment(\.locale, Locale(identifier: "zh_Hans"))
        }
    }
}

enum RemoteSection: String, CaseIterable, Identifiable {
    case songs, albums, artists, playlists, macLibrary, player, connection
    var id: String { rawValue }
    var title: String {
        switch self {
        case .songs: return "歌曲"
        case .albums: return "专辑"
        case .artists: return "艺人"
        case .playlists: return "播放列表"
        case .macLibrary: return "Mac 资料库"
        case .player: return "正在播放"
        case .connection: return "连接"
        }
    }
    var symbol: String {
        switch self {
        case .songs: return "music.note"
        case .albums: return "square.stack.fill"
        case .artists: return "person.fill"
        case .playlists: return "music.note.list"
        case .macLibrary: return "desktopcomputer"
        case .player: return "play.circle.fill"
        case .connection: return "wifi"
        }
    }
    var category: String {
        switch self {
        case .albums: return "Albums"
        case .artists: return "Artists"
        case .playlists: return "Playlists"
        default: return "Songs"
        }
    }
}

struct AdaptiveRemoteView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject var remote: RemoteClient
    @State private var selection: RemoteSection? = .connection
    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var pairingCode = ""
    private var usesSidebar: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
        #else
        return false
        #endif
    }
    private var compactSelection: Binding<Int> {
        Binding(get: {
            switch selection {
            case .macLibrary: return 1
            case .player: return 2
            case .connection, nil: return 3
            default: return 0
            }
        }, set: { value in
            switch value {
            case 1: selection = .macLibrary
            case 2: selection = .player
            case 3: selection = .connection
            default: selection = .songs
            }
        })
    }
    var body: some View {
        Group {
            if usesSidebar {
                NavigationSplitView(columnVisibility: $visibility) {
                    List(selection: $selection) {
                        Section("Apple Music") {
                            ForEach([RemoteSection.songs, .albums, .artists, .playlists]) { item in
                                NavigationLink(value: item) { Label(item.title, systemImage: item.symbol) }
                            }
                        }
                        Section("这台 Mac") {
                            ForEach([RemoteSection.macLibrary, .player, .connection]) { item in
                                NavigationLink(value: item) { Label(item.title, systemImage: item.symbol) }
                            }
                        }
                        Section {
                            Label(remote.connected ? "已连接 Mac" : "尚未连接", systemImage: remote.connected ? "checkmark.circle.fill" : "wifi.slash")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .listStyle(.sidebar)
                    .navigationTitle("音乐遥控")
                    .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 300)
                } detail: {
                    detail
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            if selection != .player {
                                TabletPlaybackBar { selection = .player }
                            }
                        }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                TabView(selection: compactSelection) {
                    LibraryView(category: selection?.category ?? "Songs").tabItem { Label("资料库", systemImage: "music.note.house") }.tag(0)
                    MacLibraryView().tabItem { Label("Mac 资料库", systemImage: "desktopcomputer") }.tag(1)
                    PlayerView().tabItem { Label("正在播放", systemImage: "play.circle.fill") }.tag(2)
                    ConnectionView(key: $pairingCode).tabItem { Label("连接", systemImage: "wifi") }.tag(3)
                }
            }
        }
    }
    @ViewBuilder private var detail: some View {
        switch selection ?? .connection {
        case .songs, .albums, .artists, .playlists:
            LibraryView(category: (selection ?? .songs).category, showsCategoryPicker: false)
                .id(selection)
        case .macLibrary: MacLibraryView()
        case .player: PlayerView()
        case .connection: ConnectionView(key: $pairingCode)
        }
    }
}

struct TabletPlaybackBar: View {
    @EnvironmentObject var remote: RemoteClient
    var showPlayer: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            Button(action: showPlayer) {
                HStack(spacing: 12) {
                    Image(systemName: "hifispeaker.fill").font(.title2).frame(width: 44, height: 44)
                        .background(.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(remote.playback.title).font(.headline).lineLimit(1)
                        Text(remote.connected ? remote.playback.artist : "先连接 Mac，再选择音乐")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("打开正在播放：\(remote.playback.title)")
            Button { remote.command(remote.playback.playing ? "pause" : "play") } label: {
                Image(systemName: remote.playback.playing ? "pause.fill" : "play.fill")
                    .font(.title2).frame(width: 44, height: 44)
            }.accessibilityLabel(remote.playback.playing ? "暂停" : "播放")
                .disabled(!remote.connected || remote.busy)
            Button { remote.command("next") } label: {
                Image(systemName: "forward.end.fill").font(.title2).frame(width: 44, height: 44)
            }.accessibilityLabel("下一首").disabled(!remote.connected || remote.busy)
        }.padding(.horizontal, 20).padding(.vertical, 12)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
    }
}

struct ConnectionView: View {
    @EnvironmentObject var remote: RemoteClient
    @Binding var key: String
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
    @State private var category: String
    var showsCategoryPicker: Bool
    init(category: String = "Songs", showsCategoryPicker: Bool = true) {
        _category = State(initialValue: category)
        self.showsCategoryPicker = showsCategoryPicker
    }
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
                    if showsCategoryPicker {
                        Picker("浏览分类", selection: $category) { ForEach(categories, id: \.self) { Text(categoryTitle($0)).tag($0) } }.pickerStyle(.menu)
                    }
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
            }.navigationTitle(showsCategoryPicker ? "我的资料库" : categoryTitle(category)).searchable(text: $search, prompt: "搜索资料库")
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
            ScrollView {
              VStack(spacing: 24) {
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
              }.padding(28).frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }.disabled(!remote.connected)
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
