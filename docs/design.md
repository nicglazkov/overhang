# Overhang, a menu bar overflow manager

**Date:** 2026-07-31
**Target:** MacBook Pro 14" (MacBookPro18,4), macOS 15.6.1, notched display

## Problem

The menu bar right of the notch is 790pt wide. Sixteen status items occupy 752pt of it.
An overflowing item is allocated a slot, measured at x=1001 to 1039, and then never composited by
WindowServer, it is silently dropped, with no affordance to reach it.

Measured geometry (`NSScreen.main`, scaled 1800×1169):

| Region | Range | Width |
|---|---|---|
| `auxiliaryTopLeftArea` | 0 → 790 | 790pt (app menus) |
| notch | 790 → 1010 | 220pt (dead) |
| `auxiliaryTopRightArea` | 1010 → 1800 | 790pt (status items) |

## Goal

A single always-visible control at the rightmost slot a third-party item can hold. Clicking it
reveals every status item macOS has culled, each identified by owning app, and lets the user
act on it. No TCC permissions.

## Non-goals

- Rendering other apps' status-item glyphs. That requires Screen Recording; we draw the owning
  app's bundle icon instead.
- Reordering other apps' items. Not possible without private API.
- A second menu bar. Rejected during design.

## Validated mechanisms

All four were confirmed empirically on macOS 15.6.1 before this spec was written.

1. **Permission-free enumeration.** `CGWindowListCopyWindowInfo` at
   `CGWindowLevelForKey(.statusWindow)` (= 25) returns owner PID, owner name, bounds, and
   on-screen flag for every status item. Window *titles* are TCC-gated; none of these fields are.
   `NSRunningApplication(processIdentifier:).icon` supplies the icon, also ungated.

2. **Culled items remain discoverable.** `.optionOnScreenOnly` returns 16 items;
   `.optionAll` returns 20 and includes `JetBrains Toolbox@1001 onscreen=N`. This is the only way to
   learn that a dropped item exists.

3. **Preferred-position placement.** Writing
   `NSStatusItem Preferred Position <autosaveName>` to `UserDefaults` before creating the item
   places it at the rightmost third-party slot (~x=1562), immediately left of Control Center.
   System items (Control Center, Clock, Spotlight) cannot be displaced.

   The value is measured **from the right edge, smaller sorts further right.** This is the
   opposite of the intuitive reading and was found the hard way: chevron=998 / spacer=997 put the
   spacer on the right, so growing it dragged the chevron leftward instead of leaving it
   anchored. Correct assignment is chevron=997, spacer=998.

4. **Geometric hiding.** Growing a status item's `length` shifts the third-party run leftward;
   items crossing the notch boundary are culled by WindowServer. Fully reversible, instant,
   no permission.

   | spacer length | items on screen | chevron |
   |---|---|---|
   | 20 (baseline) | 16 | visible @1520 |
   | 120 | 13 | visible @1420 |
   | 250 | 11 | visible @1290 |
   | 400 | 7 | visible @1140 |
   | 10000 | 2 | **lost** |

   **Length must be computed, never hardcoded.** Values approaching the width of the visible
   group push the app's own chevron off-screen. 10000 displaces the entire run.

## Architecture

Three units, each independently testable.

### `StatusItemScanner`
Pure read. Wraps `CGWindowListCopyWindowInfo` and returns `[MenuBarItem]`
(`windowNumber`, `pid`, `ownerName`, `frame`, `isOnscreen`). No state, no side effects.

Classification of a *casualty* (an item the user has lost access to):
- `isOnscreen == false`, **and**
- its frame does not intersect any on-screen item's frame, **and**
- it is not owned by this process, **and**
- `frame.minX > 0`

The intersection test is load-bearing. Control Center reports stale offscreen windows for
modules the user disabled (observed at x=1350 and x=1479, overlapping live items). Without the
test they appear as phantom casualties. `TextInputMenuAgent@0` is excluded by the `minX > 0` rule.

### `BarController`
Owns two `NSStatusItem`s and all mutation.
- **chevron**, rightmost slot, opens the menu.
- **spacer**, empty, its `length` is the hiding mechanism.

Recomputes on `NSApplication.didChangeScreenParametersNotification` and on menu open.
Notch boundary is read from `NSScreen.auxiliaryTopRightArea.minX`, never hardcoded.

Safety clamp: spacer length may never exceed `visibleGroupWidth - chevronWidth - margin`,
enforced against a live scan. This is what prevents the 10000 failure mode.

### `OverhangMenu`
`NSMenu` built on demand via `menuNeedsUpdate`. One row per casualty: owning app's icon at
16×16 plus its name. Selecting a row calls `NSRunningApplication.activate()`.

Plus: `Hide more` / `Hide less` (±50pt on the spacer), `Show everything`, `Quit`.

An auto-fit command was considered and dropped. There is no objectively correct hide count, hiding items to rescue one just makes different items casualties instead. Which ones the
user is willing to lose is a preference, not something the app can derive, so v1 exposes the
control and stays out of it.

## v2, click-through (2026-08-01)

Goal: clicking a row behaves as though the real status item had been clicked.

### Findings

