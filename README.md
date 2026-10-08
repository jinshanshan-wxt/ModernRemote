# Modern Remote 0.3.0

<img src="Assets/Mac-Icon-1024.png" width="128" alt="Modern Remote Mac icon">

A SwiftUI iPhone/iPad remote for the library and playback of **Music.app on your Mac**. All browsing data comes from the Mac, including unsynced local tracks. No iPhone Apple Music account, MusicKit entitlement, hosted server or custom account is required.

## Run

1. Open `ModernRemote.xcodeproj` in Xcode. Choose your team and bundle identifiers for device signing. Schemes: ModernRemoteMac and ModernRemoteiOS. Minimum iOS 17 / macOS 14.
2. Run the Mac app, open Music.app, and click **开启共享**. Allow Automation access to Music and local-network access when prompted.
3. Open the iPhone/iPad app on the same LAN. A single discovered Mac connects automatically. The last selected Mac is remembered; select a Mac if several are available. No pairing code. Multiple controllers can connect concurrently.
4. The app loads Mac songs and playlists automatically in pages. Browse **最近添加 / 艺人 / 专辑 / 歌曲 / 类型 / 播放列表**. Search only examines Mac library data. While loading, search is explicitly marked partial; after completion it covers the loaded Mac library. Refresh after changing the library on Mac.
5. Tap a song for playback by its Mac persistent ID. Use the player for pause/resume, previous/next, seek and Music.app volume. All audio stays on Mac.

Chinese guide: `README.zh-CN.txt` (strict GBK). Swift/project/configuration files are UTF-8.

## Features and limits

- Mac library: automatic 200-track pages; artist/album/genre groups; recent additions sorted by Mac date-added; ascending/descending sorting; Mac user playlists and their tracks. Album grouping uses album artist when available. Empty genre becomes uncategorized.
- Artwork: fetched on demand from Music.app artwork data, resized to 320px and cached in memory. No catalog lookup. If Music does not expose the artwork, a placeholder remains. Covers available only inside Apple's streaming interface are not guaranteed.
- Navigation on iPhone and iPad: five tabs for Artists, Albums, Songs, Genres and More. More contains Playlists, Recently Added and Settings. Mac library selection, connection management and reload live in Settings. Albums use an adaptive artwork grid, artists open their albums. A floating mini-player above the tabs opens the artwork-led Now Playing sheet. iOS 26 uses the native tab-bar accessory; older versions use an inset mini-player. All main labels are Simplified Chinese.
- Playback status: polls every two seconds while active. Multiple clients receive the same Mac status. Music keeps playing when the phone sleeps.
- Connection: Bonjour discovery with restart, manual address/port fallback, automatic retry, remembered preferred Mac. Mac must be awake and sharing. Guest-Wi-Fi isolation/firewalls may prevent access. Discovery cannot determine whether two devices literally use the same Wi-Fi SSID; it operates on the reachable LAN.
- **Open LAN mode:** requested zero-pairing mode uses unauthenticated, unencrypted TCP. Any device able to reach the listener can browse/control Music while sharing is on. Stop sharing to close every connection. No claim of encrypted pairing is made.
- **Up Next:** Music.app's complete existing Up Next queue is not exposed by this implementation. “按顺序播放” explicitly creates a new, dated `音乐遥控` playlist in Mac Music and plays it with shuffle/repeat disabled. The player shows subsequent tracks from that app-created playlist only. Tracks manually inserted into native Up Next are not included. Native random playback or switching to another playlist hides this view. Each explicit ordered-play request creates a playlist visible on Mac; maximum 1000 tracks. Individual song taps do not replace a whole album queue.
- Library loading is a snapshot, not live synchronization. Very large libraries use memory on iOS and synchronous AppleScript on Mac; changes during pagination may require refresh. No playlist editing, playlist-folder hierarchy mirroring, DRM extraction, or complete native Up Next editing.

## API and permissions

Native Mac playback uses Music.app's installed AppleScript dictionary. It does not pretend iOS SystemMusicPlayer controls a remote Mac. See [Apple SystemMusicPlayer documentation](https://developer.apple.com/documentation/musickit/systemmusicplayer) and [Apple's MusicKit session](https://developer.apple.com/videos/play/wwdc2026/254/) for the distinction between app playback and system playback queues.

- Mac: Apple Events Automation entitlement and usage description; Hardened Runtime, no App Sandbox in this prototype.
- iPhone/iPad: Bonjour service `_modernremote._tcp` and Local Network usage description; no MusicKit entitlement or Music Library authorization.
- Shared transport: request IDs, 1 MiB bounded newline JSON frames, connection/response timeouts. Client serializes requests and does not replay failed commands after reconnect.
- macOS does not expose a Connect-like public cross-device API; the local companion supplies discovery, metadata and control.

## Build

```sh
# Select full Xcode first, or set DEVELOPER_DIR to your Xcode developer directory.
./Scripts/test.sh
./Scripts/build-mac.sh
./Scripts/build-ios.sh
```

Releases include an ad-hoc-signed Apple-silicon Mac ZIP, unsigned iOS IPA and complete Xcode source ZIP. Re-sign the IPA with your own certificate/profile. No MusicKit service is needed. The Mac binary is not notarized. Update both ends together when moving from older paired/TLS releases.

## Validation

Both native Release targets and the iOS Simulator target compile with Xcode 26.3. Protocol checks exercise Unicode framing, size/version rejection, AppleScript argument escaping and two concurrent no-pairing LAN clients. Live Mac checks retrieved song pages, playlists, playlist tracks, date-added metadata, artwork bytes and playback state. Signed physical-device installation and exhaustive huge-library/background behavior remain device acceptance checks.

## Troubleshooting

- No Mac: turn on sharing; allow Local Network access; use the same reachable LAN; check firewall/client isolation. Try **重新搜索**, then manual address and port shown on Mac. Simulator on that Mac can use `127.0.0.1`.
- Automation error: System Settings → Privacy & Security → Automation → allow Music control.
- Missing artwork: refresh the library and verify Music itself exposes artwork for the track.
- Cloud track unavailable: Music.app must have the required account/subscription and network access to play it.
- No full Up Next: the native queue is an API limitation, not a library permission problem. See the explicit app-playlist fallback above.
