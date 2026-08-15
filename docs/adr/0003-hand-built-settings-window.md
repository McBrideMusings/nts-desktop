# Build the settings window by hand, not with SwiftUI's `Settings` scene

Date: 2026-08-15

## Context

The app is an `.accessory` agent whenever "Show in Dock" is off, so there is
no app menu for the `Settings` scene to hang off, and `openSettings()`
reports success and creates no window.

## Decision

Don't use SwiftUI's `Settings` scene. Settings and the account are the two
panes of one real window (`SettingsWindowController` + `SettingsView`),
hand-built instead. The `NTSRadioApp` declaration stays an `EmptyView`
placeholder because an `App` must declare one.

## Consequences

Three further rules follow from building the window by hand rather than
inheriting AppKit's scene machinery:

- The tabs are an `NSToolbar` with `toolbarStyle = .preference`, not a
  SwiftUI `TabView`, whose `.tabItem`s draw a small segmented picker rather
  than the icon-and-label toolbar every Mac preferences window has.
- Use one hosted view whose pane changes (`SettingsSelection`), never a
  swapped `contentViewController`, which makes AppKit size the window to the
  incoming view first.
- Never resize that window by hand — set `NSHostingController.sizingOptions
  = [.preferredContentSize]` and let AppKit do it, because `setContentSize`
  keeps the bottom-left corner (AppKit's origin) and walks the window up the
  screen on every switch to a taller pane.
