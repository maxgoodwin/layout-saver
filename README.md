# layout-saver

A tiny macOS menu bar app that saves the arrangement of your open windows —
across however many monitors you have connected — and restores it later,
either with one click or automatically as soon as it detects you've switched
to a monitor setup you've saved a layout for.

Built for the "different monitors at home vs. the office" problem: save one
layout for each setup, and layout-saver remembers which layout goes with which set
of physical displays — then applies it the moment it sees that set connected
again.

## Features

- Saves position + size of every open window, across all connected displays.
- Ties each saved layout to the specific set of monitors it was captured on
  (detected via each display's persistent hardware identity), so home and
  office layouts don't clash.
- Applies a saved layout with one click from the menu bar. Apps that aren't
  currently running are skipped rather than launched.
- **Auto-applies** the matching saved layout as soon as it detects your
  connected monitor set has changed to one you've saved — no click needed.
  Toggle this on/off from the menu (on by default).
- **Default layout per monitor setup** — if you've saved more than one
  layout for the same set of monitors, mark one as the default so auto-apply
  (and the menu) always prefer it.
- **Optionally launches missing apps** when applying a layout, per layout,
  instead of just skipping windows for apps that aren't running.
- **Launch at Login**, so layout-saver (and auto-apply) are ready from boot.
- **Undo Last Apply** and a global shortcut (⌃⌥⌘L) to apply the matching
  layout on demand, independent of the auto-apply trigger.
- Menu bar icon itself shows whether the current setup has a saved layout,
  without needing to open the menu.
- Rename, duplicate, and delete saved layouts from the Manage Layouts window.
- No Dock icon, no window chrome — just a menu bar item, plus a small window
  for managing saved layouts.

## Install

There are two ways to run layout-saver, depending on whether you want it as a
normal double-clickable, Spotlight-searchable app, or as a background CLI
service.

### As an app (Spotlight-searchable, recommended for everyday use)

Build it from source and let the bundling script assemble a real `App
Snap.app` and install it to `~/Applications`:

```sh
git clone https://github.com/maxgoodwin/layout-saver
cd layout-saver
Scripts/build-app.sh
```

After that, **Layout Saver** shows up in Spotlight (⌘Space → type "Layout Saver") and
Launchpad like any other app — launch it from there, or `open -a "Layout Saver"`.
Re-run `Scripts/build-app.sh` any time you pull new changes to rebuild and
reinstall it.

This is a personal/from-source build for now — no notarized release download
exists yet (see [Roadmap](#roadmap)), so macOS won't complain about an
unidentified developer since it never left your machine, but it is only
ad-hoc signed, not signed with a Developer ID.

### As a background service (Homebrew)

```sh
brew tap maxgoodwin/layout-saver
brew install layout-saver
brew services start layout-saver   # keeps it running across logins
```

To stop it: `brew services stop layout-saver`.

This path installs the bare `layout-saver` binary as a `brew services`-managed
background process — it won't appear in Spotlight or Launchpad, since it's
not an app bundle. Use this if you just want it always running headlessly;
use the app bundle above if you want to launch/quit it like a normal app.

You can also just run `layout-saver` directly (e.g. from Terminal) without
`brew services` — it'll run until you quit it from the menu bar or close the
terminal.

### Grant Accessibility access

layout-saver needs to read and move other apps' windows, which macOS gates behind
the **Accessibility** permission. On first launch, click the menu bar icon →
**Grant Accessibility Access…**, then enable Layout Saver in the System Settings
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
- **Set Default Layout** — submenu to mark which layout should be preferred
  when several saved layouts share the same monitor fingerprint (used by
  auto-apply, the global shortcut, and the "matches current setup" grouping
  in Apply/Update). At most one default per fingerprint; picking a new one
  clears the old.
- **Launch Missing Apps When Applying** — submenu of per-layout toggles. Off
  by default (apps that aren't running are just skipped); turn it on for a
  layout to have applying it also launch those apps, positioning their
  windows once they're up (bounded to an 8s wait per app).
- **Manage Layouts…** — opens a window listing all saved layouts, where you
  can rename, duplicate, update (overwrite in place), toggle default/launch-
  missing-apps, or delete any of them.
- **Auto-Apply on Monitor Change** — checkable toggle; on by default. When
  on, layout-saver watches for display connect/disconnect events and, once the
  new setup settles, automatically applies the matching saved layout
  (preferring its default if one's set, then whichever was most recently
  applied/updated), briefly showing a status-bar message rather than a modal
  alert so it doesn't interrupt you.
- **Launch at Login** — checkable toggle; registers layout-saver to start
  automatically at login via `SMAppService`. Only shown when running as the
  proper `.app` bundle.
- **Undo Last Apply** — reverts to how windows were arranged immediately
  before the most recent apply (manual, shortcut, or auto). Only available
  for the current session; nothing is persisted for undo across relaunches.
- **Apply Matching Layout Now** — applies whichever saved layout matches the
  current monitor setup right now, also bound to the global shortcut
  **⌃⌥⌘L** (works even when layout-saver isn't the active app).

CLI flags:

```
layout-saver --version
layout-saver --help
```

## How it works

Window positions and sizes are read and written via the macOS Accessibility
API (`AXUIElement`), the same mechanism tools like Rectangle use. Each
connected display's stable hardware UUID (`CGDisplayCreateUUIDFromDisplayID`)
is combined into an order-independent "fingerprint" of your current monitor
set, which is what a saved layout is matched against — so it doesn't matter
which cable/port an external monitor is plugged into, only *which* monitors
are connected.

Layouts are stored as JSON in `~/Library/Application Support/layout-saver/`.

## Building from source

```sh
git clone https://github.com/maxgoodwin/layout-saver
cd layout-saver
swift build -c release
.build/release/layout-saver
```

Requires macOS 14+ and the Swift 5.9+ toolchain (Xcode or Command Line Tools).

## Roadmap

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
