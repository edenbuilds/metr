# Changelog

## 0.5.3 — 2026-08-30

- Fixed cat logo resource lookup so the dock and menu bar render the supplied mark.

## 0.5.2 — 2026-08-30

- Fixed the hover crash by keeping rail window geometry stable while the preview animates.
- Added the Claude flower mark and cat-branded rail header.

## 0.5.1 — 2026-08-30

- Fixed Claude/Anthropic SVG rendering on macOS.
- Stabilized rail hover through preview re-layout and made the whole rail clickable.

## 0.5.0 — 2026-08-30

- Added a stable hover status card with Used / Remaining display preference.
- Added explicit rail drag handle and native drag-to-snap behavior.
- Replaced Claude Code/Codex marks with bundled Anthropic/OpenAI SVG marks from theSVG.
- Added the supplied cat mark as the adaptive metr brand logo and menu-bar glyph.
- Consolidated the menu bar around one always-on native status item.

## 0.4.7 — 2026-08-30

- Made the native menu-bar label text-backed with a visible drop glyph and metr name so it remains discoverable even when custom status-item artwork is elided by macOS.

## 0.4.6 — 2026-08-30

- Replaced the unreliable manual status item with a native `MenuBarExtra` scene so the metr glyph remains visible and accessible in the menu bar.
- Kept the floating panel actions available from the native menu-bar menu.

## 0.4.5 — 2026-08-30

- Made the menu-bar image load directly from the packaged `metr.icns` resource and added a visible `metr` fallback label.
- Added launch diagnostics for the menu-bar status-item lifecycle.

## 0.4.3 — 2026-08-30

- Fixed SVG rasterization source bounds so bundled provider marks render visibly in the dock and expanded panel.
- Made the menu-bar status item reserve a visible branded glyph slot with a compact metr label.

## 0.4.4 — 2026-08-30

- Fixed the packaged resource lookup for flattened Swift Package Manager SVG assets.

## 0.4.2 — 2026-08-30

- Rasterized bundled SVG marks into stable AppKit representations so provider logos remain visible in SwiftUI docks and cards across macOS releases and themes.
- Made the menu-bar item use the metr application mark when available, ensuring a visible branded glyph instead of an empty status slot.
- Added the Claude unified rate-limit-header fallback described by the CodeZeno monitor for accounts where the dedicated usage endpoint is unavailable.

## 0.4.1 — 2026-08-30

- Fixed provider SVG marks not appearing reliably by loading the bundled vector resources synchronously with a cache.
- Fixed hover detection by tracking the dock surface directly while the bounded quick-status card animates into place.
- Strengthened the custom menu-bar glyph and made its status item a fixed, always-visible 22-point slot.

## 0.4.0 — 2026-08-30

- Added a compact hover peek with the active usage percentage, reset countdown, weekly window, and a clear measured-versus-estimated label.
- Kept the metr menu-bar glyph permanently visible by default, with quiet refresh motion and critical-state attention pulses.
- Added an opt-in catalog of popular AI apps with bundled SVG marks; optional apps remain unavailable until they expose a trustworthy local or provider quota feed.
- Removed Cursor from the default provider surface while retaining it as an explicit optional app.
- Tightened side-dock geometry so the expanded view stays bounded and scrollable rather than filling the screen.
- Renamed the primary provider label to Claude and kept Claude activity history separate without exposing conversation wording in the main UI.

## 0.3.1 — 2026-08-30

- Fixed minimized-dock hover expanding the whole panel; expansion now happens only on click.
- Added clear Claude Code connection guidance and separated Claude conversation history in Detailed history.
- Improved adaptive SVG provider-mark contrast in compact and expanded views.

## 0.3.0 — 2026-08-30

- Tightened expanded geometry into a compact, bounded popover with a sleek scroll region.
- Made the side placement default to the right-top glance zone, preserving deliberate repositioning.
- Added bundled theSVG provider marks for Claude Code, Codex, and Cursor.
- Added Cursor as an honest, unavailable provider until a trustworthy quota source exists.
- Kept Claude Code limits primary while moving Claude conversations into Detailed history.
- Fixed hover-to-expand behavior and adapted provider marks to light/dark surfaces.

## 0.2.0 — 2026-08-30

- Replaced the minimized edge line with an adaptive side/top provider dock with ring meters, hover feedback, accessible actions, and spring motion.
- Added the `metr-statusline` helper for Claude Code’s official `rate_limits` statusLine payload, with ten-minute freshness expiry and atomic local writes.
- Added a safe Claude Code statusLine installer with timestamped settings backups.
- Added tests proving official Claude statusline data wins over local estimates and retains weekly limits.

## 0.1.0 — 2026-08-30

- Renamed the product and bundle to deliberately lowercase `metr`.
- Added provider-reported Codex and Claude quota/reset adapters with read-only credential discovery.
- Added provider-specific weekly detail, per-app local history, and simultaneous immediate/weekly limit windows.
- Added a quietly animated menu-bar meter that remains synchronized after every refresh.
- Increased adaptive contrast and added reduced-motion-aware hover feedback.
- Retained measured local session/history data and explicit estimated fallbacks.
- Added Side dock, Top bar, and Both placement choices.
- Removed normal timezone controls; reset times now follow macOS automatically.
- Added System, Light, and Dark appearance modes.
- Refined the compact provider hierarchy, edge rail, motion, glyph, onboarding, alerts, history, and insights.
- Added Universal 2 release packaging for DMG and ZIP distribution.
