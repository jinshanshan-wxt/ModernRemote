import Foundation
import Network
import Combine

final class RemoteClient: ObservableObject {
    @Published var devices: [NWBrowser.Result] = []
    @Published var macName = ""
    @Published var connected = false
    @Published var busy = false
    @Published var message = "请选择同一局域网中的 Mac。"
    @Published var playback = Playback()
    @Published private(set) var libraryGeneration = 0
    @Published var macTracks: [RemoteTrack] = [] { didSet { libraryGeneration += 1 } }
    @Published var hasMore = true
    @Published var artwork: [String: Data] = [:]
    @Published var routes: [AudioRoute] = []
    @Published var routeMessage = ""
    @Published var selectingRouteID: String? = nil
    private var incomingArtwork: [String: ArtworkAssembly] = [:]
    private var activePlaybackIDs: [String] = []
    private var pendingEmptyPlayback: DispatchWorkItem?
    private var requestedArtwork: Set<String> = []
    @Published var playlists: [RemotePlaylist] = []
    @Published var playlistTracks: [String: [RemoteTrack]] = [:]
    @Published var completedPlaylists: Set<String> = []
    @Published var loadingLibrary = false
    private var wantsConnection = true
    private var connecting = false
    private var browser: NWBrowser?
    private var wire: Wire?
    private var pendingAction: String?
    private var pending: String?
    private var deferred = RequestQueue()
    private var timeout: DispatchWorkItem?
    private var timer: AnyCancellable?
    @Published var cacheUpdatedAt: Double?
    private var disk: LibraryDiskCache?
    private var cacheID = ""
    private var cacheRevision: String?
    private var incomingTracks: [RemoteTrack] = []
    private var rebuildingLibrary = false
    @Published private(set) var cacheEpoch = 0
    private var lastCacheCheck = Date.distantPast
    init() {
        if let id = UserDefaults.standard.string(forKey: "cache.lastServerID") {
            selectCache(id)
            macName = UserDefaults.standard.string(forKey: "cache.lastHost") ?? ""
        }
    }
    private func selectCache(_ id: String) {
        if id != cacheID {
            incomingArtwork = [:]; pendingEmptyPlayback?.cancel(); pendingEmptyPlayback = nil; cacheEpoch += 1; cacheID = id; disk = LibraryDiskCache(namespace: "ios:" + id)
            artwork = [:]; requestedArtwork = []; macTracks = []; playlists = []; playlistTracks = [:]; completedPlaylists = []
            cacheRevision = nil; cacheUpdatedAt = nil
            if let value = disk?.snapshot() {
                macTracks = value.tracks; playlists = value.playlists; playlistTracks = value.playlistTracks
                completedPlaylists = Set(value.playlistTracks.keys); cacheRevision = value.revision; cacheUpdatedAt = value.updatedAt; hasMore = false
            }
        }
        UserDefaults.standard.set(id, forKey: "cache.lastServerID")
    }
    private func saveCache() {
        guard !rebuildingLibrary, let revision = cacheRevision, let date = cacheUpdatedAt else { return }
        let completeLists = playlistTracks.filter { completedPlaylists.contains($0.key) }
        disk?.save(LibrarySnapshot(revision: revision, updatedAt: date, tracks: macTracks,
            playlists: playlists, playlistTracks: completeLists))
    }
    private func rememberArtwork(_ data: Data, id: String) {
        while artwork.values.reduce(0, { $0 + $1.count }) + data.count > 64 * 1024 * 1024,
              let old = artwork.keys.first(where: { $0 != playback.trackID && $0 != id }) { artwork[old] = nil }
        if artwork.count >= 300, let old = artwork.keys.first(where: { $0 != playback.trackID }) { artwork[old] = nil }
        artwork[id] = data
    }
    func discover(restart: Bool = false) {
        if restart {
            browser?.stateUpdateHandler = nil
            browser?.browseResultsChangedHandler = nil
            browser?.cancel(); browser = nil; devices = []
        }
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: SecureLAN.service, domain: "local."), using: .tcp)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            self.devices = results.sorted { Self.name($0) < Self.name($1) }
            self.autoConnect()
        }
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .waiting(let error): self?.message = "局域网搜索暂不可用：\(error.localizedDescription)。请检查本地网络权限，或使用手动连接。"
            case .failed(let error): self?.message = error.localizedDescription; self?.browser?.cancel(); self?.browser = nil
            default: break
            }
        }
        browser.start(queue: .main)
    }
    static func name(_ result: NWBrowser.Result) -> String {
        if case .service(let name, _, _, _) = result.endpoint { return name }
        return "Mac"
    }
    func connect(_ device: NWBrowser.Result) {
        UserDefaults.standard.set(Self.name(device), forKey: "preferredMac")
        connect(endpoint: device.endpoint, name: Self.name(device))
    }
    func connect(host: String, port: String) {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, let number = UInt16(port), number > 0, let port = NWEndpoint.Port(rawValue: number) else {
            message = "请输入有效的 Mac 地址和端口。"; return
        }
        connect(endpoint: .hostPort(host: NWEndpoint.Host(host), port: port), name: host)
    }
    private func connect(endpoint: NWEndpoint, name: String) {
        disconnect()
        wantsConnection = true; connecting = true
        rebuildingLibrary = false; incomingTracks = []; loadingLibrary = false
        let knownHosts = UserDefaults.standard.dictionary(forKey: "cache.hosts") as? [String: String] ?? [:]
        if let id = knownHosts[name] { selectCache(id) }
        else {
            incomingArtwork = [:]; pendingEmptyPlayback?.cancel(); pendingEmptyPlayback = nil; cacheEpoch += 1; disk = nil; cacheID = ""; cacheRevision = nil; cacheUpdatedAt = nil
            macTracks = []; playlists = []; playlistTracks = [:]; completedPlaylists = []; artwork = [:]; requestedArtwork = []; hasMore = true
        }
        macName = name
        message = "正在连接 Mac……"
        let peer = Wire(NWConnection(to: endpoint, using: SecureLAN.parameters()))
        wire = peer
        peer.onReady = { [weak self] in
            guard let self else { return }
            self.macName = name; self.connecting = false; self.connected = true; self.message = "已连接到 \(name)"
            self.lastCacheCheck = Date()
            self.send(Packet(action: "cacheInfo"))
            self.timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                guard let self else { return }
                self.send(Packet(action: "status"))
                if Date().timeIntervalSince(self.lastCacheCheck) >= 86400 && !self.loadingLibrary {
                    self.lastCacheCheck = Date(); self.send(Packet(action: "cacheInfo"))
                }
            }
        }
        peer.onClose = { [weak self] reason in
            guard let self else { return }
            self.selectingRouteID = nil; self.routeMessage = reason
            self.connecting = false; self.connected = false; self.loadingLibrary = false; self.busy = false; self.pending = nil
            self.timeout?.cancel(); self.timer = nil; self.message = reason
            self.wire = nil; self.deferred = RequestQueue()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.autoConnect() }
        }
        peer.onPacket = { [weak self] packet in
            guard let self, packet.id == self.pending else { return }
            let requestAction = self.pendingAction
            self.timeout?.cancel(); self.pending = nil; self.pendingAction = nil; self.busy = false
            if let error = packet.error { self.message = error }
            if requestAction == "cacheInfo" {
                if let info = packet.cacheInfo {
                    self.selectCache(info.serverID)
                    var hosts = UserDefaults.standard.dictionary(forKey: "cache.hosts") as? [String: String] ?? [:]
                    hosts[name] = info.serverID; UserDefaults.standard.set(hosts, forKey: "cache.hosts")
                    UserDefaults.standard.set(name, forKey: "cache.lastHost")
                    if self.cacheRevision == info.revision && info.revision != nil && !info.needsRefresh {
                        self.message = "已连接到 \(name) · 已读取磁盘缓存"
                        self.send(Packet(action: "status"))
                    } else {
                        self.startLibraryReload(refreshMac: info.needsRefresh, clearArtwork: false)
                    }
                } else {
                    // Old companions have no cache manifest; retain protocol compatibility.
                    self.selectCache("legacy:" + name)
                    self.cacheRevision = UUID().uuidString; self.cacheUpdatedAt = Date().timeIntervalSince1970
                    self.startLibraryReload(refreshMac: false, clearArtwork: false)
                }
            }
            if requestAction != "cacheInfo", let info = packet.cacheInfo {
                if !info.serverID.isEmpty && info.serverID != self.cacheID {
                    self.selectCache(info.serverID)
                    var hosts = UserDefaults.standard.dictionary(forKey: "cache.hosts") as? [String: String] ?? [:]
                    hosts[name] = info.serverID; UserDefaults.standard.set(hosts, forKey: "cache.hosts")
                    UserDefaults.standard.set(name, forKey: "cache.lastHost")
                }
                if let revision = info.revision { self.cacheRevision = revision; self.cacheUpdatedAt = info.updatedAt }
            }
            if let playback = packet.playback {
                self.applyPlayback(playback)
            }
            if let id = packet.artworkID {
                if packet.error == nil {
                    do {
                        var assembly = self.incomingArtwork[id] ?? ArtworkAssembly()
                        let completed = try assembly.append(packet.artwork ?? Data(), offset: packet.offset ?? 0, hasMore: packet.hasMore == true)
                        if let completed {
                            self.incomingArtwork[id] = nil; self.requestedArtwork.remove(id)
                            self.rememberArtwork(completed, id: id); self.disk?.saveArtwork(completed, id: id)
                        } else {
                            self.incomingArtwork[id] = assembly
                            self.deferred.append(Packet(action: "artwork", offset: assembly.data.count, artworkID: id))
                        }
                    } catch {
                        self.incomingArtwork[id] = nil; self.requestedArtwork.remove(id); self.message = error.localizedDescription
                    }
                } else { self.incomingArtwork[id] = nil; self.requestedArtwork.remove(id) }
            }
            if let routes = packet.routes {
                self.routes = routes
                if requestAction == "route", let selectedID = self.selectingRouteID {
                    self.routeMessage = routes.contains { $0.id == selectedID && $0.selected } ? "" : "Mac 尚未确认此输出，请刷新或重试。"
                } else if self.selectingRouteID == nil { self.routeMessage = "" }
            }
            if requestAction == "route" { self.selectingRouteID = nil }
            if let error = packet.error, requestAction == "routes" || requestAction == "route" { self.routeMessage = error }
            if let lists = packet.playlists {
                self.playlists = lists; self.saveCache()
            }
            if let tracks = packet.tracks {
                if let id = packet.playlistID {
                    self.playlistTracks[id, default: []].append(contentsOf: tracks)
                    if packet.hasMore == false { self.completedPlaylists.insert(id); self.saveCache() }
                    if packet.hasMore == true { self.deferred.append(Packet(action: "library", offset: self.playlistTracks[id]?.count ?? 0, playlistID: id)) }
                } else {
                    self.incomingTracks.append(contentsOf: tracks); self.hasMore = packet.hasMore ?? false
                    self.loadingLibrary = self.hasMore
                    if self.hasMore { self.deferred.append(Packet(action: "library", offset: self.incomingTracks.count)) }
                    else {
                        self.macTracks = self.incomingTracks; self.incomingTracks = []; self.rebuildingLibrary = false
                        self.saveCache(); self.message = "已连接到 \(name) · 资料库已缓存"
                    }
                }
            }
            if packet.error != nil && requestAction != "cacheInfo" { self.loadingLibrary = false; self.rebuildingLibrary = false }
            if !self.deferred.isEmpty {
                let next = self.deferred.removeFirst()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.send(next) }
            }
        }
        peer.start()
    }
    private func autoConnect() {
        guard wantsConnection, !connected, !connecting else { return }
        let saved = UserDefaults.standard.string(forKey: "preferredMac")
        if let device = devices.first(where: { Self.name($0) == saved }) ?? (devices.count == 1 ? devices.first : nil) {
            connect(device)
        }
    }
    func reloadLibrary() {
        guard connected, !busy else { return }
        disk?.clear(); artwork = [:]; requestedArtwork = []; incomingArtwork = [:]; pendingEmptyPlayback?.cancel(); pendingEmptyPlayback = nil; cacheEpoch += 1
        startLibraryReload(refreshMac: true, clearArtwork: true)
    }
    private func startLibraryReload(refreshMac: Bool, clearArtwork: Bool) {
        incomingTracks = []; rebuildingLibrary = true; hasMore = true; loadingLibrary = true
        playlistTracks = [:]; completedPlaylists = []
        var request = Packet(action: "library", offset: 0)
        request.refresh = refreshMac; request.clearArtwork = clearArtwork
        send(request); send(Packet(action: "playlists")); deferred.append(Packet(action: "status"))
    }
    func loadPlaylist(_ id: String) {
        guard playlistTracks[id] == nil else { return }
        playlistTracks[id] = []
        send(Packet(action: "library", offset: 0, playlistID: id))
    }
    func applyPlayback(_ state: Playback) {
        if state.trackID == nil, playback.trackID != nil {
            guard pendingEmptyPlayback == nil else { return }
            let update = DispatchWorkItem { [weak self] in
                self?.playback = state; self?.pendingEmptyPlayback = nil
            }
            pendingEmptyPlayback = update
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: update)
            return
        }
        pendingEmptyPlayback?.cancel(); pendingEmptyPlayback = nil
        playback = state
        if let id = state.trackID {
            loadArtwork(id)
            if let index = activePlaybackIDs.firstIndex(of: id), index + 1 < activePlaybackIDs.count {
                loadArtwork(activePlaybackIDs[index + 1])
            }
        }
    }
    func loadRoutes() { routeMessage = "正在寻找音频输出……"; send(Packet(action: "routes")) }
    func selectRoute(_ id: String) {
        guard connected, selectingRouteID == nil else { return }
        selectingRouteID = id; routeMessage = "正在连接音频输出……"; send(Packet(action: "route", routeID: id))
    }
    func loadArtwork(_ id: String) {
        guard artwork[id] == nil, !requestedArtwork.contains(id) else { return }
        requestedArtwork.insert(id)
        let epoch = cacheEpoch
        if let disk {
            disk.loadArtwork(id) { [weak self] data in
                DispatchQueue.main.async {
                    guard let self, self.cacheEpoch == epoch else { return }
                    if let data { self.rememberArtwork(data, id: id); self.requestedArtwork.remove(id) }
                    else if self.connected { self.send(Packet(action: "artwork", offset: 0, artworkID: id)) }
                    else { self.requestedArtwork.remove(id) }
                }
            }
        } else if connected { send(Packet(action: "artwork", offset: 0, artworkID: id)) }
        else { requestedArtwork.remove(id) }
    }
    func playQueue(_ tracks: [RemoteTrack], shuffle: Bool = false) {
        guard let first = tracks.first else { return }
        play(first, in: tracks, shuffle: shuffle)
    }
    func send(_ packet: Packet) {
        guard connected else { return }
        if busy { deferred.append(packet); return }
        busy = true; pending = packet.id; pendingAction = packet.action
        let deadline = DispatchWorkItem { [weak self] in self?.wire?.close("Mac 未响应。请检查“音乐”应用与自动化权限，然后重新连接。") }
        timeout = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + (packet.action == "queue" ? 120 : 30), execute: deadline)
        wire?.send(packet)
    }
    func command(_ action: String, value: Double? = nil) { send(Packet(action: action, value: value)) }
    func play(_ track: RemoteTrack, in context: [RemoteTrack]? = nil, shuffle: Bool = false) {
        guard let selection = PlaybackSelection(tracks: context ?? macTracks, selectedID: track.id) else {
            message = "这首歌曲不在当前播放列表中，请刷新资料库。"; return
        }
        activePlaybackIDs = selection.ids
        send(Packet(action: "queue", value: shuffle ? 1 : 0, offset: selection.start, trackIDs: selection.ids))
    }
    func loadMacPage() { send(Packet(action: "library", offset: incomingTracks.count)) }
    func disconnect() {
        incomingArtwork = [:]; pendingEmptyPlayback?.cancel(); pendingEmptyPlayback = nil; cacheEpoch += 1; requestedArtwork = []
        wantsConnection = false; connecting = false
        timer = nil; timeout?.cancel(); wire?.close(); wire = nil
        selectingRouteID = nil; routes = []; routeMessage = ""
        connected = false; busy = false; pending = nil; deferred = RequestQueue()
    }
}
