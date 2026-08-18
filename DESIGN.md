# Zhuoyue Browser Design System

## 1. Atmosphere & Identity

The browser is a quiet paper-like surface: generous empty space, restrained chrome,
and muted ink-green accents. The signature is progressive disclosure with a visible
escape hatch for every primary browser task; gestures may accelerate a workflow but
must not be the only way to discover it.

## 2. Color

| Role | Token | Light | Dark | Usage |
|------|-------|-------|------|-------|
| Page | `app.color.page_background` | `#FAF9F7` | `#131311` | Start page and tab overview |
| Panel | `app.color.surface_panel` | `#FFFFFF` | `#1D1D1A` | Capsules, cards, sheets |
| Subtle surface | `app.color.surface_subtle` | `#F1EFEA` | `#26251F` | Placeholders and secondary areas |
| Primary text | `app.color.text_primary` | `#1A1A18` | `#F5F3EE` | Headings and actions |
| Secondary text | `app.color.text_secondary` | `#8B877F` | `#8B877F` | Hints and metadata |
| Border | `app.color.border` | `#E5E2DB` | `#26251F` | Component boundaries |
| Accent | `app.color.accent` | `#2E6B5C` | `#2E6B5C` | Progress and selected state |
| Strong accent | `app.color.accent_strong` | `#2E6B5C` | `#84A794` | Small icons and visible controls |
| Website body | `site.color.body` | `#55534F` | — | Long-form landing page copy |
| Website muted | `site.color.muted` | `#706D67` | — | Secondary landing page metadata |
| Website dark secondary | `site.color.on_dark_muted` | `#C7C4BD` | — | Secondary text on the landing page dark surface |

Accent is reserved for interactive or selected states. New UI must use resource
tokens rather than inline colors.

## 3. Typography

The app uses the Harmony system sans-serif family. The existing scale is compact
and operational: 30sp display greeting, 20sp sheet titles, 14-16sp body controls,
and 11-13sp metadata. Numeric counters use tabular figures where supported.

## 4. Spacing & Layout

Spacing follows a 4vp rhythm. Existing surfaces use 8, 12, 16, 20, 24, 32, 40,
and 46vp values for control gaps, card padding, and safe bottom margins. Full-width
content is used for browsing; floating controls keep a 24vp side margin and the web
viewport reserves a 96vp bottom inset so the dock never obscures live page content.

## 5. Components

### Tab launcher

- **Structure**: floating panel with tabs icon, numeric count, and the explicit
  `N 个标签页` label.
- **Variants**: one or multiple open tabs; light and dark themes.
- **Spacing**: 42vp control height, 14vp horizontal padding, 8vp icon-to-label gap.
- **States**: default, pressed by the system, and hidden while a modal sheet is open.
- **Accessibility**: visible Chinese label explains the action; the entire panel is
  one tappable target with a stable `tab-launcher` id for UI automation.
- **Motion**: no decorative motion; the tab overview owns its 200ms opacity entry.

### Tab overview

- **Structure**: count header, close-all action, two-column tab cards, and a labeled
  `新建标签页` action.
- **Variants**: active card, inactive card, private card, and empty snapshot placeholder.
- **States**: select, close, close-all, new tab, and long-press new private tab.
- **Motion**: 200ms opacity transition when entering or leaving the overview.

### Recent tabs dock

- **Structure**: a bottom sheet with the active tab, up to four recently used tabs
  from the same privacy mode, a compact new-tab tile, and an explicit path to the
  complete overview.
- **Entry**: long-press the tab counter. A normal tap continues to open the complete
  overview, so the gesture is an accelerator rather than the only path.
- **States**: active tab, recent tab, private working set, horizontal overflow, and
  background-tap dismissal.
- **Spacing**: 112vp tab cards in a horizontal list; the panel is capped at 560vp on
  larger windows and remains edge-to-edge on phones.
- **Motion**: 180ms opacity entry; no decorative card motion.

### Address-bar tab indicator

- **Structure**: a compact row on the address capsule's lower edge; the active tab
  uses a short ink-green segment and neighboring tabs use muted dots.
- **Visibility**: shown only when horizontal tab switching is enabled and at least
  two tabs are open; a single tab never reserves indicator space.
- **Overflow**: at most five positions are visible, centered around the active tab
  where possible, so large sessions do not compete with the address text.
- **Motion**: state changes are immediate; the indicator explains the existing
  swipe gesture and does not add decorative animation.

### Wide browser menu

- **Structure**: a 440vp anchored panel below the right edge of the browser toolbar;
  page actions and browser destinations use dense two-column rows.
- **Visibility**: Medium, Expanded, and Desktop layouts use the anchored panel;
  Compact layouts retain the thumb-reachable bottom action sheet.
- **Surface**: shared panel, border, subtle-surface, accent, and shadow tokens only.
  Wide layouts do not dim or visually remove the tab strip and address toolbar.
