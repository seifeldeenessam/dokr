# Dokr

iOS-style **app folders for the macOS Dock**. Group apps into a folder, pin it next to your apps, click it to get a popup grid, click an app to launch it.

- Folder icon on the Dock is a rendered 3×3 grid of the first 9 apps (like iOS)
- Popup looks like a Dock stack in grid view (rounded bubble with a tail pointing at the folder's Dock icon, large icons with names) and opens right next to the Dock icon, using the Dock's real settings (edge, auto-hide, icon size, magnification); blurred background; Esc, clicking outside, or clicking the Dock icon again closes it
- Click the folder name in the popup to open that folder in Dokr. Right-click an app for Open, Show in Finder, Remove from Folder (updates the Dock right away) and, while it's running, Quit / Force Quit
- Dock-style dots under apps that are open (follows "Show indicators for open applications"), updated live
- Editor: create/rename/reorder folders, add apps from a searchable list of installed apps, the Finder picker, or drag & drop; reorder/remove apps
- "Open" dot under a folder's Dock icon while any of its apps are running (optional, on by default): each folder's helper stays running in the background, as a regular app while one of its apps is open (the Dock draws the dot) and as a background-only app otherwise. The popup also opens instantly. Helpers start at login via `~/Library/LaunchAgents/com.seifeldeenessam.dokr.folders.plist` (macOS shows a "Background Items Added" notice once)
- Optional: remove grouped apps' own Dock icons when applying (like moving an app into a folder on iOS)
- Every Dock change backs up `persistent-apps` to `~/Library/Application Support/Dokr/Backups` (last 10)

## Install

```sh
brew install --cask uraxdev/tap/dokr
```

Upgrade with `brew upgrade --cask dokr`; uninstall (including folders, backups and the login agent) with `brew uninstall --zap --cask dokr`.

## How it works

No private APIs and nothing injected into the Dock:

1. Each folder becomes a tiny generated app in `~/Library/Application Support/Dokr/Folders/<Name>.app`:
   ```
   Contents/Info.plist              unique bundle ID per folder, LSUIElement (no running indicator)
   Contents/MacOS/DokrFolder        copy of the helper binary
   Contents/Resources/AppIcon.icns  rendered app-grid icon
   Contents/Resources/folder.json   folder definition
   ```
   It's ad-hoc signed (`codesign -s -`), which is all Apple silicon needs for locally created apps.
2. Dokr adds/updates/removes those apps in `com.apple.dock` → `persistent-apps` and restarts the Dock.
3. Clicking the tile launches the helper (fast, AppKit + SwiftUI); it shows the grid near the pointer, launches your pick via `NSWorkspace`, then quits.

Apps are stored by path with the bundle ID as fallback, so a moved app still launches.

## Build

Requires Xcode 15+ (or the Command Line Tools with Swift 5.9+), macOS 13+.

```sh
make test        # unit tests (DokrCore)
make run         # build/Dokr.app (ad-hoc signed) and open it
make install     # copy to /Applications
make universal   # arm64 + x86_64 (needs full Xcode)
make dmg         # universal build -> build/Dokr.dmg
```

Open in Xcode with `open Package.swift`. Try the popup alone without touching the Dock:

```sh
cat > /tmp/dev.json <<'JSON'
{"id":"6F1C2A52-3C55-4B8E-9A43-0C1B4E0F0001","name":"Dev","showInDock":true,
 "apps":[{"name":"Safari","path":"/Applications/Safari.app"},{"name":"Notes","path":"/System/Applications/Notes.app"}]}
JSON
swift run DokrFolder --config /tmp/dev.json
```

Releases: push a tag (`git tag v1.0.0 && git push origin v1.0.0`) and the Release workflow builds `Dokr.dmg`, publishes it as a release tagged `dokr-v1.0.0` on the public tap repo [`uraxdev/homebrew-tap`](https://github.com/uraxdev/homebrew-tap) (tags are prefixed because the tap hosts releases for several apps), and bumps `Casks/dokr.rb` there (needs the `TAP_TOKEN` secret: fine-grained PAT with Contents read/write on the tap). Push workflow changes to `main` before tagging; a tag runs the workflow as it is at the tagged commit. Direct downloads: `https://github.com/uraxdev/homebrew-tap/releases/download/dokr-v<version>/Dokr.dmg`, or pick a `dokr-v*` release on the [releases page](https://github.com/uraxdev/homebrew-tap/releases).

Manual distribution:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" VERSION=1.0.0 UNIVERSAL=1 ./scripts/bundle.sh
ditto -c -k --keepParent build/Dokr.app build/Dokr.zip
xcrun notarytool submit build/Dokr.zip --keychain-profile <profile> --wait
xcrun stapler staple build/Dokr.app
```

> Dokr must **not** be sandboxed (it writes the Dock's preferences and generates apps), so it can't ship on the Mac App Store. Use Developer ID + notarization.

## Layout

```
Sources/DokrCore/    Foundation-only: AppFolder model, persistent-apps sync, .icns writer (unit tested)
Sources/DokrKit/     AppKit helpers shared by both apps: app resolution/icons, folder icon renderer
Sources/Dokr/        Editor app: UI, folder .app generation, Dock prefs I/O
Sources/DokrFolder/  Helper inside each folder app: the popup grid
scripts/bundle.sh    SwiftPM build -> Dokr.app (with the helper) + codesign
scripts/make-dmg.sh  build/Dokr.app -> build/Dokr.dmg
scripts/make-icon.py Resources/Brand/logo-square.png -> Resources/AppIcon.icns (Pillow)
```

## Notes

- Running apps always get their own Dock icon as well; macOS has no public API to hide another app's Dock icon (only the app itself can, via `LSUIElement`, and editing its Info.plist breaks its signature).

- Removing a folder in Dokr deletes its generated app and its Dock tile on the next Apply. Apps hidden from the Dock by the toggle aren't re-added automatically.
- Dragging a folder tile out of the Dock by hand is fine; Dokr re-adds it on the next Apply if "Show in Dock" is on.

## Restore a Dock backup

```sh
B=~/Library/Application\ Support/Dokr/Backups/<persistent-apps-…>.plist
defaults export com.apple.dock /tmp/dock.plist
plutil -replace persistent-apps -xml "$(cat "$B")" /tmp/dock.plist
defaults import com.apple.dock /tmp/dock.plist && killall Dock
```

---

Made by [Seif Essam](https://seifessam.com).
