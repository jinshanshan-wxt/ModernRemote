# Modern Remote 0.7.0

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

- Mac library: automatic 200-track pages; artist/album/genre groups; recently added album grid sorted by each album’s newest Mac date-added; ascending/descending sorting; Mac user playlists and their tracks. Album grouping uses album artist when available. Empty genre becomes uncategorized.
- Artwork: fetched on demand from Music.app artwork data, transferred without resizing or recompression and cached on disk. Display images are decoded in the background at a size matched to screen scale. No catalog lookup. If Music does not expose the artwork, a placeholder remains. Covers available only inside Apple's streaming interface are not guaranteed.
- Navigation on iPhone: five tabs for Artists, Albums, Songs, Genres and More. More contains Playlists, Recently Added and Settings. Mac library selection, connection management and reload live in Settings. Albums use an adaptive artwork grid, artists open their albums. A floating mini-player above the tabs opens the artwork-led full-screen Now Playing page. iOS 26 uses the native tab-bar accessory; older versions use an inset mini-player. All main labels are Simplified Chinese.
- iPad: a native sidebar for Recently Added, Artists, Albums, Songs, Genres, Playlists and Settings; compact playback capsule centered at the bottom. Album/playlist pages use a side-by-side cover and metadata header, a compact monochrome play button, and song/artist/duration columns. Appearance follows the system; selections use the Music red accent. Sidebar rows explicitly update the detail route; screenshot-only preview overrides have been removed. Songs use a text-only table; Recently Added opens albums, not individual songs. iPhone retains its five-tab layout.
- Playback status: polls every two seconds while active. Multiple clients receive the same Mac status. Playback/status/output requests bypass background library/artwork loads; status polls are coalesced rather than dropped during loading. Shuffle and repeat controls read and update real Music.app state. Music keeps playing when the phone sleeps.
- Connection: Bonjour discovery with restart, manual address/port fallback, automatic retry, remembered preferred Mac. Mac must be awake and sharing. Guest-Wi-Fi isolation/firewalls may prevent access. Discovery cannot determine whether two devices literally use the same Wi-Fi SSID; it operates on the reachable LAN.
- **Open LAN mode:** requested zero-pairing mode uses unauthenticated, unencrypted TCP. Any device able to reach the listener can browse/control Music while sharing is on. Stop sharing to close every connection. No claim of encrypted pairing is made.
- Now Playing: artwork-colored blurred background, thin progress/volume sliders and playback controls. Shuffle, AirPlay and repeat share a compact 19pt icon row; enabled shuffle/repeat and repeat-one are indicated. iPad uses the full screen, with cover and controls side by side in landscape. Hostnames, computer badges and Up Next have been removed from this page.
- Filters and display options: All / Favorites, nested sorting and ascending/descending order, saved separately for each category. Songs support title, play count, genre, duration, favorite, artist, downloaded status and album; albums support title, artist, year and rating. Display options include album grid/list and cover size, artwork, artist, album, duration, rating and playlist track counts where applicable. Values come from Mac metadata. Artist favorites are unavailable in Music's scripting interface, so that filter is disabled with an explanation; song, album and playlist favorites are supported. Genres sort by title. Unknown metadata sorts last.
- AirPlay/output: the picker controls Mac Music's discovered AirPlay devices (including HomePod) and CoreAudio local outputs (built-in speakers, connected display/USB devices). Selecting a local output also changes Mac's default system output. This prototype selects one destination at a time. Password-protected destinations may require verification on Mac. It does not display the iPhone's audio routes. Device discovery and availability are controlled by Mac Music/macOS. AirPlay selection waits for actual audio reception when already playing (up to ten seconds), preserves playback through the change, and reports connection errors instead of optimistic success. Route rows show a pending indicator until acknowledgement.
- Up Next has no UI or remote queue response. **Ordered album/collection playback** remains available: it creates a dated `音乐遥控` user playlist in Mac Music and plays it in order or with shuffle enabled (repeat disabled), up to 10000 tracks. Individual song taps rebuild or reuse the current screen’s ordered playback context and play a native playlist starting with the tapped song; Next/Previous use that native playlist. Songs use the displayed sort/filter, search uses its results, and albums/playlists use their track order. Queues transfer compact persistent IDs rather than repeating metadata. Existing native Up Next contents cannot be fully read or edited by this prototype.
- Mac icon: an independent rounded, transparent-margin ICNS is explicitly packaged and loaded, separate from the iOS asset catalog. Installation does not alter Dock caches or preferences.
- Library loading is a snapshot, not live synchronization. Very large libraries use memory on iOS and synchronous AppleScript on Mac; changes during pagination may require refresh. No playlist editing, playlist-folder hierarchy mirroring, DRM extraction, or complete native Up Next editing.

## API and permissions

Native Mac playback uses Music.app's installed AppleScript dictionary. It does not pretend iOS SystemMusicPlayer controls a remote Mac. MusicKit on the phone is not used to read the Mac library. The Mac companion uses Music's installed scripting dictionary plus CoreAudio for local output selection.

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

Both native Release targets and the iOS Simulator target compile with Xcode 26.3. Protocol checks exercise Unicode framing, size/version rejection, AppleScript argument escaping and two concurrent no-pairing LAN clients. Live Mac checks retrieved song pages, playlists, playlist tracks, date-added metadata, artwork bytes and playback state. Version 0.4 additionally verifies metadata sorting/missing values, Mac play counts/favorites/year/rating/downloaded flags, and real switching between HomePod, built-in speakers and display audio (restoring the original output). Full-screen player layouts were inspected on iPad Pro M4 and iPhone 17 Pro Max simulators. Signed physical-device installation and exhaustive huge-library/background behavior remain device acceptance checks.

