# MacTuak

A native macOS app for running Windows applications on your Mac, powered by [Wine](https://www.winehq.org). Add a Windows `.exe` by drag-and-drop, double-click to run, and manage everything from a clean SwiftUI library — no terminal required.

![MacTuak](docs/preview.png)

## Install

1. Download **MacTuak.dmg** from the [latest release](https://github.com/moerdowo/MacTuak/releases/latest).
2. Open the DMG and drag **MacTuak** into your **Applications** folder.

### Opening a non-notarized app

MacTuak is **not notarized by Apple**, so Gatekeeper blocks it on first launch. This is expected — pick one of these (one-time):

- **Right-click to open:** in Applications, Control-click (right-click) **MacTuak** → **Open** → **Open**.
- **If macOS still blocks it** (Sequoia/Tahoe): open **System Settings → Privacy & Security**, scroll to the *"MacTuak was blocked"* message, click **Open Anyway**, then launch it again.
- **Or via Terminal** — remove the quarantine flag, then open normally:
  ```bash
  xattr -dr com.apple.quarantine /Applications/MacTuak.app
  ```

After the first successful launch, MacTuak opens normally like any other app. (Prefer to skip all this? Build it yourself — see [Build & run](#build--run) — locally built apps aren't quarantined.)

## Features

- **App library** — add Windows apps by dragging a `.exe`/folder anywhere into the window, the **Add App** button, or by scanning a bottle's Program Files. Double-click to run.
- **Bundled, self-updating Wine** — on first launch MacTuak downloads the latest **stable** Wine build into its support folder and checks for newer builds on every open. Choose the stable / staging / devel channel in Tweaks. No separate Wine install needed.
- **Wine bottles** — create, rename, and delete isolated prefixes; pick the Windows version (7/10/11) and architecture (32/64-bit); run `winecfg`, `regedit`, the Control Panel, open the C: drive, initialize/repair, or reset.
- **winetricks** — one-click install of common runtime components (DXVK, VKD3D, Visual C++ runtimes, .NET, core fonts, …). The required `cabextract` and `7-Zip` helpers are **bundled** in the app (no Homebrew needed).
- **Per-app launch options** — arguments, working directory, environment variables, `WINEDEBUG`, esync, Retina/HiDPI, and a virtual desktop size.
- **Custom & extracted icons** — pick your own image, or let MacTuak pull the real icon straight out of the `.exe` (it also auto-detects x86/x64).
- **Add to Applications** — export a standalone double-clickable launcher to `~/Applications`.
- **Quality of life** — favorites, categories, search, grid/list views, sorting, live launch console with log saving, accurate running state, uninstall with undo, light/dark themes, and notifications.

## Requirements

- macOS 26 (Tahoe) or later
- Apple Silicon or Intel Mac

## Build & run

MacTuak is a Swift Package. To build a double-clickable app:

```bash
git clone https://github.com/moerdowo/MacTuak.git
cd MacTuak
./bundle.sh          # builds MacTuak.app
open MacTuak.app
```

Or run directly during development:

```bash
swift run
```

## How it works

MacTuak keeps everything under `~/Library/Application Support/MacTuak`:

- `Wine/` — the managed Wine runtime (`installed.json` records the version/channel)
- `Bottles/<id>/` — each bottle's `WINEPREFIX`
- `Icons/`, `Logs/`, `library.json` — app icons, launch logs, and the library

Apps run as a normal `wine` process inside their bottle's prefix; MacTuak watches `wineserver` to track when the real window actually closes.

## Licensing & acknowledgements

MacTuak runs apps using **Wine**, which is licensed under the **GNU LGPL v2.1 or later**. The full license texts, attributions, and source-code offer ship with the app (Tweaks → About → *Licenses & acknowledgements*) and live in [`licenses/`](licenses/).

- **Wine** — © the Wine project authors, LGPL-2.1-or-later — https://gitlab.winehq.org/wine/wine
- **Wine macOS builds** — [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds)
- **winetricks** — LGPL-2.1 — https://github.com/Winetricks/winetricks

MacTuak does **not** bundle or redistribute Microsoft components. winetricks downloads any Microsoft redistributables on demand, on your machine, under their own license terms.

> "Wine" is a trademark of the Wine project. MacTuak is an independent project and is not affiliated with or endorsed by the Wine project or CodeWeavers.
