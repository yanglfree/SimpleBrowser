export const TAB_CONTROL_GAP: number = 8;
export const TAB_LAUNCHER_HEIGHT: number = 44;
export const TAB_LAUNCHER_HORIZONTAL_PADDING: number = 14;
export const TAB_LAUNCHER_RADIUS: number = 21;
export const TAB_LAUNCHER_ICON_SIZE: number = 18;
export const TAB_LAUNCHER_TEXT_SIZE: number = 12.5;
export const TAB_LAUNCHER_TOP_MARGIN: number = 18;
export const TAB_LAUNCHER_RIGHT_MARGIN: number = 24;
export const TAB_CLOSE_HIT_SIZE: number = 32;
export const TAB_CARD_CLOSE_ICON_SIZE: number = 13;
export const TAB_CARD_CLOSE_SWIPE_DISTANCE: number = 44;
export const TAB_CARD_RADIUS: number = 20;
export const TAB_CARD_TITLE_SIZE: number = 11;
export const TAB_CARD_HEADER_TOP: number = 8;
export const TAB_CARD_HEADER_HORIZONTAL: number = 8;
export const TAB_CARD_HEADER_BOTTOM: number = 6;
export const TAB_CARD_ACTIVE_BORDER: number = 1.5;
export const TAB_CARD_BORDER: number = 1;
export const TAB_CARD_SHADOW_RADIUS: number = 12;
export const TAB_CARD_SHADOW_OFFSET_Y: number = 2;
export const TAB_CARD_SWIPE_DISTANCE: number = 8;
export const TAB_CARD_SWITCH_SWIPE_DISTANCE: number = 56;
export const TAB_THUMB_HEIGHT: number = 172;
/** Header (top padding + one title line + bottom padding) plus the thumbnail. */
export const TAB_CARD_HEIGHT: number = 218;
export const TAB_OVERVIEW_TITLE_SIZE: number = 20;
export const TAB_OVERVIEW_ACTION_SIZE: number = 14;
export const TAB_OVERVIEW_HEADER_TOP: number = 22;
export const TAB_OVERVIEW_HEADER_HORIZONTAL: number = 24;
export const TAB_OVERVIEW_HEADER_BOTTOM: number = 18;
export const TAB_OVERVIEW_GRID_GAP: number = 16;
export const TAB_OVERVIEW_GRID_BOTTOM: number = 120;
export const TAB_NEW_BUTTON_ICON_SIZE: number = 20;
export const TAB_NEW_BUTTON_TEXT_SIZE: number = 14;
export const TAB_NEW_BUTTON_BOTTOM_MARGIN: number = 46;
export const TAB_PRIVATE_GESTURE_DURATION: number = 450;
export const TAB_NEW_BUTTON_HEIGHT: number = 52;
export const TAB_NEW_BUTTON_HORIZONTAL_PADDING: number = 20;
export const TAB_NEW_BUTTON_RADIUS: number = 26;

/** Recent-tab dock: a compact bridge between gesture switching and the full overview. */
export const RECENT_TABS_DOCK_RADIUS: number = 24;
export const RECENT_TABS_DOCK_MAX_WIDTH: number = 560;
export const RECENT_TABS_DOCK_SHADOW_RADIUS: number = 20;
export const RECENT_TABS_DOCK_SHADOW_OFFSET_Y: number = -2;
export const RECENT_TABS_DOCK_HORIZONTAL_PADDING: number = 16;
export const RECENT_TABS_DOCK_TOP_PADDING: number = 10;
export const RECENT_TABS_DOCK_BOTTOM_PADDING: number = 24;
export const RECENT_TABS_DOCK_SECTION_GAP: number = 14;
export const RECENT_TABS_DOCK_HEADER_SIZE: number = 16;
export const RECENT_TABS_DOCK_ACTION_SIZE: number = 13;
export const RECENT_TABS_DOCK_ACTION_VERTICAL_PADDING: number = 8;
export const RECENT_TABS_DOCK_ACTION_LEFT_PADDING: number = 10;
export const RECENT_TABS_DOCK_HANDLE_WIDTH: number = 36;
export const RECENT_TABS_DOCK_HANDLE_HEIGHT: number = 4;
export const RECENT_TABS_DOCK_LIST_HEIGHT: number = 76;
export const RECENT_TAB_CARD_WIDTH: number = 112;
export const RECENT_TAB_CARD_HEIGHT: number = 72;
export const RECENT_TAB_CARD_RADIUS: number = 16;
export const RECENT_TAB_CARD_TITLE_SIZE: number = 13;
export const RECENT_TAB_CARD_META_SIZE: number = 11;
export const RECENT_TAB_CARD_GAP: number = 10;
export const RECENT_TAB_CARD_CONTENT_GAP: number = 5;
export const RECENT_TAB_CARD_HORIZONTAL_PADDING: number = 12;
export const RECENT_TAB_ACTIVE_DOT_SIZE: number = 6;
export const RECENT_TAB_NEW_ICON_SIZE: number = 20;
export const RECENT_TAB_NEW_CONTENT_GAP: number = 6;
export const RECENT_TAB_LIMIT: number = 5;

/** Bottom dock: one 46vp row in a tightly-centred container. */
export const DOCK_ROW_HEIGHT: number = 46;
export const DOCK_SLOT_WIDTH: number = 40;
export const DOCK_ICON_SIZE: number = 28;
/** Outlined square holding the tab count, the way every mobile browser draws it. */
export const DOCK_BADGE_SIZE: number = 24;
export const DOCK_HEIGHT: number = 52;
export const DOCK_TAB_INDICATOR_LIMIT: number = 5;
export const DOCK_TAB_INDICATOR_ACTIVE_WIDTH: number = 12;
export const DOCK_TAB_INDICATOR_DOT_SIZE: number = 4;
export const DOCK_TAB_INDICATOR_GAP: number = 3;
export const DOCK_TAB_INDICATOR_BOTTOM_INSET: number = 4;
/** Scrolled-away state: a host-only pill, not an invisible strip. */
export const DOCK_COLLAPSED_PILL_HEIGHT: number = 30;
export const DOCK_COLLAPSED_HEIGHT: number = DOCK_COLLAPSED_PILL_HEIGHT;

/**
 * The page reserves only what the dock occupies at its smallest. When the dock is
 * pinned it reserves the full bar; when it auto-hides the expanded bar floats over
 * the last few vp of the page, the way Safari does, so nothing reflows on scroll.
 */
export const TAB_WEB_BOTTOM_INSET: number = DOCK_HEIGHT + 2;
export const TAB_WEB_BOTTOM_INSET_COMPACT: number = DOCK_COLLAPSED_HEIGHT + 2;
