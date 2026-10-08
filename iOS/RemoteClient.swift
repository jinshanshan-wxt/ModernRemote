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
    @Published var macTracks: [RemoteTrack] = []
    @Published var hasMore = true
    @Published var artwork: [String: Data] = [:]
    @Published var routes: [AudioRoute] = []
    @Published var routeMessage = ""
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
    private var deferred: [Packet] = []
    private var timeout: DispatchWorkItem?
    private var timer: AnyCancellable?
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
        macTracks = []; playlists = []; playlistTracks = [:]; completedPlaylists = []; artwork = [:]; requestedArtwork = []; hasMore = true
        message = "正在连接 Mac……"
        let peer = Wire(NWConnection(to: endpoint, using: SecureLAN.parameters()))
        wire = peer
        peer.onReady = { [weak self] in
            guard let self else { return }
            self.macName = name; self.connecting = false; self.connected = true; self.message = "已连接到 \(name)"
            self.reloadLibrary()
            self.timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                guard let self, !self.busy else { return }
                self.send(Packet(action: "status"))
            }
        }
        peer.onClose = { [weak self] reason in
            guard let self else { return }
            self.connecting = false; self.connected = false; self.loadingLibrary = false; self.busy = false; self.pending = nil
            self.timeout?.cancel(); self.timer = nil; self.message = reason
            self.wire = nil; self.deferred = []
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.autoConnect() }
        }
        peer.onPacket = { [weak self] packet in
            guard let self, packet.id == self.pending else { return }
            let requestAction = self.pendingAction
            self.timeout?.cancel(); self.pending = nil; self.pendingAction = nil; self.busy = false
            if let error = packet.error { self.message = error }
            if let playback = packet.playback {
                self.playback = playback
                if let id = playback.trackID { self.loadArtwork(id) }
            }
            if let id = packet.artworkID, let data = packet.artwork { self.artwork[id] = data }
            if let routes = packet.routes { self.routes = routes; self.routeMessage = "" }
            if let error = packet.error, requestAction == "routes" || requestAction == "route" { self.routeMessage = error }
            if let lists = packet.playlists {
                self.playlists = lists
            }
            if let tracks = packet.tracks {
                if let id = packet.playlistID {
                    self.playlistTracks[id, default: []].append(contentsOf: tracks)
                    if packet.hasMore == false { self.completedPlaylists.insert(id) }
                    if packet.hasMore == true { self.deferred.append(Packet(action: "library", offset: self.playlistTracks[id]?.count ?? 0, playlistID: id)) }
                } else {
                    self.macTracks.append(contentsOf: tracks); self.hasMore = packet.hasMore ?? false
                    self.loadingLibrary = self.hasMore
                    if self.hasMore { self.deferred.append(Packet(action: "library", offset: self.macTracks.count)) }
                }
            }
            if packet.error != nil { self.loadingLibrary = false }
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
        macTracks = []; playlistTracks = [:]; completedPlaylists = []; artwork = [:]; requestedArtwork = []; hasMore = true; loadingLibrary = true
        send(Packet(action: "library", offset: 0))
        send(Packet(action: "playlists"))
        deferred.append(Packet(action: "status"))
    }
    func loadPlaylist(_ id: String) {
        guard playlistTracks[id] == nil else { return }
        playlistTracks[id] = []
        send(Packet(action: "library", offset: 0, playlistID: id))
    }
    func loadRoutes() { routeMessage = "正在寻找音频输出……"; send(Packet(action: "routes")) }
    func selectRoute(_ id: String) { routeMessage = "正在切换……"; send(Packet(action: "route", routeID: id)) }
    func loadArtwork(_ id: String) {
        guard connected, !requestedArtwork.contains(id) else { return }
        requestedArtwork.insert(id)
        send(Packet(action: "artwork", artworkID: id))
    }
    func playQueue(_ tracks: [RemoteTrack]) { send(Packet(action: "queue", tracks: tracks)) }
    func send(_ packet: Packet) {
        guard connected else { return }
        if busy { if packet.action != "status" { deferred.append(packet) }; return }
        busy = true; pending = packet.id; pendingAction = packet.action
        let deadline = DispatchWorkItem { [weak self] in self?.wire?.close("Mac 未响应。请检查“音乐”应用与自动化权限，然后重新连接。") }
        timeout = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + (packet.action == "queue" ? 120 : 30), execute: deadline)
        wire?.send(packet)
    }
    func command(_ action: String, value: Double? = nil) { send(Packet(action: action, value: value)) }
    func play(_ track: RemoteTrack) { send(Packet(action: "track", track: track)) }
    func loadMacPage() { send(Packet(action: "library", offset: macTracks.count)) }
    func disconnect() {
        wantsConnection = false; connecting = false
        timer = nil; timeout?.cancel(); wire?.close(); wire = nil
        connected = false; busy = false; pending = nil; deferred = []
    }
}
