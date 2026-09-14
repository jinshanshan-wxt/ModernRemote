import Foundation
import Network
import Combine

final class RemoteClient: ObservableObject {
    @Published var devices: [NWBrowser.Result] = []
    @Published var connected = false
    @Published var busy = false
    @Published var message = "请选择同一局域网中的 Mac。"
    @Published var playback = Playback()
    @Published var macTracks: [RemoteTrack] = []
    @Published var hasMore = true
    private var browser: NWBrowser?
    private var wire: Wire?
    private var pending: String?
    private var deferred: Packet?
    private var timeout: DispatchWorkItem?
    private var timer: AnyCancellable?
    func discover() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: SecureLAN.service, domain: nil), using: .tcp)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.devices = results.sorted { Self.name($0) < Self.name($1) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state { self?.message = error.localizedDescription; self?.browser?.cancel(); self?.browser = nil }
        }
        browser.start(queue: .main)
    }
    static func name(_ result: NWBrowser.Result) -> String {
        if case .service(let name, _, _, _) = result.endpoint { return name }
        return "Mac"
    }
    func connect(_ device: NWBrowser.Result, key: String) {
        let secret = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard SecureLAN.validSecret(secret) else { message = "请输入 Mac 窗口中显示的四位数字配对码。"; return }
        disconnect()
        macTracks = []; hasMore = true
        message = "正在建立加密连接……"
        let peer = Wire(NWConnection(to: device.endpoint, using: SecureLAN.parameters(secret: secret)))
        wire = peer
        peer.onReady = { [weak self] in
            guard let self else { return }
            self.connected = true; self.message = "已连接到 \(Self.name(device))"
            self.send(Packet(action: "status"))
            self.timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                guard let self, !self.busy else { return }
                self.send(Packet(action: "status"))
            }
        }
        peer.onClose = { [weak self] reason in
            guard let self else { return }
            self.connected = false; self.busy = false; self.pending = nil
            self.timeout?.cancel(); self.timer = nil; self.message = reason
        }
        peer.onPacket = { [weak self] packet in
            guard let self, packet.id == self.pending else { return }
            self.timeout?.cancel(); self.pending = nil; self.busy = false
            if let error = packet.error { self.message = error }
            if let playback = packet.playback { self.playback = playback }
            if let tracks = packet.tracks { self.macTracks.append(contentsOf: tracks); self.hasMore = packet.hasMore ?? false }
            if let next = self.deferred {
                self.deferred = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.send(next) }
            }
        }
        peer.start()
    }
    func send(_ packet: Packet) {
        guard connected else { return }
        if busy { if packet.action != "status" { deferred = packet }; return }
        busy = true; pending = packet.id
        let deadline = DispatchWorkItem { [weak self] in self?.wire?.close("Mac 未响应。请检查“音乐”应用与自动化权限，然后重新连接。") }
        timeout = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: deadline)
        wire?.send(packet)
    }
    func command(_ action: String, value: Double? = nil) { send(Packet(action: action, value: value)) }
    func play(_ track: RemoteTrack) { send(Packet(action: "track", track: track)) }
    func loadMacPage() { send(Packet(action: "library", offset: macTracks.count)) }
    func disconnect() {
        timer = nil; timeout?.cancel(); wire?.close(); wire = nil
        connected = false; busy = false; pending = nil; deferred = nil
    }
}
