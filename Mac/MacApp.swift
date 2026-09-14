import SwiftUI
import Network

final class Companion: ObservableObject {
    @Published var secret = SecureLAN.newCode()
    @Published var message = "开启共享后，即可连接 iPhone。"
    @Published var running = false
    @Published var connected = false
    @Published var playback = Playback()
    private var listener: NWListener?
    private var wire: Wire?
    private let music = MusicBridge()
    private var lastRequest = Date.distantPast
    private var pairingGate = PairingGate()
    func start() {
        guard listener == nil else { return }
        do {
            _ = try music.status() // Trigger Automation permission locally, before advertising.
            let listener = try NWListener(using: SecureLAN.parameters(secret: secret))
            self.listener = listener
            listener.service = NWListener.Service(name: Host.current().localizedName ?? "Mac", type: SecureLAN.service)
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state { self?.running = true; self?.message = "等待 iPhone 连接" }
                if case .failed(let error) = state { self?.stop(); self?.message = error.localizedDescription }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: .main)
        } catch { message = error.localizedDescription }
    }
    private func accept(_ connection: NWConnection) {
        // One controller per session. Rotate the key to revoke access.
        guard wire == nil else { connection.cancel(); return }
        guard pairingGate.allowsAttempt() else {
            message = "配对错误次数较多，请稍候一分钟再试。"
            connection.cancel()
            return
        }
        let peer = Wire(connection)
        wire = peer
        var authenticated = false
        peer.onReady = { [weak self] in
            authenticated = true
            self?.pairingGate.reset()
            self?.connected = true
            self?.message = "已与 iPhone 建立加密连接"
        }
        peer.onClose = { [weak self] reason in
            guard let self else { return }
            self.wire = nil; self.connected = false
            if !authenticated { self.pairingGate.failed() }
            self.message = self.pairingGate.lockedUntil != nil
                ? "配对错误次数较多，请稍候一分钟再试。" : reason
        }
        peer.onPacket = { [weak self, weak peer] request in
            guard let self, let peer else { return }
            guard Date().timeIntervalSince(self.lastRequest) >= 0.08 else {
                peer.send(Packet(id: request.id, action: "reply", error: "操作较快，请稍候再试。")); return
            }
            self.lastRequest = Date()
            var reply = Packet(id: request.id, action: "reply")
            do {
                if request.action == "library" {
                    let page = try self.music.library(offset: request.offset ?? 0)
                    reply.tracks = page.0; reply.hasMore = page.1
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
        wire?.onClose = nil
        wire?.close(); wire = nil
        pairingGate.reset()
        listener?.cancel(); listener = nil
        running = false; connected = false
        secret = SecureLAN.newCode(excluding: secret)
        message = "共享已停止，配对码已更新。"
    }
}

@main struct ModernRemoteMacApp: App {
    @StateObject private var model = Companion()
    var body: some Scene {
        WindowGroup("音乐遥控 · Mac") {
            VStack(alignment: .leading, spacing: 20) {
                Label("音乐遥控", systemImage: "hifispeaker.fill").font(.largeTitle.bold())
                Text("用 iPhone 选歌，让 Mac 播放。").foregroundStyle(.secondary)
                Label(model.message, systemImage: model.connected ? "lock.shield.fill" : "wifi")
                    .textSelection(.enabled)
                if model.running {
                    Text("配对码").font(.headline)
                    Text(model.secret).font(.system(size: 48, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                    Button("复制配对码") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.secret, forType: .string) }
                    Text("在 iPhone 上输入这四位数字，再选择这台 Mac。停止共享后会更换配对码。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Text(model.playback.title).font(.title2)
                Text(model.playback.artist).foregroundStyle(.secondary)
                Button(model.running ? "停止共享并更换配对码" : "开启共享") {
                    if model.running { model.stop() } else { model.start() }
                }.buttonStyle(.borderedProminent)
                Text("请确认 Mac 的“音乐”应用可以正常播放。系统询问时，请允许本应用通过自动化控制“音乐”。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(30).frame(width: 520)
                .environment(\.locale, Locale(identifier: "zh_Hans"))
        }
    }
}
