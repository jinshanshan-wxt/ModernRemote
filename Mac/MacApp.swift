import SwiftUI
import Network

final class Companion: ObservableObject {
    @Published var message = "开启共享后，即可连接 iPhone。"
    @Published var running = false
    @Published var connected = false
    @Published var playback = Playback()
    @Published var connectionHint = ""
    private var listener: NWListener?
    private var peers: [UUID: Wire] = [:]
    private let music = MusicBridge()
    func start() {
        guard listener == nil else { return }
        do {
            _ = try music.status() // Trigger Automation permission locally, before advertising.
            let listener = try NWListener(using: SecureLAN.parameters())
            self.listener = listener
            listener.service = NWListener.Service(name: Host.current().localizedName ?? "Mac", type: SecureLAN.service)
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                if case .ready = state {
                    self?.running = true; self?.message = "等待 iPhone 或 iPad 连接"
                    let addresses = (Host.current().addresses).filter { !$0.contains(":") && $0 != "127.0.0.1" }
                    self?.connectionHint = "端口：\(listener?.port?.rawValue ?? 0)\nMac 地址：\(addresses.joined(separator: "、"))\n本机模拟器地址：127.0.0.1"
                }
                if case .failed(let error) = state { self?.stop(); self?.message = error.localizedDescription }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: .main)
        } catch { message = error.localizedDescription }
    }
    private func accept(_ connection: NWConnection) {
        let id = UUID()
        let peer = Wire(connection)
        peers[id] = peer
        peer.onReady = { [weak self] in
            self?.connected = true
            self?.message = "已连接 \(self?.peers.count ?? 0) 台设备"
        }
        peer.onClose = { [weak self] _ in
            guard let self else { return }
            self.peers.removeValue(forKey: id)
            self.connected = !self.peers.isEmpty
            self.message = "已连接 \(self.peers.count) 台设备"
        }
        peer.onPacket = { [weak self, weak peer] request in
            guard let self, let peer else { return }
            var reply = Packet(id: request.id, action: "reply")
            do {
                if request.action == "library" {
                    let page = try self.music.library(offset: request.offset ?? 0, playlistID: request.playlistID)
                    reply.tracks = page.0; reply.hasMore = page.1; reply.playlistID = request.playlistID
                } else if request.action == "artwork", let id = request.artworkID {
                    reply.artworkID = id; reply.artwork = try self.music.artwork(id: id)
                } else if request.action == "routes" {
                    reply.routes = try self.music.audioRoutes()
                } else if request.action == "route", let id = request.routeID {
                    try self.music.selectAudioRoute(id)
                    reply.routes = try self.music.audioRoutes()
                    reply.playback = try self.music.status()
                } else if request.action == "playlists" {
                    reply.playlists = try self.music.playlists()
                } else {
                    if request.action != "status" { try self.music.execute(request) }
                    self.playback = try self.music.status()
                    reply.playback = self.playback
                }
            } catch { reply.error = error.localizedDescription; self.message = error.localizedDescription }
            peer.send(reply)
        }
        peer.start()
    }
    func stop() {
        let active = Array(peers.values); peers.removeAll()
        for peer in active { peer.onClose = nil; peer.close() }
        listener?.cancel(); listener = nil
        running = false; connected = false
        message = "共享已停止。"
    }
}

@main struct ModernRemoteMacApp: App {
    @StateObject private var model = Companion()
    init() {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }
    }
    var body: some Scene {
        WindowGroup("音乐遥控 · Mac") {
            VStack(alignment: .leading, spacing: 20) {
                Label("音乐遥控", systemImage: "hifispeaker.fill").font(.largeTitle.bold())
                Text("用 iPhone 选歌，让 Mac 播放。").foregroundStyle(.secondary)
                Label(model.message, systemImage: model.connected ? "desktopcomputer" : "wifi")
                    .textSelection(.enabled)
                if model.running {
                    Text("同一局域网中的 iPhone 和 iPad 可以直接连接，无需配对。")
                    Text(model.connectionHint).font(.caption.monospaced()).textSelection(.enabled)
                    Text("开启共享时，局域网内的设备均可浏览资料库和控制播放。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Text(model.playback.title).font(.title2)
                Text(model.playback.artist).foregroundStyle(.secondary)
                Button(model.running ? "停止共享" : "开启共享") {
                    if model.running { model.stop() } else { model.start() }
                }.buttonStyle(.borderedProminent)
                Text("请确认 Mac 的“音乐”应用可以正常播放。系统询问时，请允许本应用通过自动化控制“音乐”。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(30).frame(width: 520)
                .environment(\.locale, Locale(identifier: "zh_Hans"))
        }
    }
}