## Troubleshooting

- No Mac: turn on sharing; allow Local Network access; use the same reachable LAN; check firewall/client isolation. Try **重新搜索**, then manual address and port shown on Mac. Simulator on that Mac can use `127.0.0.1`.
- Automation error: System Settings → Privacy & Security → Automation → allow Music control.
- Missing artwork: refresh the library and verify Music itself exposes artwork for the track.
- Cloud track unavailable: Music.app must have the required account/subscription and network access to play it.
- Missing AirPlay destination: confirm it is visible and available in Mac Music, then refresh the output picker. Local output selection changes system audio, including other apps.

The Mac companion lives in the menu bar, without a Dock icon or launch window. Sharing starts automatically on launch. Click the menu bar play icon for status, connection addresses, start/stop sharing, or Quit.

Mobile UI: compact song rows with artist/album columns, dedicated library search in More (iPad sidebar), persistent four-slot tab editing with tap or drag-and-drop, a shared Music accent for UIKit and SwiftUI, and slider thumbs shown only while dragging. Album/playlist covers, track rows, separators and totals share a single 24-point content inset.

Track titles use 16-point text, supporting metadata uses 13/14-point text, and rows use 46-point height for comfortable reading.

Persistent cache: both platforms store complete library snapshots, opened playlists and original artwork in Application Support, excluded from backups. Cache namespaces combine a persistent Mac installation UUID and Music library persistent ID. On launch the mobile app restores its last snapshot and connects with a small cache manifest; matching revisions skip all library/playlist transfers. The Mac reuses its snapshot after restart instead of rescripting every track. Track-count changes or a 24-hour age trigger one shared rebuild. Metadata edits and playlist changes appear at the next automatic check; manual Reload Library and Artwork immediately rebuilds both caches and invalidates artwork. Artwork (including missing-artwork results) is stored individually; disk artwork is capped at approximately 256 MB per library and memory at 300 images. Only complete snapshots/playlists are saved atomically, corrupt files fall back to reload. First use or manual refresh still requires a full scan. Update both companions to use the manifest optimization.

Version 0.8: Genres open an album list (cover, artist/year, track count), then album details. Genre membership selects whole albums, including mixed-genre tracks. iPhone album details use a compact cover/title header, adjacent Play/Shuffle Play buttons, numbered tracks and durations; iPad retains a large header. Songs/artists/albums/recent albums have a right-edge rail supporting tap and continuous drag to any position in the current ordering, with a title preview. Library filtering/grouping/sorting and rail labels are calculated off the main thread only when the library generation or browser preferences change, not on artwork/playback updates. Artwork is decoded off the main thread and decoded pixels use a memory-pressure-aware 64 MB cache. Rail jumps are unanimated and limited to 25 per second, with a final release jump.

Playback regression fix: playing a library track reference alone could leave Music’s previous album queue attached to Next, or stop after that old queue finished. Song taps now send the complete screen context plus the selected index; Mac plays the **native playlist itself**, containing the selected song and subsequent tracks, including when reusing a playlist after exhaustion. Bulk library ID lookup avoids a full search per insertion. Update both platforms together. Protocol tests cover selection index/order and the 10000-ID frame limit.

Version 0.8.1 corrects the incomplete 0.8.0 playback fix. Music's `play track N of playlist` still produced a one-item playback queue in live tests, even with `once false`. The companion now builds the native playlist from the selected song through the end of the screen order and calls `play playlist`. Previous can return to the song preceding the original selection by rebuilding that earlier starting point. Full context remains in companion memory; the native playlist holds the remaining suffix. Live tests verify changed contexts, Next after exhausted queues, restarting the same context, Previous across the starting boundary, natural automatic advancement, natural queue exhaustion and selecting/advancing again afterward.

Native playback integration test: stop Music first, then run `python3 Tests/PlaybackIntegration.py --port <companion-port> --exercise-playback`. This is opt-in because it actually plays local songs and creates the same dated remote playlists as ordinary use. It restores the stopped state and shuffle/repeat modes. The default unit suite does not play music.

Version 0.8.2 preserves Music.app raw artwork bytes with bounded, ordered chunk transfers. A new artwork cache namespace ignores old 320px thumbnails while retaining library snapshots. Player covers and backgrounds remain visible until the next cover has decoded, and brief empty playback states are debounced across a status poll. Album Play and Shuffle are compact buttons beside the album information. Update both apps for original artwork; resolution is limited by what Music exposes.

Version 0.8.3 fixes invisible iPad sidebar labels in dark mode by using a neutral custom selection background. New selections cancel unsent old playback intents; generation tokens reject obsolete controls from other controllers. The companion explicitly serializes complete Music transactions even if an Apple Event pumps the main run loop, ignores pending commands from disconnected peers, and verifies native playlist identity and selected track across three consecutive reports before reporting success. Native Next/Previous preserve the preceding playing/paused state. Previous only uses saved context when the native playlist still belongs to it. Bounded local identifier-only command/state diagnostics are stored at Application Support/ModernRemote/PlaybackDiagnostics-v1.json (200 entries, background disk writes) to investigate intermittent unexpected source changes. The reported spontaneous Our Song-to-Jay jump was not reproduced in a 15-second baseline observation; cross-album, stale-control, Next and native-advance regression checks passed with the new safeguards.

The 0.8.3 live regression also verifies native queue exhaustion/reselection and both paused and playing Next/Previous states with two concurrent polling controllers. Use `python3 Tests/PlaybackIntegration.py --port PORT --exercise-playback --polling-controllers 2` while Music is stopped.