There is **no zero-permission way** to press another app's status item. Apple Events only work
where the app implements them; posting mouse events cross-process is gated. Accessibility is the
floor for any programmatic activation.

`AXPress` **works on culled items with no reveal step**, the assumption that we would have to
slide an item back on screen first was wrong. Pressing a culled item while it sat under the notch
opened its menu at (948, 44): horizontally beneath the notch, vertically below it, fully usable.

`AXPress` **coverage is partial, and this is architectural, not positional.** A popover-based client ignored
it while fully visible at x=1071, that item consumes the mouse event itself rather than routing
through a button action. Popover-based items are likely all in this class. Measured:

| Item | `AXPress` result |
|---|---|
| A menu-backed item | NSMenu, 15 items |
| A culled menu-backed item | NSMenu, 2 items, menu at (948, 44) |
| A popover-backed item (visible) | nothing |

A full per-item survey was not run, it flashes each menu open, which was too intrusive at the
time. The design deliberately does not need it: coverage is discovered per item at click time.

### Design

`Activator` presses via `AXExtrasMenuBar` → children → `kAXPressAction`, matching the right child
by nearest horizontal centre when an app owns several (Stats owns four). It never assumes the
press worked: it polls up to 640ms for an `AXMenu` child or a new on-screen window >60×40 for
that pid, and reports `.opened` or `.failed`.

On `.failed`, untrusted, or an item that ignores `AXPress`, `BarController.temporarilyReveal`
puts the item back on screen for 8 seconds so it can be clicked by hand, and the owning app is
activated so something visibly happens either way. If collapsing the spacer is not enough
(the bar was already full at spacer 0), the app surrenders its own chevron width too and
restores it on the timer.

**Accessibility is opt-in and never prompted for automatically.** The menu offers
`Enable click-through…`; until then every row takes the reveal path. Zero-permission operation
remains a supported mode, not a degraded one.

### Signing

Ad-hoc signing was replaced with the Apple Development identity (team `M7D6YHVDNK`). Accessibility
grants bind to the code signature, and an ad-hoc signature changes hash every build, macOS would
revoke the grant and re-prompt after each rebuild. The app is installed to `/Applications/Overhang.app`
so its path is stable too.

## Known limits (v1)

- **Headless items do nothing when clicked.** Stats and similar have no window;
  `activate()` is a no-op for them. Pressing their real status item needs
  `AXUIElementPerformAction`, which requires Accessibility. Deferred to v2 by explicit decision, v1 ships with zero permissions and we assess whether this is annoying in practice.
- **The spacer's width is a visible gap.** Auto-placement puts both items at the right end, so
  the gap falls between the chevron and Control Center. Moving the spacer to the left edge of the
  keep-group (gap next to the notch, where it reads as margin) requires a one-time ⌘-drag;
  position then persists via `autosaveName`. Attempts to drive an item to a specific middle
  position via preferred-position values did not work, both items landed adjacent at the right.
- **Adding the chevron evicts one item.** The bar is exactly full; a 28pt item costs one
  existing slot. That item becomes a casualty and therefore appears in the menu, so it stays
  reachable, but the count of *visible* icons drops by one until the spacer is tuned.

## Testing

- `StatusItemScanner` against recorded `CGWindowListCopyWindowInfo` fixtures: a known-good bar,
  a bar with a culled item, and a bar with Control Center phantoms.
- Clamp arithmetic in `BarController` as pure functions over synthetic geometry, no live bar
  needed for the case that matters (rejecting a length that would eat the chevron).
- Manual: launch, confirm the culled item appears in the menu, confirm `Hide more`/`Hide less` are
  reversible, confirm the chevron never disappears.

## v0.5, the hide feature removed (2026-08-02)

The spacer and everything built on it, Hide more and Hide less, the settings slider, and the
SpacerClamp, are gone. The feature was a holdover from when this was going to be a menu bar
manager; the shipped product is a recovery tool, and growing the spacer only ever created more
casualties, never fewer. It also left a permanent artifact: even at length 1, NSStatusItem
reserves about 17pt, so an idle spacer sat in the bar as a blank clickable item.

The app now owns exactly one status item, the chevron. The reveal fallback surrenders the
chevron's own width for eight seconds, which frees one slot; items deeper in the hidden run
are reachable through the menu and click-through as before.

## v0.5.3, the reveal fallback removed (2026-08-02)

A field bug traced every "macOS squeeze" symptom back to our own code. Clicking a hidden item
whose menu opened slowly made `Activator` misjudge the press as failed after its 640ms poll, so
`temporarilyReveal` fired on top of a working click-through: chevron length to zero, the whole
run sliding 22pt right into the freed space, the target item peeking out from under the notch,
a dead 16pt padding stub where the chevron was, and an exactly 8 second recovery, our timer.
Instrumented builds showed clicks arriving at the stub and being swallowed by the zero length
button, and showed the earlier "fixed macOS timer" theory to be this app looking at itself.

The reveal is gone. Shrinking the chevron can free at most 22pt, which reveals nothing, so the
fallback is now simply activating the owning app. The success poll is 1.6 seconds with early
exit, which catches slow menus and makes the fallback rare. The left anchored glyph from
0.5.2, a mitigation for a squeeze that no longer exists, is reverted.
