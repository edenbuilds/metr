# Changelog

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
