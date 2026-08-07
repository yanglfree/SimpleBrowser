# Dolphin Browser Design System

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
