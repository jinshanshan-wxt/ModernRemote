import SwiftUI
import Network

@main struct ModernRemoteApp: App {
    @StateObject private var remote = RemoteClient()
    var body: some Scene {
        WindowGroup {
            AdaptiveRemoteView().tint(.pink).environmentObject(remote)
                .environment(\.locale, Locale(identifier: "zh_Hans"))
        }
    }
}

struct AdaptiveRemoteView: View {
    @EnvironmentObject var remote: RemoteClient
    @State private var selection = 0
    @State private var showPlayer = false
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                tabs.tabViewBottomAccessory { MiniPlayer { showPlayer = true } }
            } else {
                tabs
            }
        }
        .environment(\.horizontalSizeClass, .compact)
        .sheet(isPresented: $showPlayer) {
            PlayerView().presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .task { remote.discover() }
    }
    private var tabs: some View {
        TabView(selection: $selection) {
            tab("Artists").tabItem { Label("艺人", systemImage: "person.fill") }.tag(0)
            tab("Albums").tabItem { Label("专辑", systemImage: "square.stack.fill") }.tag(1)
            tab("Songs").tabItem { Label("歌曲", systemImage: "music.note") }.tag(2)
            tab("Genres").tabItem { Label("类型", systemImage: "guitars.fill") }.tag(3)
            NavigationStack { MoreView() }.modifier(LegacyPlayerInset(showPlayer: { showPlayer = true }))
                .tabItem { Label("更多", systemImage: "ellipsis") }.tag(4)
        }
    }
    private func tab(_ category: String) -> some View {
        NavigationStack { LibraryView(category: category) }
            .modifier(LegacyPlayerInset(showPlayer: { showPlayer = true }))
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
                    MacArtwork(id: remote.playback.trackID, size: 40)
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
    var body: some View {
        List {
            NavigationLink { LibraryView(category: "Playlists") } label: { Label("播放列表", systemImage: "music.note.list") }
            NavigationLink { LibraryView(category: "Recent") } label: { Label("最近添加", systemImage: "clock") }
            Section {
                NavigationLink { SettingsView() } label: { Label("设置", systemImage: "gearshape") }
            }
        }.navigationTitle("更多")
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
            Section("状态") { Text(remote.message).textSelection(.enabled) }
            Section("关于") {
                LabeledContent("音乐遥控", value: "0.3.0")
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
                Text("地址和端口见 Mac 端窗口。").font(.footnote).foregroundStyle(.secondary)
            }
            if remote.connected { Button("断开连接", role: .destructive) { remote.disconnect() } }
        }.navigationTitle("连接设置")
    }
}

