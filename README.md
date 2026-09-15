# Disk Bloom

macOS disk space visualizer — a free alternative to DaisyDisk, GrandPerspective, Disk Inventory X, OmniDiskSweeper, and cross-platform tools like SquirrelDisk, WinDirStat and WizTree.

Pick a volume or folder, get a fast concurrent scan, then explore an interactive sunburst: hover for size/percent, click a segment to zoom in, click the center to go back up, right-click to reveal in Finder or move to Trash (never hard-deletes).

The scanner counts what's actually on disk: hardlinked files count once (du semantics), firmlinked directories aren't double-counted, symlinks are never followed, and scans stay on one volume. A whole-disk total matches `df`.

## Reclaim

A size chart can tell you a folder is 74 GB. It can't tell you what that folder is or what to do about it, and for tool-owned directories "select and trash" is usually the wrong answer. The Reclaim panel (⇧⌘R) adds three things the chart can't show on its own:

Known owners. Xcode DerivedData, simulator runtimes, npm and Homebrew caches, `node_modules`, Docker and OrbStack disk images, and others are recognized by path. Each one says what owns it, whether it regenerates by itself or needs checking first, and the correct reclaim step. For a Docker or OrbStack image that step is a command, since the space is inside the image and deleting the file destroys the tool.

Cold data. Every node carries its modification time, and a directory reports the newest one in its subtree, so a folder counts as untouched only when nothing inside it has been. Large things nothing has opened in months are listed separately from large things in daily use.

Held space. Local Time Machine snapshots pin the blocks of deleted files, so free space often doesn't move by as much as you just deleted. The panel says how many snapshots are holding blocks and how much is purgeable.

## Exclusions

Settings takes a list of folders the scanner never descends into. An excluded tree is never opened, costs nothing to skip, and contributes nothing to any parent's total. Useful for an rsync `--link-dest` mirror or any folder whose size you've already decided about.

## Build

```
xcodegen
xcodebuild -project Bloom.xcodeproj -scheme Bloom -configuration Release build
```

Engine tests: `cd Packages/BloomCore && swift test`

## Privileged scanning

- "Scan as administrator" (welcome screen or Settings) runs the embedded `bloom-scan` helper with admin privileges — one password prompt per scan. The helper scans with the same engine and hands the tree back via a serialized temp file.
- For everyday scans, grant the app Full Disk Access (System Settings → Privacy & Security) — the welcome screen offers this when not granted. That's what stops macOS's per-folder permission pop-ups.

## Debug flags

- `--autoscan <dir>` — skip the welcome screen and scan a path
- `--autofocus <child>` / `--autotrash <child>` — drive zoom/trash for screenshot testing
- `--report <path>` — write the scanned tree as text and exit
- `--snapshot <dir> --out <png>` — render a chart offscreen to PNG
- `--uishot <png>` — capture the app window to PNG
- `--autoinsights` — open the Reclaim panel after a scan, for screenshot testing
- `--icon <png>` — render the app icon artwork
