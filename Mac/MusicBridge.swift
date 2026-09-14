import Foundation
import AppKit

// NSAppleScript is executed serially on the main thread. Scripts consist only
// of fixed commands plus escaped strings / validated numeric values.
final class MusicBridge {
    static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
    private func run(_ body: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        let result = NSAppleScript(source: "tell application \"Music\"\n\(body)\nend tell")!
            .executeAndReturnError(&error)
        if let error {
            throw NSError(domain: "MusicAutomation", code: error["NSAppleScriptErrorNumber"] as? Int ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: error["NSAppleScriptErrorMessage"] as? String ?? "无法控制“音乐”应用，请检查自动化权限。"])
        }
        return result
    }
    func status() throws -> Playback {
        let result = try run("""
        set v to sound volume
        set s to player state as string
        if s is "stopped" then return {"尚未播放", "", s, 0, 0, v}
        return {name of current track, artist of current track, s, player position, duration of current track, v}
        """)
        return Playback(title: result.atIndex(1)?.stringValue ?? "", artist: result.atIndex(2)?.stringValue ?? "",
                        playing: result.atIndex(3)?.stringValue == "playing",
                        position: number(result.atIndex(4)), duration: number(result.atIndex(5)), volume: number(result.atIndex(6)))
    }
    private func number(_ item: NSAppleEventDescriptor?) -> Double {
        guard let item else { return 0 }
        return item.coerce(toDescriptorType: typeIEEE64BitFloatingPoint)?.doubleValue ?? 0
    }
    func library(offset: Int) throws -> ([RemoteTrack], Bool) {
        guard offset >= 0 && offset <= 1_000_000 else { throw failure("资料库分页位置无效，请重新加载。") }
        let result = try run("""
        set output to {}
        tell library playlist 1
            set total to count of tracks
            set lastIndex to \(offset + 200)
            if lastIndex > total then set lastIndex to total
            if \(offset + 1) <= total then
                repeat with i from \(offset + 1) to lastIndex
                    set t to track i
                    set end of output to {persistent ID of t, name of t, artist of t, album of t, duration of t}
                end repeat
            end if
        end tell
        return {output, total}
        """)
        let rows = result.atIndex(1)!
        var tracks: [RemoteTrack] = []
        if rows.numberOfItems > 0 {
            for i in 1...rows.numberOfItems {
                guard let row = rows.atIndex(i) else { continue }
                let id = row.atIndex(1)?.stringValue ?? ""
                tracks.append(RemoteTrack(id: id, title: row.atIndex(2)?.stringValue ?? "",
                                          artist: row.atIndex(3)?.stringValue ?? "", album: row.atIndex(4)?.stringValue ?? "",
                                          duration: number(row.atIndex(5)), macID: id))
            }
        }
        return (tracks, offset + tracks.count < Int(result.atIndex(2)?.int32Value ?? 0))
    }
    func execute(_ packet: Packet) throws {
        switch packet.action {
        case "play": _ = try run("play")
        case "pause": _ = try run("pause")
        case "previous": _ = try run("previous track")
        case "next": _ = try run("next track")
        case "seek":
            guard let value = packet.value, value.isFinite, value >= 0 else { throw failure("播放进度无效。") }
            let current = try status()
            guard current.duration > 0 else { throw failure("当前歌曲不支持调整进度。") }
            _ = try run("set player position to \(min(value, current.duration))")
        case "volume":
            guard let value = packet.value, value.isFinite, (0...100).contains(value) else { throw failure("音量值无效。") }
            _ = try run("set sound volume to \(Int(value))")
        case "track":
            guard let track = packet.track else { throw failure("没有收到歌曲信息。") }
            if let id = track.macID {
                guard id.count == 16 && id.allSatisfy({ $0.isHexDigit }) else { throw failure("Mac 曲目 ID 无效。") }
                _ = try run("play (first track of library playlist 1 whose persistent ID is \(Self.quote(id)))")
            } else {
                // iPhone library IDs are NOT Mac persistent IDs. Resolve only a
                // unique metadata match; never guess or silently play another song.
                guard track.title.count <= 1024, track.artist.count <= 1024, track.album.count <= 1024,
                      track.duration.isFinite else { throw failure("歌曲信息无效。") }
                let candidates = try run("""
                set found to {}
                repeat with t in (every track of library playlist 1 whose name is \(Self.quote(track.title)))
                    if artist of t is \(Self.quote(track.artist)) and album of t is \(Self.quote(track.album)) then
                        if \(track.duration) <= 0 or ((duration of t) > \(track.duration - 3) and (duration of t) < \(track.duration + 3)) then
                            set end of found to persistent ID of t
                        end if
                    end if
                end repeat
                return found
                """)
                guard candidates.numberOfItems == 1, let id = candidates.atIndex(1)?.stringValue else {
                    throw failure("Mac 资料库中没有唯一匹配的歌曲。请先在 Mac 添加或同步这首歌，或从“Mac 资料库”选择准确的版本。")
                }
                _ = try run("play (first track of library playlist 1 whose persistent ID is \(Self.quote(id)))")
            }
        default: throw failure("暂不支持此操作。")
        }
    }
    private func failure(_ text: String) -> Error { NSError(domain: "ModernRemote", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
