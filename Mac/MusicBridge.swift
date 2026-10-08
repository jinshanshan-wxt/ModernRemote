import Foundation
import AppKit
import CoreAudio
import CryptoKit

// NSAppleScript is executed serially on the main thread. Scripts consist only
// of fixed commands plus escaped strings / validated numeric values.
final class MusicBridge {
    private var airDeviceIDs: [String: String] = [:]
    private var localTrackIDs: Set<String>?
    private var artworkCache: [String: Data] = [:]

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
        return {name of current track, artist of current track, s, player position, duration of current track, v, persistent ID of current track}
        """)
        return Playback(trackID: result.atIndex(7)?.stringValue, title: result.atIndex(1)?.stringValue ?? "", artist: result.atIndex(2)?.stringValue ?? "",
                        playing: result.atIndex(3)?.stringValue == "playing",
                        position: number(result.atIndex(4)), duration: number(result.atIndex(5)), volume: number(result.atIndex(6)))
    }
    private func number(_ item: NSAppleEventDescriptor?) -> Double {
        guard let item else { return 0 }
        return item.coerce(toDescriptorType: typeIEEE64BitFloatingPoint)?.doubleValue ?? 0
    }
    func library(offset: Int, playlistID: String? = nil) throws -> ([RemoteTrack], Bool) {
        guard offset >= 0 && offset <= 1_000_000 else { throw failure("资料库分页位置无效，请重新加载。") }
        if let id = playlistID, !(id.count == 16 && id.allSatisfy({ $0.isHexDigit })) { throw failure("播放列表 ID 无效。") }
        if offset == 0 || localTrackIDs == nil {
            // Do not expose filesystem paths; only publish whether a Music file track has a location.
            if let ids = try? run("get persistent ID of (file tracks of library playlist 1 whose location is not missing value)") {
                localTrackIDs = Set((0..<ids.numberOfItems).compactMap { ids.atIndex($0 + 1)?.stringValue })
            }
        }
        let source = playlistID.map { "(first user playlist whose persistent ID is \(Self.quote($0)))" } ?? "library playlist 1"
        let result = try run("""
        tell \(source)
            set total to count of tracks
            set lastIndex to \(offset + 200)
            if lastIndex > total then set lastIndex to total
            if \(offset + 1) > total then return {{}, total}
            set output to {persistent ID, name, artist, album, duration, genre, album artist, track number, date added, favorited, album favorited, played count, year, rating, album rating, disc number} of tracks \(offset + 1) thru lastIndex
            return {output, total}
        end tell
        """)
        guard let columns = result.atIndex(1) else { throw failure("无法读取 Mac 资料库。") }
        let count = columns.atIndex(1)?.numberOfItems ?? 0
        var tracks: [RemoteTrack] = []
        if count > 0 {
            for i in 1...count {
                func field(_ column: Int) -> NSAppleEventDescriptor? { columns.atIndex(column)?.atIndex(i) }
                let id = field(1)?.stringValue ?? ""
                tracks.append(RemoteTrack(id: id, title: field(2)?.stringValue ?? "",
                    artist: field(3)?.stringValue ?? "", album: field(4)?.stringValue ?? "",
                    duration: number(field(5)), dateAdded: field(9)?.dateValue?.timeIntervalSince1970 ?? 0,
                    genre: field(6)?.stringValue ?? "", albumArtist: field(7)?.stringValue ?? "",
                    trackNumber: Int(field(8)?.int32Value ?? 0),
                    favorite: field(10)?.booleanValue, albumFavorite: field(11)?.booleanValue,
                    playCount: field(12).map { Int($0.int32Value) }, year: field(13).map { Int($0.int32Value) },
                    rating: field(14).map { Int($0.int32Value) }, albumRating: field(15).map { Int($0.int32Value) },
                    downloaded: localTrackIDs.map { $0.contains(id) }, discNumber: field(16).map { Int($0.int32Value) }, macID: id))
            }
        }
        return (tracks, offset + tracks.count < Int(result.atIndex(2)?.int32Value ?? 0))
    }
    func playlists() throws -> [RemotePlaylist] {
        let rows = try run("""
        set output to {}
        repeat with p in user playlists
            set end of output to {persistent ID of p, name of p, count of tracks of p, favorited of p}
        end repeat
        return output
        """)
        guard rows.numberOfItems > 0 else { return [] }
        return (1...rows.numberOfItems).compactMap { i in
            guard let row = rows.atIndex(i), let id = row.atIndex(1)?.stringValue else { return nil }
            return RemotePlaylist(id: id, name: row.atIndex(2)?.stringValue ?? "", trackCount: row.atIndex(3).map { Int($0.int32Value) }, favorite: row.atIndex(4)?.booleanValue)
        }
    }
    func artwork(id: String) throws -> Data? {
        guard id.count == 16, id.allSatisfy({ $0.isHexDigit }) else { throw failure("歌曲 ID 无效。") }
        if let cached = artworkCache[id] { return cached }
        let result = try run("""
        set t to first track of library playlist 1 whose persistent ID is \(Self.quote(id))
        if (count of artworks of t) is 0 then return missing value
        return raw data of artwork 1 of t
        """)
        guard let image = NSImage(data: result.data) else { return nil }
        let small = NSImage(size: NSSize(width: 320, height: 320))
        small.lockFocus(); image.draw(in: NSRect(x: 0, y: 0, width: 320, height: 320)); small.unlockFocus()
        guard let tiff = small.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        if artworkCache.count >= 300 { artworkCache.removeAll() }
        artworkCache[id] = data
        return data
    }
    private func playQueue(_ tracks: [RemoteTrack]) throws {
        guard !tracks.isEmpty, tracks.count <= 1000,
              tracks.allSatisfy({ $0.id.count == 16 && $0.id.allSatisfy({ $0.isHexDigit }) }) else { throw failure("队列最多支持 1000 首 Mac 歌曲。") }
        // A dedicated native playlist lets Music advance naturally while the phone sleeps.
        let ids = tracks.map { Self.quote($0.id) }.joined(separator: ",")
        _ = try run("""
        set p to make new user playlist with properties {name:"音乐遥控 · " & (current date as string)}
        repeat with trackID in {\(ids)}
            duplicate (first track of library playlist 1 whose persistent ID is (trackID as string)) to p
        end repeat
        set shuffle enabled to false
        set song repeat to off
        play p
        return persistent ID of p
        """)
    }
    func audioRoutes() throws -> [AudioRoute] {
        let result = try run("""
        set output to {}
        repeat with d in AirPlay devices
            if supports audio of d then
                set end of output to {(id of d) as string, name of d, (kind of d) as string, selected of d, available of d, protected of d, network address of d}
            end if
        end repeat
        return output
        """)
        var air: [AudioRoute] = []
        airDeviceIDs = [:]
        for i in 0..<result.numberOfItems {
            guard let row = result.atIndex(i + 1), let id = row.atIndex(1)?.stringValue else { continue }
            let name = row.atIndex(2)?.stringValue ?? "AirPlay"
            let address = row.atIndex(7)?.stringValue ?? ""
            let identity = address.isEmpty ? name + "|" + (row.atIndex(3)?.stringValue ?? "") : address.lowercased()
            let stableID = "air:" + SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
            airDeviceIDs[stableID] = id
            air.append(AudioRoute(id: stableID, name: name,
                kind: row.atIndex(3)?.stringValue ?? "AirPlay", selected: row.atIndex(4)?.booleanValue ?? false,
                available: row.atIndex(5)?.booleanValue ?? false, requiresPassword: row.atIndex(6)?.booleanValue ?? false))
        }
        let localSelected = air.contains { $0.kind == "computer" && $0.selected }
        let local = CoreAudioOutputs.routes(selected: localSelected)
        return local + air.filter { local.isEmpty || $0.kind != "computer" }
    }
    func selectAudioRoute(_ id: String) throws {
        guard let route = try audioRoutes().first(where: { $0.id == id }), route.available else {
            throw failure("此音频输出已不可用，请刷新设备列表。")
        }
        if route.isSystem {
            guard let device = UInt32(id.dropFirst(5)) else { throw failure("音频设备无效。") }
            let previous = CoreAudioOutputs.defaultDevice()
            try CoreAudioOutputs.select(device)
            do { _ = try run("set current AirPlay devices to {first AirPlay device whose kind is computer}") }
            catch { if let previous { try? CoreAudioOutputs.select(previous) }; throw error }
        } else {
            guard let deviceID = airDeviceIDs[id] else { throw failure("AirPlay 设备已断开。") }
            _ = try run("""
            set chosen to missing value
            repeat with d in AirPlay devices
                if (id of d as string) is \(Self.quote(deviceID)) then set chosen to contents of d
            end repeat
            if chosen is missing value then error "AirPlay 设备已断开"
            set current AirPlay devices to {chosen}
            """)
        }
    }
    func execute(_ packet: Packet) throws {
        switch packet.action {
        case "queue": try playQueue(packet.tracks ?? [])
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

// Controls the Mac's default media output, never the iPhone audio session.
enum CoreAudioOutputs {
    private static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    static func defaultDevice() -> AudioDeviceID? {
        var a = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id: AudioDeviceID = 0; var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr ? id : nil
    }
    static func routes(selected: Bool) -> [AudioRoute] {
        var a = address(kAudioHardwarePropertyDevices); var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids) == noErr else { return [] }
        let current = defaultDevice()
        return ids.compactMap { id in
            var streams = address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput); var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            var name: Unmanaged<CFString>? = nil; var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var nameAddress = address(kAudioObjectPropertyName)
            let result = withUnsafeMutablePointer(to: &name) { AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, $0) }
            guard result == noErr, let name = name?.takeRetainedValue() else { return nil }
            var alive: UInt32 = 0; var aliveSize = UInt32(MemoryLayout<UInt32>.size)
            var aliveAddress = address(kAudioDevicePropertyDeviceIsAlive)
            _ = AudioObjectGetPropertyData(id, &aliveAddress, 0, nil, &aliveSize, &alive)
            return AudioRoute(id: "core:\(id)", name: name as String, kind: "system", selected: selected && id == current, available: alive != 0)
        }
    }
    static func select(_ id: AudioDeviceID) throws {
        guard routes(selected: false).contains(where: { $0.id == "core:\(id)" && $0.available }) else {
            throw NSError(domain: "CoreAudio", code: -1, userInfo: [NSLocalizedDescriptionKey: "输出设备已断开。"])
        }
        var a = address(kAudioHardwarePropertyDefaultOutputDevice); var value = id
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value)
        guard status == noErr else { throw NSError(domain: "CoreAudio", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "无法切换 Mac 音频输出（\(status)）。"]) }
    }
}
