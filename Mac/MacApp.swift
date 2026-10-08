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
    init() {
        DispatchQueue.main.async { [weak self] in self?.start() }
    }
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
                if request.action == "cacheInfo" {
                    reply.cacheInfo = try self.music.cacheInfo()
                } else if request.action == "library" {
                    if request.refresh == true && (request.offset ?? 0) == 0 && request.playlistID == nil {
                        _ = try self.music.cacheInfo()
                        self.music.refreshCache(clearArtwork: request.clearArtwork == true)
                    }
                    let page = try self.music.library(offset: request.offset ?? 0, playlistID: request.playlistID)
                    reply.tracks = page.0; reply.hasMore = page.1; reply.playlistID = request.playlistID
                    reply.cacheInfo = self.music.currentCacheInfo
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
        MenuBarExtra("音乐遥控", systemImage: "play.circle") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("音乐遥控").font(.headline)
                    Spacer()
                    Circle().fill(model.running ? Color.green : Color.secondary).frame(width: 8, height: 8)
                }
                Text(model.message).font(.callout).textSelection(.enabled)
                if model.running {
                    Text("同一 Wi-Fi 下可直接连接 iPhone 和 iPad。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(model.connectionHint).font(.caption.monospaced()).textSelection(.enabled)
                }
                if !model.playback.title.isEmpty {
                    Divider()
                    Text(model.playback.title).font(.headline).lineLimit(2)
                    Text(model.playback.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Divider()
                HStack {
                    Button(model.running ? "停止共享" : "开启共享") {
                        if model.running { model.stop() } else { model.start() }
                    }.buttonStyle(.borderedProminent)
                    Spacer()
                    Button("退出") {
                        model.stop()
                        NSApplication.shared.terminate(nil)
                    }.keyboardShortcut("q")
                }
                Text("请允许自动化控制 Mac 的“音乐”应用。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(18).frame(width: 340)
                .environment(\.locale, Locale(identifier: "zh_Hans"))
        }.menuBarExtraStyle(.window)
    }
}
