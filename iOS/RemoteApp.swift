import SwiftUI
import Network
import UniformTypeIdentifiers

@main struct ModernRemoteApp: App {
    @StateObject private var remote = RemoteClient()
    init() {
        // UIKit-backed navigation and tab controllers must share the app accent,
        // including controllers created again when tapping More repeatedly.
        let accent = UIColor(named: "AccentColor") ?? UIColor(red: 1, green: 0.15, blue: 0.25, alpha: 1)
        UIView.appearance().tintColor = accent
        UINavigationBar.appearance().tintColor = accent
        UITabBar.appearance().tintColor = accent
    }
    var body: some Scene {
        WindowGroup {
            AdaptiveRemoteView().tint(Color.accentColor).environmentObject(remote)
                .environment(\.locale, Locale(identifier: "zh_Hans"))

        }
    }
}

enum LibrarySection: String, CaseIterable, Identifiable {
    case artists = "Artists", albums = "Albums", songs = "Songs", genres = "Genres"
    case playlists = "Playlists", recent = "Recent", search = "Search"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .artists: return "艺人"
        case .albums: return "专辑"
        case .songs: return "歌曲"
        case .genres: return "类型"
        case .playlists: return "播放列表"
        case .recent: return "最近添加"
        case .search: return "搜索"
        }
    }
    var symbol: String {
        switch self {
        case .artists: return "music.mic"
        case .albums: return "square.stack"
        case .songs: return "music.note"
        case .genres: return "guitars"
        case .playlists: return "music.note.list"
        case .recent: return "clock"
        case .search: return "magnifyingglass"
        }
    }
    static let defaults: [LibrarySection] = [.artists, .albums, .songs, .genres]
    static func tabs(_ stored: String) -> [LibrarySection] {
        var result: [LibrarySection] = []
        for value in stored.split(separator: ",") {
            if let section = LibrarySection(rawValue: String(value)), !result.contains(section) { result.append(section) }
        }
        for section in defaults where !result.contains(section) { result.append(section) }
        return Array(result.prefix(4))
    }
}
struct LibraryDestination: View {
    let section: LibrarySection
    var body: some View {
        if section == .search { LibrarySearchView() }
        else { LibraryView(category: section.rawValue) }
    }
}
struct AdaptiveRemoteView: View {
    @EnvironmentObject var remote: RemoteClient
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("navigation.tabs") private var tabOrder = "Artists,Albums,Songs,Genres"
    @State private var selection = "Artists"
    @State private var showPlayer = false
    var body: some View {
        Group {
            if sizeClass == .regular {
                PadLibraryView(showPlayer: { showPlayer = true })
            } else if #available(iOS 26.0, *) {
                tabs.tabViewBottomAccessory { MiniPlayer { showPlayer = true } }
            } else { tabs }
        }
        .fullScreenCover(isPresented: $showPlayer) { PlayerView() }
        .task { remote.discover() }
        .onChange(of: tabOrder) { _, _ in
            if selection != "More", !LibrarySection.tabs(tabOrder).contains(where: { $0.rawValue == selection }) { selection = "More" }
        }
    }
    private var tabs: some View {
        TabView(selection: $selection) {
            ForEach(LibrarySection.tabs(tabOrder)) { section in
                NavigationStack { LibraryDestination(section: section) }
                    .modifier(LegacyPlayerInset(showPlayer: { showPlayer = true }))
                    .tabItem { Label(section.title, systemImage: section.symbol) }.tag(section.rawValue)
            }
            NavigationStack { MoreView(tabOrder: $tabOrder) }
                .modifier(LegacyPlayerInset(showPlayer: { showPlayer = true }))
                .tabItem { Label("更多", systemImage: "ellipsis") }.tag("More")
        }.tint(.accentColor)
    }
}
struct PadLibraryView: View {
    @EnvironmentObject var remote: RemoteClient
    var showPlayer: () -> Void
    @State private var category: String? = "Albums"
    @State private var visibility: NavigationSplitViewVisibility = .all
    private let sections: [(String, String, String)] = [
        ("Recent", "最近添加", "clock"), ("Artists", "艺人", "music.mic"),
        ("Albums", "专辑", "square.stack"), ("Songs", "歌曲", "music.note"),
        ("Genres", "类型", "guitars"), ("Playlists", "播放列表", "music.note.list"),
        ("Search", "搜索", "magnifyingglass")
    ]
    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            List(selection: $category) {
                Section("资料库") {
                    ForEach(sections, id: \.0) { item in
                        Button { category = item.0 } label: {
                            Label(item.1, systemImage: item.2)
                                .foregroundStyle(category == item.0 ? Color.accentColor : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).tag(item.0)
                    }
                }
                Section {
                    Button { category = "Settings" } label: {
                        Label("设置", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).tag("Settings")
                }
            }.listStyle(.sidebar).navigationTitle("音乐")
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
        } detail: {
            NavigationStack {
                detail.safeAreaPadding(.bottom, 90)
            }.id(category).clipped()
        }.navigationSplitViewStyle(.balanced).tint(Color.accentColor)
            .overlay(alignment: .bottom) { PadPlaybackBar(showPlayer: showPlayer) }
    }
    @ViewBuilder private var detail: some View {
        if category == "Settings" { SettingsView() }
        else if category == "Search" { LibrarySearchView() }
        else { LibraryView(category: category ?? "Albums") }
    }
}
struct PadPlaybackBar: View {
    @EnvironmentObject var remote: RemoteClient
    var showPlayer: () -> Void
    @State private var showRoutes = false
    @State private var showVolume = false
    @State private var volume = 50.0
    var body: some View {
        HStack(spacing: 18) {
            Button { remote.command("shuffle", value: remote.playback.shuffle == true ? 0 : 1) } label: {
                Image(systemName: "shuffle").foregroundStyle(remote.playback.shuffle == true ? .primary : .secondary)
            }.accessibilityLabel("随机播放")
            Button { remote.command("previous") } label: { Image(systemName: "backward.fill") }.accessibilityLabel("上一首")
            Button { remote.command(remote.playback.playing ? "pause" : "play") } label: {
                Image(systemName: remote.playback.playing ? "pause.fill" : "play.fill").font(.system(size: 30))
            }.accessibilityLabel(remote.playback.playing ? "暂停" : "播放")
            Button { remote.command("next") } label: { Image(systemName: "forward.fill") }.accessibilityLabel("下一首")
            Button { remote.command("repeat", value: Double(((remote.playback.repeatMode ?? 0) + 1) % 3)) } label: {
                Image(systemName: remote.playback.repeatMode == 2 ? "repeat.1" : "repeat")
                    .foregroundStyle((remote.playback.repeatMode ?? 0) > 0 ? .primary : .secondary)
            }.accessibilityLabel("循环播放")
            Button(action: showPlayer) {
                HStack(spacing: 10) {
                    MacArtwork(id: remote.playback.trackID, size: 44, retainPreviousImage: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(remote.playback.title).font(.subheadline.weight(.medium)).lineLimit(1)
                        Text(remote.playback.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.accessibilityLabel("打开正在播放")
            Button { showVolume = true } label: { Image(systemName: "speaker.wave.2").frame(width: 30, height: 40) }.accessibilityLabel("播放音量")
                .popover(isPresented: $showVolume) {
                    Slider(value: $volume, in: 0...100) { editing in if !editing { remote.command("volume", value: volume) } }
                        .padding(24).frame(width: 240).onAppear { volume = remote.playback.volume }
                }
            Button { showRoutes = true } label: { Image(systemName: "airplay.audio").frame(width: 30, height: 40) }.accessibilityLabel("AirPlay 与音频输出")
        }.font(.system(size: 19)).buttonStyle(.plain).foregroundStyle(.primary)
            .padding(.horizontal, 22).padding(.vertical, 10).frame(maxWidth: 700)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 1) }
            .disabled(!remote.connected)
            .sheet(isPresented: $showRoutes) { AudioOutputView().presentationDetents([.medium, .large]) }
            .padding(.horizontal, 20).padding(.bottom, 12).padding(.top, 8)
            .frame(maxWidth: .infinity)
    }
}
struct LegacyPlayerInset: ViewModifier {
    var showPlayer: () -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content }
        else {
            content.safeAreaInset(edge: .bottom) {
                MiniPlayer(showPlayer: showPlayer).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 10).padding(.bottom, 6)
            }
        }
    }
}
struct MiniPlayer: View {
    @EnvironmentObject var remote: RemoteClient
    var showPlayer: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: showPlayer) {
                HStack(spacing: 12) {
                    MacArtwork(id: remote.playback.trackID, size: 40, retainPreviousImage: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(remote.playback.title).font(.subheadline.weight(.medium)).lineLimit(1)
                        Text(remote.connected ? remote.playback.artist : "正在寻找 Mac")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("打开正在播放：\(remote.playback.title)")
            Button { remote.command(remote.playback.playing ? "pause" : "play") } label: {
                Image(systemName: remote.playback.playing ? "pause.fill" : "play.fill").font(.title3).frame(width: 38, height: 44)
            }.accessibilityLabel(remote.playback.playing ? "暂停" : "播放").disabled(!remote.connected)
            Button { remote.command("next") } label: {
                Image(systemName: "forward.fill").font(.title3).frame(width: 38, height: 44)
            }.accessibilityLabel("下一首").disabled(!remote.connected)
        }.buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6)
    }
}
struct MoreView: View {
    @Binding var tabOrder: String
    @State private var editing = false
    private var remaining: [LibrarySection] { LibrarySection.allCases.filter { !LibrarySection.tabs(tabOrder).contains($0) } }
    var body: some View {
        List {
            ForEach(remaining) { section in
                NavigationLink { LibraryDestination(section: section) } label: {
                    Label(section.title, systemImage: section.symbol)
                }
            }
            Section {
                NavigationLink { SettingsView() } label: { Label("设置", systemImage: "gearshape") }
            }
        }.navigationTitle("更多")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("编辑") { editing = true } } }
            .sheet(isPresented: $editing) { TabEditor(tabOrder: $tabOrder) }
    }
}
struct TabEditor: View {
    @Binding var tabOrder: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSlot = 0
    private var tabs: [LibrarySection] { LibrarySection.tabs(tabOrder) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("选择一个底部位置，再点选分类；也可以把分类拖到该位置。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        ForEach(Array(tabs.enumerated()), id: \.offset) { index, section in
                            Button { selectedSlot = index } label: {
                                item(section).frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(selectedSlot == index ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain)
                                .onDrag { NSItemProvider(object: section.rawValue as NSString) }
                                .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                                    guard let provider = providers.first else { return false }
                                    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                                        guard let text = object as? String, let section = LibrarySection(rawValue: text) else { return }
                                        DispatchQueue.main.async { assign(section, to: index) }
                                    }
                                    return true
                                }
                        }
                    }
                    Divider()
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 28) {
                        ForEach(LibrarySection.allCases) { section in
                            Button { assign(section, to: selectedSlot) } label: {
                                item(section).frame(maxWidth: .infinity).frame(height: 82)
                            }.buttonStyle(.plain)
                                .onDrag { NSItemProvider(object: section.rawValue as NSString) }
                        }
                    }
                    Button("恢复默认 Tab") { tabOrder = LibrarySection.defaults.map(\.rawValue).joined(separator: ",") }
                }.padding(24)
            }.navigationTitle("编辑 Tab 栏").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.tint(.accentColor)
    }
    private func item(_ section: LibrarySection) -> some View {
        VStack(spacing: 8) {
            Image(systemName: section.symbol).font(.system(size: 25))
            Text(section.title).font(.caption)
        }.foregroundStyle(Color.accentColor)
    }
    private func assign(_ section: LibrarySection, to index: Int) {
        var result = tabs
        if let existing = result.firstIndex(of: section) { result.swapAt(existing, index) }
        else { result[index] = section }
        tabOrder = result.map(\.rawValue).joined(separator: ",")
    }
}
struct LibrarySearchView: View {
    @EnvironmentObject var remote: RemoteClient
    @State private var query = ""
    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var songs: [RemoteTrack] {
        remote.macTracks.filter { !$0.title.isEmpty && $0.title.localizedCaseInsensitiveContains(term) }
    }
    private var albums: [(String, [RemoteTrack])] {
        Dictionary(grouping: remote.macTracks, by: albumKey).map { ($0.key, $0.value) }
            .filter { $0.1.first?.album.localizedCaseInsensitiveContains(term) == true }.sorted { $0.0 < $1.0 }
    }
    private var artists: [(String, [RemoteTrack])] {
        Dictionary(grouping: remote.macTracks, by: \.artist).map { ($0.key, $0.value) }
            .filter { $0.0.localizedCaseInsensitiveContains(term) }.sorted { $0.0 < $1.0 }
    }
    private var playlists: [RemotePlaylist] { remote.playlists.filter { $0.name.localizedCaseInsensitiveContains(term) } }
    var body: some View {
        List {
            if term.isEmpty {
                ContentUnavailableView("搜索", systemImage: "magnifyingglass", description: Text("歌曲、艺人、专辑和播放列表"))
            } else {
                if !songs.isEmpty { Section("歌曲") { ForEach(songs) { MacTrackRow(track: $0, showArtwork: false, playbackContext: songs) } } }
                if !albums.isEmpty {
                    Section("专辑") { ForEach(albums, id: \.0) { album in
                        NavigationLink { TrackCollectionView(title: album.0, tracks: album.1) } label: {
                            HStack { MacArtwork(id: album.1.first?.id, size: 44); Text(album.0).font(.subheadline) }
                        }
                    } }
                }
                if !artists.isEmpty { Section("艺人") { ForEach(artists, id: \.0) { artist in
                    NavigationLink(artist.0) { ArtistAlbumsView(name: artist.0, tracks: artist.1) }
                } } }
                if !playlists.isEmpty { Section("播放列表") { ForEach(playlists) { playlist in
                    NavigationLink(playlist.name) { MacPlaylistView(playlist: playlist) }
                } } }
                if songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty {
                    ContentUnavailableView.search(text: term)
                }
            }
        }.listStyle(.plain).navigationTitle("搜索")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索")
            .autocorrectionDisabled()
    }
}
struct SettingsView: View {
    @EnvironmentObject var remote: RemoteClient
    var body: some View {
        Form {
            Section("Mac") {
                NavigationLink { LibrarySelectionView() } label: {
                    LabeledContent("资料库选择", value: remote.macName.isEmpty ? "自动选择" : remote.macName)
                }
                NavigationLink { ConnectionView() } label: { Label("连接设置", systemImage: "wifi") }
            }
            Section("资料库") {
                LabeledContent("歌曲", value: "\(remote.macTracks.count)")
                LabeledContent("播放列表", value: "\(remote.playlists.count)")
                Button("重新加载资料库与封面") { remote.reloadLibrary() }.disabled(!remote.connected || remote.busy || remote.loadingLibrary)
                Text("所有分类、搜索、播放列表和封面都来自选中的 Mac“音乐”资料库。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("磁盘缓存") {
                if let timestamp = remote.cacheUpdatedAt {
                    LabeledContent("资料库更新时间") { Text(Date(timeIntervalSince1970: timestamp), style: .date) }
                }
                Text("曲库、播放列表和封面保存在本机。启动先读缓存；每 24 小时检查更新，曲目数量变化时重新读取。手动刷新会更新 Mac 与本机缓存。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("状态") { Text(remote.message).textSelection(.enabled) }
            Section("关于") {
                LabeledContent("音乐遥控", value: "0.7.0")
                Text("同一局域网免配对，可同时连接多台遥控设备。").font(.footnote)
            }
        }.navigationTitle("设置")
    }
}
struct LibrarySelectionView: View {
    @EnvironmentObject var remote: RemoteClient
    var body: some View {
        List {
            Section {
                ForEach(remote.devices, id: \.endpoint) { device in
                    Button { remote.connect(device) } label: {
                        HStack {
                            Label(RemoteClient.name(device), systemImage: "desktopcomputer")
                            Spacer()
                            if remote.connected && remote.macName == RemoteClient.name(device) { Image(systemName: "checkmark") }
                        }
                    }
                }
                if remote.devices.isEmpty { Text("正在寻找已开启共享的 Mac……") }
            } footer: { Text("选择要浏览和控制的 Mac。下次优先连接这台 Mac，无需配对。") }
            Button("重新搜索") { remote.discover(restart: true) }
        }.navigationTitle("资料库选择").onAppear { remote.discover() }
    }
}
struct ConnectionView: View {
    @EnvironmentObject var remote: RemoteClient
    #if targetEnvironment(simulator)
    @State private var host = "127.0.0.1"
    #else
    @State private var host = ""
    #endif
    @State private var port = ""
    var body: some View {
        Form {
            Section("自动连接") {
                Text("Mac 开启共享后自动发现。同一局域网直接连接，无需配对码。")
                Text(remote.message).font(.footnote).foregroundStyle(.secondary)
                Button("重新搜索 Mac") { remote.discover(restart: true) }
            }
            Section("手动连接") {
                TextField("Mac 地址", text: $host).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Mac 端口", text: $port).keyboardType(.numberPad)
                Button("连接") { remote.connect(host: host, port: port) }.disabled(host.isEmpty || port.isEmpty)
                Text("地址和端口见 Mac 菜单栏面板。").font(.footnote).foregroundStyle(.secondary)
            }
            if remote.connected { Button("断开连接", role: .destructive) { remote.disconnect() } }
        }.navigationTitle("连接设置")
    }
}

struct LibraryView: View {
    @EnvironmentObject var remote: RemoteClient
    let category: String
    @State private var search = ""
    @AppStorage private var descending: Bool
    @AppStorage private var sortRaw: String
    @AppStorage private var favoritesOnly: Bool
    @AppStorage private var showArtwork: Bool
    @AppStorage private var showArtist: Bool
    @AppStorage private var showAlbum: Bool
    @AppStorage private var showDuration: Bool
    @AppStorage private var showRating: Bool
    @AppStorage private var gridLayout: Bool
    @AppStorage private var showPlaylistCount: Bool
    @AppStorage private var gridSize: Double
    @State private var showDisplayOptions = false
    init(category: String) {
        self.category = category
        let prefix = "browser.\(category == "Recent" ? "RecentAlbums" : category)."
        _descending = AppStorage(wrappedValue: category == "Recent", prefix + "descending")
        _sortRaw = AppStorage(wrappedValue: category == "Recent" ? "added" : "title", prefix + "sort")
        _favoritesOnly = AppStorage(wrappedValue: false, prefix + "favorites")
        _showArtwork = AppStorage(wrappedValue: true, prefix + "artwork")
        _showArtist = AppStorage(wrappedValue: true, prefix + "artist")
        _showAlbum = AppStorage(wrappedValue: true, prefix + "album")
        _showDuration = AppStorage(wrappedValue: false, prefix + "duration")
        _showRating = AppStorage(wrappedValue: false, prefix + "rating")
        _gridLayout = AppStorage(wrappedValue: category == "Albums" || category == "Recent", prefix + "grid")
        _showPlaylistCount = AppStorage(wrappedValue: true, prefix + "playlistCount")
        _gridSize = AppStorage(wrappedValue: 170.0, prefix + "size")
    }
    private var order: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .title }
    private var title: String {
        ["Recent": "最近添加", "Songs": "歌曲", "Albums": "专辑", "Artists": "艺人", "Playlists": "播放列表", "Genres": "类型"][category] ?? category
    }
    @State private var songs: [RemoteTrack] = []
    @State private var groups: [(String, [RemoteTrack])] = []
    @State private var scrollTargets: [QuickScrollTarget] = []
    private var indexKey: String { "\(remote.libraryGeneration):\(category):\(sortRaw):\(descending):\(favoritesOnly):\(search)" }
    private func rebuildIndex() async {
        let tracks = remote.macTracks, category = category, search = search
        let favorites = favoritesOnly, order = order, descending = descending
        let result = await Task.detached(priority: .userInitiated) {
            let songs = tracks.filter { track in
                (search.isEmpty || "\(track.title) \(track.artist) \(track.album) \(track.genre)".localizedCaseInsensitiveContains(search)) &&
                (!favorites || ((category == "Albums" || category == "Recent") ? track.albumFavorite == true : category == "Artists" ? true : track.favorite == true))
            }.sorted { LibrarySorting.less([$0], [$1], order: order, descending: descending, context: "Songs") }
            let groups: [(String, [RemoteTrack])] = Dictionary(grouping: (category == "Albums" || category == "Recent") ? tracks : songs) { t in
                switch category {
                case "Artists": return t.artist.isEmpty ? "未知艺人" : t.artist
                case "Genres": return t.genre.isEmpty ? "未分类" : t.genre
                default: return albumKey(t)
                }
            }.map { ($0.key, $0.value) }.filter { group in
                guard category == "Albums" || category == "Recent" else { return true }
                return (search.isEmpty || group.1.contains { "\($0.title) \($0.artist) \($0.album)".localizedCaseInsensitiveContains(search) }) &&
                    (!favorites || group.1.contains { $0.albumFavorite == true })
            }.sorted { LibrarySorting.less($0.1, $1.1, order: order, descending: descending, context: category, leftTitle: $0.0, rightTitle: $1.0) }
            let targets = category == "Songs" ? songs.map { QuickScrollTarget(id: $0.id, title: $0.title) } : groups.map { QuickScrollTarget(id: $0.0, title: $0.0) }
            return (songs, groups, targets)
        }.value
        guard !Task.isCancelled else { return }
        songs = result.0; groups = result.1; scrollTargets = result.2
    }
    var body: some View {
        ScrollViewReader { proxy in
        Group {
            if category == "Recent" || (category == "Albums" && gridLayout) {
                ScrollView {
                    loading
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: gridSize, maximum: gridSize + 80), spacing: 18)], spacing: 24) {
                        ForEach(groups, id: \.0) { group in
                            NavigationLink { TrackCollectionView(title: group.0, tracks: group.1) } label: {
                                AlbumTile(tracks: group.1, showArtist: showArtist)
                            }.buttonStyle(.plain).id(group.0)
                        }
                    }.padding(.horizontal, 20).padding(.bottom, 20)
                }
            } else {
                List {
                    if remote.loadingLibrary || !remote.connected { loading.listRowSeparator(.hidden) }
                    if category == "Songs" {
                        ForEach(songs) { track in
                            MacTrackRow(track: track, showArtwork: false, showArtist: showArtist, showAlbum: showAlbum, showDuration: showDuration, showRating: showRating, playbackContext: songs)
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 26)).id(track.id)
                        }
                    } else if category == "Playlists" {
                        ForEach(remote.playlists.filter { (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) && (!favoritesOnly || $0.favorite == true) }.sorted { descending ? $0.name > $1.name : $0.name < $1.name }) { list in
                            NavigationLink { MacPlaylistView(playlist: list) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "music.note.list").frame(width: 30)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(list.name)
                                        if showPlaylistCount, let count = list.trackCount { Text("\(count) 首歌曲").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }.padding(.vertical, 10)
                            }
                        }
                    } else {
                        ForEach(groups, id: \.0) { group in
                            NavigationLink {
                                if category == "Artists" { ArtistAlbumsView(name: group.0, tracks: group.1) }
                                else if category == "Genres" { GenreAlbumsView(name: group.0, tracks: LibraryNavigation.albumsInGenre(remote.macTracks, genre: group.0)) }
                                else { TrackCollectionView(title: group.0, tracks: group.1) }
                            } label: {
                                HStack(spacing: 14) {
                                    if category != "Genres", showArtwork, let first = group.1.first {
                                        MacArtwork(id: first.id, size: 56).clipShape(RoundedRectangle(cornerRadius: category == "Artists" ? 28 : 8))
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(category == "Albums" ? (group.1.first?.album ?? "未知专辑") : group.0).font(.body)
                                        if category == "Albums" && showArtist { Text(group.1.first.map { $0.albumArtist.isEmpty ? $0.artist : $0.albumArtist } ?? "").font(.caption).foregroundStyle(.secondary) }
                                        if category != "Genres" { Text("\(group.1.count) 首歌曲").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }.padding(.vertical, 4)
                            }.id(group.0)
                        }
                    }
                }.listStyle(.plain).environment(\.defaultMinListRowHeight, 46)
            }
        }.overlay(alignment: .trailing) {
            if ["Songs", "Artists", "Albums", "Recent"].contains(category) {
                QuickScrollRail(targets: scrollTargets) { id in
                    var transaction = Transaction(); transaction.disablesAnimations = true
                    withTransaction(transaction) { proxy.scrollTo(id, anchor: .top) }
                }
            }
        }
        }.task(id: indexKey) { await rebuildIndex() }
        .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if category != "Genres" {
                            Section {
                                Button { favoritesOnly = false } label: { Label("所有" + (category == "Recent" ? "专辑" : title), systemImage: favoritesOnly ? "" : "checkmark") }
                                Button { favoritesOnly = true } label: { Label("仅喜爱", systemImage: favoritesOnly ? "checkmark" : "") }.disabled(category == "Artists")
                            }
                        }
                        Menu("排序选项") {
                            Picker("排序", selection: $sortRaw) {
                                ForEach(LibrarySort.options(for: category), id: \.self) { option in Text(option.title).tag(option.rawValue) }
                            }
                            Divider()
                            Picker("顺序", selection: $descending) { Text("升序").tag(false); Text("降序").tag(true) }
                        }
                        Divider()
                        Button("查看显示选项") { showDisplayOptions = true }
                    } label: {
                        HStack(spacing: 5) { Image(systemName: "line.3.horizontal.decrease"); Image(systemName: "chevron.down").font(.caption2.bold()) }
                    }.accessibilityLabel("筛选与显示选项")
                }
            }
            .sheet(isPresented: $showDisplayOptions) {
                NavigationStack {
                    Form {
                        if category == "Playlists" { Toggle("显示歌曲数量", isOn: $showPlaylistCount) }
                        if category == "Recent" { Slider(value: $gridSize, in: 130...230, step: 10) { Text("封面大小") } }
                        if category == "Albums" {
                            Picker("显示方式", selection: $gridLayout) { Text("网格").tag(true); Text("列表").tag(false) }
                            if gridLayout { Slider(value: $gridSize, in: 130...230, step: 10) { Text("封面大小") } }
                        }
                        if category != "Playlists" {
                            if category != "Songs" && category != "Recent" && (category != "Albums" || !gridLayout) { Toggle("显示封面", isOn: $showArtwork) }
                            if category == "Albums" || category == "Songs" || category == "Recent" { Toggle("显示艺人", isOn: $showArtist) }
                            if category == "Songs" {
                                Toggle("显示专辑", isOn: $showAlbum)
                                Toggle("显示时长", isOn: $showDuration)
                                Toggle("显示评分", isOn: $showRating)
                            }
                        }
                        if category == "Artists" { Text("Mac“音乐”的公开接口没有提供艺人喜爱标记，因此“仅喜爱”暂不可用。").font(.footnote).foregroundStyle(.secondary) }
                    }.navigationTitle("显示选项").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showDisplayOptions = false } } }
                }.presentationDetents([.medium, .large])
            }
    }
    @ViewBuilder private var loading: some View {
        if remote.loadingLibrary {
            HStack { ProgressView(); Text("正在读取 Mac · \(remote.macTracks.count) 首").font(.footnote).foregroundStyle(.secondary) }.padding()
        } else if !remote.connected {
            ContentUnavailableView("正在寻找 Mac", systemImage: "desktopcomputer", description: Text("在 Mac 开启共享即可自动连接。更多 → 设置中可选择资料库和管理连接。"))
        }
    }
}
private func albumKey(_ track: RemoteTrack) -> String {
    "\(track.album.isEmpty ? "未知专辑" : track.album) · \(track.albumArtist.isEmpty ? track.artist : track.albumArtist)"
}
struct AlbumTile: View {
    let tracks: [RemoteTrack]
    var showArtist = true
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in MacArtwork(id: tracks.first?.id, size: geometry.size.width) }.aspectRatio(1, contentMode: .fit)
            Text(tracks.first?.album ?? "未知专辑").font(.subheadline).lineLimit(1)
            if showArtist { Text(tracks.first.map { $0.albumArtist.isEmpty ? $0.artist : $0.albumArtist } ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
}
struct ArtistAlbumsView: View {
    let name: String
    let tracks: [RemoteTrack]
    private var albums: [(String, [RemoteTrack])] {
        Dictionary(grouping: tracks, by: albumKey).map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 18)], spacing: 24) {
                ForEach(albums, id: \.0) { album in
                    NavigationLink { TrackCollectionView(title: album.0, tracks: album.1) } label: { AlbumTile(tracks: album.1) }.buttonStyle(.plain)
                }
            }.padding(20)
        }.navigationTitle(name)
    }
}
struct GenreAlbumsView: View {
    let name: String
    private let albums: [(String, [RemoteTrack])]
    init(name: String, tracks: [RemoteTrack]) {
        self.name = name
        albums = Dictionary(grouping: tracks, by: albumKey).map { ($0.key, $0.value) }
            .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }
    var body: some View {
        List {
            ForEach(albums, id: \.0) { album in
                NavigationLink { TrackCollectionView(title: album.0, tracks: album.1) } label: {
                    HStack(spacing: 14) {
                        MacArtwork(id: album.1.first?.id, size: 88)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(album.1.first?.album ?? "未知专辑").font(.body).lineLimit(2)
                            if let track = album.1.first {
                                Text([track.albumArtist.isEmpty ? track.artist : track.albumArtist,
                                      (track.year ?? 0) > 0 ? String(track.year!) : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Text("\(album.1.count) 首歌曲").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
            }
        }.listStyle(.plain).navigationTitle(name)
    }
}
struct TrackCollectionView: View {
    @EnvironmentObject var remote: RemoteClient
    @Environment(\.horizontalSizeClass) private var sizeClass
    let title: String
    let tracks: [RemoteTrack]
    var isPlaylist = false
    var loading = false
    private var sorted: [RemoteTrack] { LibraryNavigation.albumTracks(tracks, playlist: isPlaylist) }
    private var albumTitle: String { isPlaylist ? title : (tracks.first?.album.isEmpty == false ? tracks.first!.album : title) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: sizeClass == .regular ? .bottom : .top, spacing: sizeClass == .regular ? 30 : 14) {
                    MacArtwork(id: tracks.first?.id, size: sizeClass == .regular ? 240 : 100)
                    information.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 12) {
                        collectionButton("播放", symbol: "play.fill", shuffle: false)
                        collectionButton("随机播放", symbol: "shuffle", shuffle: true)
                    }
                }.padding(.top, sizeClass == .regular ? 20 : 8)
                if loading { ProgressView("正在读取播放列表……") }
                LazyVStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, track in
                        HStack(spacing: 10) {
                            if !isPlaylist {
                                Text("\(index + 1)").font(.system(size: 14).monospacedDigit()).foregroundStyle(.secondary)
                                    .frame(width: 26, alignment: .leading)
                            }
                            MacTrackRow(track: track, showArtwork: isPlaylist, showArtist: isPlaylist, showAlbum: false, showDuration: true, playbackContext: sorted)
                        }.padding(.vertical, 3)
                        Divider()
                    }
                }
                Text("\(tracks.count) 首歌曲 · \(Int(tracks.reduce(0) { $0 + $1.duration }) / 60) 分钟")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.bottom, sizeClass == .regular ? 110 : 24)
        }.navigationTitle(albumTitle).navigationBarTitleDisplayMode(.inline)
    }
    private func collectionButton(_ title: String, symbol: String, shuffle: Bool) -> some View {
        Button { remote.playQueue(sorted, shuffle: shuffle) } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44).background(.thinMaterial, in: Circle())
        }.buttonStyle(.plain).tint(.accentColor).accessibilityLabel(title)
            .disabled(!remote.connected || tracks.isEmpty || loading)
    }
    private var information: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(albumTitle).font(sizeClass == .regular ? .largeTitle.bold() : .headline).lineLimit(sizeClass == .regular ? 4 : 3)
            Text(isPlaylist ? "播放列表" : (tracks.first.map { $0.albumArtist.isEmpty ? $0.artist : $0.albumArtist } ?? ""))
                .font(sizeClass == .regular ? .title2 : .subheadline).foregroundStyle(.secondary)
            if !isPlaylist, let first = tracks.first {
                Text([first.genre, (first.year ?? 0) > 0 ? String(first.year!) : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
struct MacTrackRow: View {
    @EnvironmentObject var remote: RemoteClient
    @Environment(\.horizontalSizeClass) private var sizeClass
    let track: RemoteTrack
    var showArtwork = true
    var showArtist = true
    var showAlbum = true
    var showDuration = false
    var showRating = false
    var playbackContext: [RemoteTrack]? = nil
    var body: some View {
        Button { remote.play(track, in: playbackContext) } label: {
            GeometryReader { geometry in
                let wide = sizeClass == .regular
                let metadataWidth = geometry.size.width * (wide ? 0.48 : 0.44)
                HStack(spacing: 10) {
                    if showArtwork { MacArtwork(id: track.id, size: 36) }
                    Text(track.title).font(.system(size: 16)).foregroundStyle(.primary).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if showArtist || showAlbum {
                        if wide {
                            HStack(spacing: 16) {
                                if showArtist { Text(track.artist).frame(maxWidth: .infinity, alignment: .leading) }
                                if showAlbum { Text(track.album).frame(maxWidth: .infinity, alignment: .leading) }
                            }.frame(width: metadataWidth)
                                .font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
                        } else {
                            Text([showArtist ? track.artist : "", showAlbum ? track.album : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                                .frame(width: metadataWidth, alignment: .leading)
                        }
                    }
                    if showRating, let rating = track.rating {
                        Text(rating == 0 ? "—" : String(repeating: "★", count: max(0, min(5, rating / 20))))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if showDuration {
                        Text(String(format: "%d:%02d", Int(track.duration) / 60, Int(track.duration) % 60))
                            .font(.system(size: 13).monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
                    }
                    if remote.playback.trackID == track.id {
                        Image(systemName: "waveform").font(.caption).foregroundStyle(Color.accentColor)
                    }
                }.frame(width: geometry.size.width, height: 46, alignment: .leading).contentShape(Rectangle())
            }.frame(height: 46)
        }.buttonStyle(.plain).disabled(!remote.connected)
    }
}

struct MacPlaylistView: View {
    @EnvironmentObject var remote: RemoteClient
    let playlist: RemotePlaylist
    var body: some View {
        TrackCollectionView(title: playlist.name, tracks: remote.playlistTracks[playlist.id] ?? [], isPlaylist: true, loading: !remote.completedPlaylists.contains(playlist.id))
            .task { remote.loadPlaylist(playlist.id) }
    }
}
struct PlayerView: View {
    @EnvironmentObject var remote: RemoteClient
    @Environment(\.dismiss) private var dismiss
    @State private var position = 0.0
    @State private var volume = 50.0
    @State private var seeking = false
    @State private var changingVolume = false
    @State private var showRoutes = false
    @State private var backgroundImage: UIImage?
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > 700 && geometry.size.width > geometry.size.height
            ZStack {
                background
                if wide {
                    HStack(spacing: 70) {
                        cover(size: min(geometry.size.width * 0.43, geometry.size.height - 100))
                        controls.frame(maxWidth: 430)
                    }.padding(50).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        Spacer(minLength: 24)
                        cover(size: min(geometry.size.width - 64, geometry.size.height * 0.48, 520))
                        Spacer(minLength: 24)
                        controls.frame(maxWidth: 520)
                        Spacer(minLength: 20)
                    }.padding(.horizontal, 32).padding(.vertical, 20).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay(alignment: .top) {
                Capsule().fill(.white.opacity(0.35)).frame(width: 36, height: 5).padding(.top, 10)
                    .accessibilityLabel("向下轻扫收起播放器")
            }
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 35).onEnded { gesture in
                if gesture.translation.height > 100 && abs(gesture.translation.width) < gesture.translation.height / 2 { dismiss() }
            })
            .accessibilityAction(.escape) { dismiss() }
            .sheet(isPresented: $showRoutes) { AudioOutputView().presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
            .onReceive(remote.$playback) { state in
                if !seeking { position = min(max(state.position, 0), max(state.duration, 1)) }
                if !changingVolume { volume = state.volume }
            }
        }.preferredColorScheme(.dark)
    }
    private var background: some View {
        GeometryReader { geometry in
            ZStack {
                Color(white: 0.12)
                if let backgroundImage {
                    Image(uiImage: backgroundImage).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: 90).opacity(0.55)
                }
                LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
            }.clipped()
        }.ignoresSafeArea().task(id: "\(remote.cacheEpoch):\(remote.playback.trackID ?? ""):\(remote.artwork[remote.playback.trackID ?? ""]?.count ?? -1)") {
            guard let id = remote.playback.trackID else { backgroundImage = nil; return }
            guard let data = remote.artwork[id] else { return }
            guard !data.isEmpty else { backgroundImage = nil; return }
            let image = await ArtworkImages.decode(data, key: "\(remote.cacheEpoch):\(id):\(data.count):background", pixels: 384)
            guard !Task.isCancelled else { return }
            backgroundImage = image
        }
    }
    private func cover(size: CGFloat) -> some View {
        MacArtwork(id: remote.playback.trackID, size: max(size, 120), retainPreviousImage: true)
            .shadow(color: .black.opacity(0.35), radius: 24, y: 16)
    }
    private var controls: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text(remote.playback.title).font(.title2.bold()).lineLimit(2)
                Text(remote.playback.artist).font(.title3).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 1) {
                MusicSlider(value: $position, range: 0...max(remote.playback.duration, 1)) { editing in
                    seeking = editing; if !editing { remote.command("seek", value: position) }
                }.accessibilityLabel("播放进度").disabled(!remote.connected)
                HStack { Text(time(position)); Spacer(); Text("−" + time(max(remote.playback.duration - position, 0))) }
                    .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
            }
            HStack {
                Spacer()
                Button { remote.command("previous") } label: { Image(systemName: "backward.fill").font(.system(size: 30)).frame(width: 64, height: 64) }.accessibilityLabel("上一首")
                Spacer()
                Button { remote.command(remote.playback.playing ? "pause" : "play") } label: {
                    Image(systemName: remote.playback.playing ? "pause.fill" : "play.fill").font(.system(size: 46)).frame(width: 72, height: 72)
                }.accessibilityLabel(remote.playback.playing ? "暂停" : "播放")
                Spacer()
                Button { remote.command("next") } label: { Image(systemName: "forward.fill").font(.system(size: 30)).frame(width: 64, height: 64) }.accessibilityLabel("下一首")
                Spacer()
            }.buttonStyle(.plain).disabled(!remote.connected)
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill").font(.caption)
                MusicSlider(value: $volume, range: 0...100) { editing in
                    changingVolume = editing; if !editing { remote.command("volume", value: volume) }
                }.accessibilityLabel("播放音量").disabled(!remote.connected)
                Image(systemName: "speaker.wave.3.fill").font(.caption)
            }.foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 36) {
                Button { remote.command("shuffle", value: remote.playback.shuffle == true ? 0 : 1) } label: {
                    Image(systemName: "shuffle").frame(width: 44, height: 44)
                        .background(remote.playback.shuffle == true ? .white.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 10))
                }.accessibilityLabel("随机播放").accessibilityValue(remote.playback.shuffle == true ? "开启" : "关闭")
                Button { showRoutes = true } label: { Image(systemName: "airplay.audio").frame(width: 44, height: 44) }
                    .accessibilityLabel("AirPlay 与音频输出")
                Button { remote.command("repeat", value: Double(((remote.playback.repeatMode ?? 0) + 1) % 3)) } label: {
                    Image(systemName: remote.playback.repeatMode == 2 ? "repeat.1" : "repeat").frame(width: 44, height: 44)
                        .background((remote.playback.repeatMode ?? 0) > 0 ? .white.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 10))
                }.accessibilityLabel("循环播放").accessibilityValue(remote.playback.repeatMode == 2 ? "单曲循环" : remote.playback.repeatMode == 1 ? "全部循环" : "关闭")
            }.font(.system(size: 19)).buttonStyle(.plain).disabled(!remote.connected)
        }.foregroundStyle(.white).tint(.white.opacity(0.7))
    }
    private func time(_ value: Double) -> String { let n = max(0, Int(value)); return String(format: "%d:%02d", n / 60, n % 60) }
}
struct MusicSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onEditingChanged: (Bool) -> Void
    @State private var dragging = false
    var body: some View {
        GeometryReader { geometry in
            let fraction = min(max((value - range.lowerBound) / max(range.upperBound - range.lowerBound, 1), 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18)).frame(height: dragging ? 8 : 4)
                Capsule().fill(.white.opacity(0.65)).frame(width: max(4, geometry.size.width * fraction), height: dragging ? 8 : 4)
                if dragging {
                    Circle().fill(.white).frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                        .offset(x: min(max(geometry.size.width * fraction - 9, 0), max(geometry.size.width - 18, 0)))
                }
            }.frame(height: 30).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                    if !dragging { dragging = true; onEditingChanged(true) }
                    value = range.lowerBound + min(max(gesture.location.x / max(geometry.size.width, 1), 0), 1) * (range.upperBound - range.lowerBound)
                }.onEnded { _ in dragging = false; onEditingChanged(false) })
        }.frame(height: 30)
            .accessibilityElement().accessibilityValue("\(Int(value))")
            .accessibilityAdjustableAction { direction in
                onEditingChanged(true)
                let step = (range.upperBound - range.lowerBound) / 20
                switch direction {
                case .increment: value = min(range.upperBound, value + step)
                case .decrement: value = max(range.lowerBound, value - step)
                @unknown default: break
                }
                onEditingChanged(false)
            }
    }
}
struct AudioOutputView: View {
    @EnvironmentObject var remote: RemoteClient
    var body: some View {
        NavigationStack {
            List {
                Section("AirPlay") {
                    ForEach(remote.routes.filter { !$0.isSystem }) { route in routeRow(route) }
                    if remote.routes.allSatisfy({ $0.isSystem }) { Text("没有发现可用的 AirPlay 扬声器").foregroundStyle(.secondary) }
                }
                Section {
                    ForEach(remote.routes.filter(\.isSystem)) { route in routeRow(route) }
                } header: { Text("本机音频输出") } footer: { Text("选择内置扬声器或显示器时，会同时更改 Mac 的系统音频输出。") }
                if !remote.routeMessage.isEmpty { Text(remote.routeMessage).font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("AirPlay").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("刷新") { remote.loadRoutes() } } }
                .task { remote.loadRoutes() }
        }
    }
    private func routeRow(_ route: AudioRoute) -> some View {
        Button { remote.selectRoute(route.id) } label: {
            HStack(spacing: 14) {
                Image(systemName: route.isSystem ? "speaker.wave.2.fill" : route.kind == "HomePod" ? "homepod.fill" : "airplay.audio").frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.name)
                    if !route.available { Text("不可用").font(.caption).foregroundStyle(.secondary) }
                    else if route.requiresPassword { Text("首次连接可能需要在 Mac 验证").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if remote.selectingRouteID == route.id { ProgressView() }
                else if route.selected { Image(systemName: "checkmark.circle.fill") }
            }.padding(.vertical, 8).frame(maxWidth: .infinity).contentShape(Rectangle())
        }.disabled(!route.available || !remote.connected || remote.selectingRouteID != nil).buttonStyle(.plain)
    }
}
struct MacArtwork: View {
    @EnvironmentObject var remote: RemoteClient
    let id: String?
    let size: CGFloat
    var retainPreviousImage = false
    @Environment(\.displayScale) private var displayScale
    @State private var decodedEpoch = -1
    @State private var decoded: UIImage?
    @State private var decodedNamespace = ""
    private var pixels: Int { [128, 384, 768, 1536, 2048].first { CGFloat($0) >= size * displayScale } ?? 2048 }
    private var imageKey: String { "\(remote.cacheEpoch):\(id ?? ""):\(remote.artwork[id ?? ""]?.count ?? -1):\(pixels)" }
    var body: some View {
        Group {
            if let decoded { Image(uiImage: decoded).resizable().scaledToFill() }
            else { Image(systemName: "music.note").resizable().scaledToFit().padding(size * 0.25).foregroundStyle(.pink).background(.quaternary) }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: min(size * 0.025, 14)))
            .task(id: "\(remote.cacheEpoch):\(remote.connected):\(id ?? "")") { if let id { remote.loadArtwork(id) } }
            .task(id: imageKey) {
                let namespace = "\(remote.cacheEpoch):\(id ?? "")"
                if decodedNamespace != namespace {
                    if !retainPreviousImage || decodedEpoch != remote.cacheEpoch || id == nil { decoded = nil }
                    decodedNamespace = namespace; decodedEpoch = remote.cacheEpoch
                }
                // Evicting compressed bytes must not blank a still-visible image.
                guard let data = remote.artwork[id ?? ""] else { return }
                guard !data.isEmpty else { decoded = nil; return }
                let key = imageKey
                let image = await ArtworkImages.decode(data, key: key, pixels: pixels)
                guard !Task.isCancelled else { return }
                decoded = image
            }
    }
}
