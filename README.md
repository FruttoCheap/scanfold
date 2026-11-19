# Scanfold

Find out what is filling up your Mac. Scanfold scans your startup disk and draws it as a map of blocks: the bigger the block, the more space it takes. Click into folders, preview files, and move what you don't need to the Trash.

- Free and open source (MIT)
- Works offline: it has no network code, nothing leaves your Mac
- Never deletes anything permanently: items go to the Trash, so you can put them back

## Requirements

macOS 14 Sonoma or later, on Apple silicon or Intel.

## Install

1. Download **Scanfold-x.y.dmg** from the [latest release](https://github.com/FruttoCheap/scanfold/releases/latest).
2. Open it and drag **Scanfold** onto the **Applications** folder.
3. Open Scanfold from Applications. macOS asks to confirm because it was downloaded from the internet: click **Open**.

## Allow Full Disk Access

macOS hides some folders (Mail, Messages, other apps' data) from apps until you allow it. Without this permission Scanfold still works, but those folders are counted as "unreadable" and the map is incomplete.

1. In Scanfold, click **Open System Settings** in the orange bar at the top.
2. Turn on the switch next to **Scanfold**. If it's not in the list, click **+** and pick Scanfold from Applications.
3. Quit and reopen Scanfold.

To build the map, Scanfold only reads file names and sizes. A handful of system folders stay unreadable even with this permission; that's normal.

## How to use it

- Click **Scan** (top right). The result is remembered for the next time you open the app.
- **Click a folder** block to go inside it. **Click a file** to preview it.
- Go back with the **up arrow** or by clicking a folder in the path bar.
- **Right-click** any block for Quick Look, Show in Finder, or Add to Collector.
- **Drag** blocks into the **Collector** at the bottom, check the total, then click **Move to Trash**. Scanfold asks for confirmation first.
- **Small files** blocks group every file under 1 MB in a folder. They can't be trashed as a group.
- The **Storage** bar at the bottom compares what was scanned with the disk's used and free space. **Purgeable** is space macOS frees on its own when needed (caches, snapshots).

Scanfold looks at the startup disk only. External drives and other volumes are not scanned.

## Uninstall

Move Scanfold from Applications to the Trash, and delete the folder `~/Library/Application Support/Scanfold` (the saved scan). You can also remove Scanfold from System Settings › Privacy & Security › Full Disk Access.

## Build from source

Needs Xcode 26 or later (which runs on macOS 15.6 or later). The built app still runs on macOS 14.

```bash
xcodebuild -project Scanfold.xcodeproj -scheme Scanfold -configuration Release -derivedDataPath build -quiet build && ditto build/Build/Products/Release/Scanfold.app /Applications/Scanfold.app
```

A local build is signed ad hoc, so each rebuild looks like a new app to macOS: turn Full Disk Access off and on again for Scanfold after updating.

Cache format check (no Xcode project needed):

```bash
swiftc Scanfold/Model/*.swift Tests/main.swift -o build/check && build/check
```

### Releasing

Needs a Developer ID Application certificate. Store the notary credentials once:

```bash
xcrun notarytool store-credentials scanfold --apple-id <apple-id> --team-id G9Y55AN5H5
```

Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`, then build, sign, notarize and staple the DMG:

```bash
scripts/release.sh
```

The script prints the `gh release create` command that publishes it.

## License

[MIT](LICENSE)
