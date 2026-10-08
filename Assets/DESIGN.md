# Remote icon

The user explicitly requested the visual design of Apple's iOS iTunes Remote icon. The reference is the official [App Store page](https://apps.apple.com/us/app/itunes-remote/id284417350): blue vertical gradient and a rounded white play triangle. This prototype is independent of Apple.

Both icon masters are rendered from vector paths in `Scripts/RenderMacIcon.swift`. iPhone/iPad uses an opaque, full-bleed 1024px canvas (`Icon-1024.png`), masked by the operating system. Mac uses an 824px continuous rounded rectangle centered on a transparent 1024px canvas (`Mac-Icon-1024.png`), matching the 824/1024 opaque footprint measured from the installed system Music.app icon. No inset border, glass rim, music-note mark or wireless arcs.

Compile using `swiftc -parse-as-library Scripts/RenderMacIcon.swift -o render-icon`, then run `render-icon Mac-Icon-1024.png` for Mac, or `render-icon Icon-1024.png --ios` for iOS. Scale standard iconset renditions with `sips` and package with `iconutil -c icns`. Mac bundles its ICNS directly and loads that resource. Installation does not change Dock caches or preferences.
