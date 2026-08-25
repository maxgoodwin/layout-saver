# app-snap

A tiny macOS menu bar app that saves the arrangement of your open windows —
across however many monitors you have connected — and restores it later, either
with one click or (in a future release) automatically when it detects you've
switched monitor setups.

Built for the "different monitors at home vs. the office" problem: save one
layout for each setup, and app-snap remembers which layout goes with which set
of physical displays.

## Features

- Saves position + size of every open window, across all connected displays.
- Ties each saved layout to the specific set of monitors it was captured on
  (detected via each display's persistent hardware identity), so home and
  office layouts don't clash.
- Applies a saved layout with one click from the menu bar. Apps that aren't
  currently running are skipped rather than launched.
- No Dock icon, no window chrome — just a menu bar item, plus a small window
  for managing saved layouts.

Auto-apply-on-monitor-change (no click required) is planned but not in this
release yet — see [Roadmap](#roadmap).

## Install

There are two ways to run app-snap, depending on whether you want it as a
normal double-clickable, Spotlight-searchable app, or as a background CLI
service.

### As an app (Spotlight-searchable, recommended for everyday use)

Build it from source and let the bundling script assemble a real `App
Snap.app` and install it to `~/Applications`:

```sh
git clone https://github.com/maxgoodwin/app-snap
cd app-snap
Scripts/build-app.sh
```

After that, **App Snap** shows up in Spotlight (⌘Space → type "App Snap") and
Launchpad like any other app — launch it from there, or `open -a "App Snap"`.
Re-run `Scripts/build-app.sh` any time you pull new changes to rebuild and
reinstall it.

This is a personal/from-source build for now — no notarized release download
exists yet (see [Roadmap](#roadmap)), so macOS won't complain about an
unidentified developer since it never left your machine, but it is only
ad-hoc signed, not signed with a Developer ID.

### As a background service (Homebrew)

```sh
brew tap maxgoodwin/app-snap
brew install app-snap
brew services start app-snap   # keeps it running across logins
```

To stop it: `brew services stop app-snap`.

This path installs the bare `app-snap` binary as a `brew services`-managed
background process — it won't appear in Spotlight or Launchpad, since it's
not an app bundle. Use this if you just want it always running headlessly;
use the app bundle above if you want to launch/quit it like a normal app.

You can also just run `app-snap` directly (e.g. from Terminal) without
`brew services` — it'll run until you quit it from the menu bar or close the
terminal.

### Grant Accessibility access

app-snap needs to read and move other apps' windows, which macOS gates behind
the **Accessibility** permission. On first launch, click the menu bar icon →
**Grant Accessibility Access…**, then enable App Snap in the System Settings
pane that opens (Privacy & Security → Accessibility).

The app bundle is only ad-hoc signed (no Developer ID certificate yet), so
its signature isn't guaranteed stable across rebuilds — rebuilding with
`Scripts/build-app.sh` and reinstalling may occasionally require re-granting
Accessibility access. A signed, notarized release (see
[Roadmap](#roadmap)) will fix this permanently. The Homebrew CLI path has the
same caveat, since it's also unsigned.

## Usage

Click the menu bar icon (three stacked rectangles) to:

- **Save Current Layout…** — captures every open app window's position and
  size on your current monitor setup, and asks you to name it.
- **Apply Layout** — a submenu of your saved layouts, with ones matching your
  *current* monitor setup listed first.
- **Update Layout** — same submenu, but overwrites the chosen saved layout
  with your current window arrangement (asks for confirmation first) instead
  of creating a new one. Use this after you've saved a layout and then
  rearranged things you want to keep.
- **Manage Layouts…** — opens a window listing all saved layouts, where you
  can update (overwrite in place) or delete ones you no longer need.

CLI flags:

```
app-snap --version
app-snap --help
```

## How it works

Window positions and sizes are read and written via the macOS Accessibility
API (`AXUIElement`), the same mechanism tools like Rectangle use. Each
connected display's stable hardware UUID (`CGDisplayCreateUUIDFromDisplayID`)
is combined into an order-independent "fingerprint" of your current monitor
set, which is what a saved layout is matched against — so it doesn't matter
which cable/port an external monitor is plugged into, only *which* monitors
are connected.

Layouts are stored as JSON in `~/Library/Application Support/app-snap/`.

## Building from source

```sh
git clone https://github.com/maxgoodwin/app-snap
cd app-snap
swift build -c release
.build/release/app-snap
```

Requires macOS 14+ and the Swift 5.9+ toolchain (Xcode or Command Line Tools).

## Roadmap

- Automatically apply the matching layout when a known monitor setup is
  detected (connect/disconnect), instead of requiring a menu click.
- Developer ID signed, notarized `.app` release (downloadable, and eventually
  a Homebrew Cask) for a stable Accessibility grant that survives upgrades,
  and Gatekeeper-clean downloads.
- Mac App Store distribution (pending a sandboxing feasibility check —
  App Sandbox and cross-app window control don't always mix cleanly).

## Contributing

Issues and PRs welcome — this is a small, single-purpose tool, so please keep
changes focused. Run `swift build` before opening a PR; CI runs the same build
plus a version smoke test on macOS.

## License

[GPL-3.0-or-later](LICENSE)
