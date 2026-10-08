# App icons

The iPhone/iPad master is `Icon-1024.png`, originally generated with image_gen. The operating system masks this full-bleed artwork.

The dedicated macOS master is `Mac-Icon-1024.png`. It is rendered from original vector paths in `Scripts/RenderMacIcon.swift`: a centered 824-point white continuous rounded tile on a transparent 1024-point canvas, a coral musical note and wireless arcs, and a restrained shadow. No glossy border, simulated glass rim or baked heavy bevel. The Mac target bundles `AppIcon.icns` directly and does not compile the iOS asset catalog.

To regenerate the Mac master, compile the Swift source with the full Xcode toolchain using `swiftc -parse-as-library`, then pass an output PNG path to the executable. Scale to standard iconset sizes with `sips`, then package with `iconutil -c icns`. Always inspect both the 1024px master and small renditions. The application loads its packaged ICNS directly; no Dock-cache maintenance is needed.