- **Dismissal**: explicit close control and outside-tap dismissal; opening the menu
  closes an existing sidebar so the two right-edge surfaces never compete.

### Browser sidebar

- **Structure**: a persistent right pane for tabs, favorites, history, downloads,
  and blocking details on Medium and wider layouts.
- **Safe area**: the pane background may extend under system bars, but its navigation
  and close controls begin below the measured top inset.
- **Dismissal**: the close control is always visible, system Back closes the pane,
  and pressing the active toolbar entry toggles the pane closed. Opening a history
  entry also closes the pane — the destination is the page the pane is covering.
- **Continuity**: the history list's search text and scroll position survive the pane
  being closed, so returning from a visit resumes where the reader left off. The owner
  holds that state; the pane itself is unmounted while closed.

### Toolbar history entry

- **Placement**: between the multi-window control and the tools menu on Medium and
  wider layouts. Compact layouts keep history inside the tools menu, where the
  address row has no width to spare.
- **States**: default and active; the active tint uses accent over a subtle surface
  while the history panel is open, and a second press toggles the panel closed.
- **Behaviour**: identical to the menu's history entry — a sidebar on wide layouts,
  a full-screen sheet otherwise — so the button is an accelerator, not a second path.

### Desktop tab strip

- **Adjust mode**: a long press on a tab lifts it and outlines it in accent. A tap
  anywhere, Escape, or completing a drag leaves the mode; a tap never selects a tab
  while the mode is active, so the long press cannot be misread as "open this".
- **Dragging**: the lifted tab tracks the finger with no easing while the tabs it
  passes step aside one slot at a time over 160ms. A drop is committed on whole slots
  only, and is clamped to the run of tabs sharing the dragged tab's pinned and private
  state — pinned tabs keep the lead and private tabs never interleave.
- **Alternate route**: a horizontal swipe on a tab still nudges it one position
  without entering the mode, so reordering does not depend on finding the long press.

### Start-page shortcuts

- **Source order**: explicitly added shortcuts first, then user-saved bookmarks,
  followed by shipped preset sites. Browsing history is never promoted automatically;
  it only becomes a shortcut when the user selects it in the add dialog.
- **Deduplication**: one tile per host; hidden hosts remain excluded.
- **Icons**: the site's own highest-quality declared icon on a neutral card. Page
  metadata and high-resolution touch icons take precedence over the legacy root
  favicon; third-party favicon proxies are not used because they are unreliable from
  the mainland. Icons sit on a fixed rounded inner plate and square artwork receives
  the same corner treatment, so transparent, circular, and rectangular assets share
  one visual footprint. Results are cached on disk for a fortnight. A site with no
  usable icon, or a cached file that will not decode, falls back to the coloured
  letter tile — the tile never waits on the network.
- **Editing**: long-press enters a desktop-style edit state with close controls,
  restrained wiggle feedback, and drag sorting. Removal hides the shortcut without
  deleting the underlying bookmark or history entry.
- **Wide layout**: tile glyphs are 30% larger while the compact Phone size remains
  unchanged. The add action opens a constrained dialog on wide windows and a bottom
  sheet on compact windows, with custom, bookmark, and history sources.

## 6. Motion & Interaction

Taps are the primary path for tabs, address entry, and actions. Existing gestures
remain as shortcuts: address-bar swipes switch tabs, action sheets escalate, and tab
cards can swipe left to close. A gesture must never be the only discoverable route
to a core browser task.

## 7. Depth & Surface

The surface strategy is mixed: tonal shifts establish hierarchy, while one-pixel
resource-token borders and soft shadows separate floating controls from content.
Capsules and tab cards use the shared panel, border, and shadow tokens so new chrome
does not introduce a competing material language.

## 8. Product Landing Page

The public website extends the in-app identity rather than introducing a separate
marketing theme. It uses the same warm paper, ink, border, and accent colors, with
the real browser UI as the hero material.

- **Canvas**: warm paper with white panels and ink-green focal surfaces.
- **Website-only material tokens**: `site.color.device_border` (`#3A3A35`),
  `site.color.device_frame` (`#0F100E`), and `site.color.device_shadow`
  (`#00000052`) are restricted to the product-stage device frame.
- **Typography**: HarmonyOS/system sans-serif; large, light display copy and compact
  operational body text. No remote fonts or negative tracking.
- **Layout**: a 4px spacing rhythm, 24px mobile gutters, and a 1200px content ceiling.
- **Product stage**: one real app screenshot inside a restrained device frame. It is
  the sole dimensional focal point; feature sections remain border-led and quiet.
- **Components**: site header, text link, primary link, product stage, feature card,
  privacy statement, and footer. Interactive states use color/border changes only.
- **Motion**: no decorative entrance or scroll animation. Respect reduced-motion
  preferences and animate only link affordances with opacity or transform.
- **Accessibility**: visible focus rings, 44px minimum primary targets, semantic
  landmarks, and WCAG AA text contrast at every size.