struct LibraryView: View {
    @EnvironmentObject var remote: RemoteClient
    let category: String
    @State private var search = ""
    @State private var descending = false
    private var title: String {
        ["Recent": "最近添加", "Songs": "歌曲", "Albums": "专辑", "Artists": "艺人", "Playlists": "播放列表", "Genres": "类型"][category] ?? category
    }
    private var songs: [RemoteTrack] {
        remote.macTracks.filter { search.isEmpty || "\($0.title) \($0.artist) \($0.album) \($0.genre)".localizedCaseInsensitiveContains(search) }
            .sorted {
                if category == "Recent" { return descending ? $0.dateAdded < $1.dateAdded : $0.dateAdded > $1.dateAdded }
                return descending ? $0.title.localizedStandardCompare($1.title) == .orderedDescending : $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }
    private var groups: [(String, [RemoteTrack])] {
        Dictionary(grouping: songs) { t in
            switch category {
            case "Artists": return t.artist.isEmpty ? "未知艺人" : t.artist
            case "Genres": return t.genre.isEmpty ? "未分类" : t.genre
            default: return albumKey(t)
            }
        }.map { ($0.key, $0.value) }.sorted {
            descending ? $0.0.localizedStandardCompare($1.0) == .orderedDescending : $0.0.localizedStandardCompare($1.0) == .orderedAscending
        }
    }
    var body: some View {
        Group {
            if category == "Albums" {
                ScrollView {
                    loading
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 18)], spacing: 24) {
                        ForEach(groups, id: \.0) { group in
                            NavigationLink { TrackCollectionView(title: group.0, tracks: group.1) } label: {
                                AlbumTile(tracks: group.1)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 20).padding(.bottom, 20)
                }
            } else {
                List {
                    if remote.loadingLibrary || !remote.connected { loading.listRowSeparator(.hidden) }
                    if category == "Songs" || category == "Recent" {
                        ForEach(songs) { MacTrackRow(track: $0) }
                    } else if category == "Playlists" {
                        ForEach(remote.playlists.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }.sorted { descending ? $0.name > $1.name : $0.name < $1.name }) { list in
                            NavigationLink { MacPlaylistView(playlist: list) } label: { Label(list.name, systemImage: "music.note.list").padding(.vertical, 10) }
                        }
                    } else {
                        ForEach(groups, id: \.0) { group in
                            NavigationLink {
                                if category == "Artists" { ArtistAlbumsView(name: group.0, tracks: group.1) }
                                else { TrackCollectionView(title: group.0, tracks: group.1) }
                            } label: {
                                HStack(spacing: 14) {
                                    if let first = group.1.first {
                                        MacArtwork(id: first.id, size: 56).clipShape(RoundedRectangle(cornerRadius: category == "Artists" ? 28 : 8))
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(group.0).font(.body)
                                        Text("\(group.1.count) 首歌曲").font(.caption).foregroundStyle(.secondary)
                                    }
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                }.listStyle(.plain)
            }
        }.navigationTitle(title)
            .searchable(text: $search, prompt: remote.loadingLibrary ? "搜索已加载的 Mac 音乐" : "搜索 Mac 资料库")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { descending = false } label: { Label(category == "Recent" ? "最新添加优先" : "名称升序", systemImage: descending ? "arrow.up" : "checkmark") }
                        Button { descending = true } label: { Label(category == "Recent" ? "最早添加优先" : "名称降序", systemImage: descending ? "checkmark" : "arrow.down") }
                    } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel("排列顺序")
                }
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
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in MacArtwork(id: tracks.first?.id, size: geometry.size.width) }.aspectRatio(1, contentMode: .fit)
            Text(tracks.first?.album ?? "未知专辑").font(.subheadline).lineLimit(1)
            Text(tracks.first.map { $0.albumArtist.isEmpty ? $0.artist : $0.albumArtist } ?? "")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
struct TrackCollectionView: View {
    @EnvironmentObject var remote: RemoteClient
    let title: String
    let tracks: [RemoteTrack]
    private var sorted: [RemoteTrack] { tracks.sorted { $0.album == $1.album ? $0.trackNumber < $1.trackNumber : $0.album < $1.album } }
    var body: some View {
        List {
            Section {
                HStack { Spacer(); MacArtwork(id: tracks.first?.id, size: 200); Spacer() }.listRowSeparator(.hidden)
                Button { remote.playQueue(sorted) } label: { Label("按顺序播放", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).disabled(!remote.connected || sorted.isEmpty)
            } footer: { Text("将在 Mac 新建遥控播放列表，连续播放这些歌曲。") }
            ForEach(sorted) { MacTrackRow(track: $0) }
        }.listStyle(.plain).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}
struct MacTrackRow: View {
    @EnvironmentObject var remote: RemoteClient
    let track: RemoteTrack
    var body: some View {
        Button { remote.play(track) } label: {
            HStack(spacing: 12) {
                MacArtwork(id: track.id, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).foregroundStyle(.primary).lineLimit(1)
                    Text("\(track.artist) · \(track.album)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if remote.playback.trackID == track.id { Image(systemName: "waveform").foregroundStyle(.pink) }
            }.padding(.vertical, 3).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!remote.connected)
    }
}
struct MacPlaylistView: View {
    @EnvironmentObject var remote: RemoteClient
    let playlist: RemotePlaylist
    var body: some View {
        List {
            Section {
                Button { remote.playQueue(remote.playlistTracks[playlist.id] ?? []) } label: { Label("按顺序播放", systemImage: "play.fill") }
                    .disabled(!remote.completedPlaylists.contains(playlist.id) || (remote.playlistTracks[playlist.id] ?? []).isEmpty)
            } footer: { Text("将在 Mac 新建遥控播放列表，按原列表顺序连续播放。") }
            if !remote.completedPlaylists.contains(playlist.id) { ProgressView("正在读取播放列表 · \(remote.playlistTracks[playlist.id]?.count ?? 0) 首") }
            ForEach(Array((remote.playlistTracks[playlist.id] ?? []).enumerated()), id: \.offset) { item in MacTrackRow(track: item.element) }
        }.listStyle(.plain).navigationTitle(playlist.name).task { remote.loadPlaylist(playlist.id) }
    }
}
struct PlayerView: View {
    @EnvironmentObject var remote: RemoteClient
    @Environment(\.dismiss) private var dismiss
    @State private var position = 0.0
    @State private var volume = 50.0
    @State private var seeking = false
    @State private var changingVolume = false
    @State private var showQueue = false
    var body: some View {
        GeometryReader { geometry in
            let coverSize = min(max(geometry.size.width - 64, 160), 380)
            ScrollView {
                VStack(spacing: 28) {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "chevron.down").font(.headline).frame(width: 36, height: 36) }.accessibilityLabel("收起播放器")
                        Spacer()
                        Text(remote.macName.isEmpty ? "在 Mac 上播放" : remote.macName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer(); Image(systemName: "desktopcomputer").frame(width: 36)
                    }
                    MacArtwork(id: remote.playback.trackID, size: coverSize)
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 12).padding(.vertical, 10)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(remote.playback.title).font(.title2.bold()).lineLimit(2)
                        Text(remote.playback.artist).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 2) {
                        Slider(value: $position, in: 0...max(remote.playback.duration, 1)) { editing in
                            seeking = editing; if !editing { remote.command("seek", value: position) }
                        }.accessibilityLabel("播放进度")
                        HStack { Text(time(position)); Spacer(); Text("−" + time(max(remote.playback.duration - position, 0))) }
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack {
                        Spacer()
                        Button { remote.command("previous") } label: { Image(systemName: "backward.fill").font(.system(size: 30)).frame(width: 60, height: 64) }.accessibilityLabel("上一首")
                        Spacer()
                        Button { remote.command(remote.playback.playing ? "pause" : "play") } label: {
                            Image(systemName: remote.playback.playing ? "pause.fill" : "play.fill").font(.system(size: 46)).frame(width: 72, height: 72)
                        }.accessibilityLabel(remote.playback.playing ? "暂停" : "播放")
                        Spacer()
                        Button { remote.command("next") } label: { Image(systemName: "forward.fill").font(.system(size: 30)).frame(width: 60, height: 64) }.accessibilityLabel("下一首")
                        Spacer()
                    }.buttonStyle(.plain)
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.fill")
                        Slider(value: $volume, in: 0...100) { editing in
                            changingVolume = editing; if !editing { remote.command("volume", value: volume) }
                        }.accessibilityLabel("Mac 音量")
                        Image(systemName: "speaker.wave.3.fill")
                    }.foregroundStyle(.secondary)
                    HStack {
                        Label("Mac 播放", systemImage: "hifispeaker.fill").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button { withAnimation { showQueue.toggle() } } label: { Image(systemName: "list.bullet").font(.title2).padding(10).background(showQueue ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10)) }
                            .accessibilityLabel("接下来播放")
                    }
                    if showQueue {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("接下来播放").font(.title3.bold())
                            if let queue = remote.upcoming {
                                Text("遥控播放列表的后续歌曲，不包含 Mac 手动插入的待播项目。").font(.caption).foregroundStyle(.secondary)
                                ForEach(Array(queue.enumerated()), id: \.offset) { MacTrackRow(track: $0.element) }
                            } else {
                                Text("Mac 原有的完整待播队列无法读取。使用专辑或播放列表中的“按顺序播放”后，可查看遥控播放列表的后续歌曲；随机播放时不显示预测顺序。")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 32).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }.background(Color(uiColor: .secondarySystemBackground)).tint(.primary)
                .onReceive(remote.$playback) { state in
                    if !seeking { position = min(max(state.position, 0), max(state.duration, 1)) }
                    if !changingVolume { volume = state.volume }
                }
        }
    }
    private func time(_ value: Double) -> String { let n = max(0, Int(value)); return String(format: "%d:%02d", n / 60, n % 60) }
}
struct MacArtwork: View {
    @EnvironmentObject var remote: RemoteClient
    let id: String?
    let size: CGFloat
    var body: some View {
        Group {
            if let id, let data = remote.artwork[id], let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else { Image(systemName: "music.note").resizable().scaledToFit().padding(size * 0.25).foregroundStyle(.pink).background(.quaternary) }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.1))
            .task(id: id) { if let id { remote.loadArtwork(id) } }
    }
}
