# metr — product and UI plan

## What it is

A calm menu-bar companion that tells you how much of your AI usage window is
left, when it resets in your timezone, and whether it is safe to keep going.

**Name.** `metr`: the line showing how high the water reached. Tides also
carry the idea the app is built on — the level rises, then the window resets.

**Promise.** *Know your headroom.*

## Principles

1. **Never assert what it has not measured.** Every number is tagged Measured or
   Estimated, and every estimate prints its assumption beside it.
2. **Status three ways.** Symbol first, word second, colour third. The panel is
   readable in greyscale and by a screen reader.
3. **Quiet by default.** No badges, no streaks, no dashboard. One surface, one
   sentence at the top, detail underneath.
4. **The empty state is the honest state.** When there is nothing to say, say
   nothing and explain why — never fill the space with an invented metric.

## Presentation model

| State | What it is | When |
|-------|-----------|------|
| **Rail** | A 7pt capsule on the screen edge, filled to your usage level | Collapsed with auto-hide on |
| **Compact** | Header plus one chosen metric per provider and a status word | Collapsed |
| **Expanded** | Guidance headline, three tabs, footer controls | Open |
| **Setup** | Four real configuration steps, in the panel | First run |

Transitions animate the *window frame* around a fixed anchor — top-centre for
the island, the docked edge for the side rail — so expanding reads as the panel
growing from where it lives rather than jumping.

## Brand

| Token | Value | Use |
|-------|-------|-----|
| Charcoal | `#141414` | Icon tile, dither wash |
| Bone | `#F6F5F2` | Mark, water |
| Warm gray | `#E5E3DF` | Unknown state |
| Olive | `#7E8469` | Clear, context meter |
| Burnt orange | `#E07A3A` | Watch, active toggles |
| Deep red | `#C7493E` | Near limit |

The mark is a vessel with a tide line and two eyes. **The water level is the
usage level and the eyes change with severity**, so the mascot is a status
indicator rather than decoration — including in the menu bar, where a template
image cannot carry colour at all.

Surface is native material plus a 4×4 ordered-dither wash and a seeded film
grain, both static, giving a printed quality without a per-frame cost.

## Data model

```
UsageDataSource (protocol)
├── LocalActivityDataSource   provider quota plus local per-app history
└── MockUsageDataSource       8 deterministic scenarios, for demo and tests
                              ↓
                        UsageSnapshot
                    ┌─────────┼─────────┐
            ProviderSnapshot  SessionRecord  DailyActivity
```

`MetrKit` holds every model and rule and links no UI framework, so all of it
is testable headlessly. `Metr` is presentation only.

## Location model

Timezone-shaped on purpose. The app **never links CoreLocation**, so it cannot
request GPS or Wi-Fi positioning even by mistake.

- Display zone follows the system, or a manual override with an optional custom
  label (so `Asia/Kolkata` can read "Mumbai").
- Provider reset zones are modelled separately; the provider's time is shown
  only when its UTC offset differs from yours at that instant.
- Quiet hours, day boundaries, peak-hour insights, and history labels all
  evaluate in the display zone, so they travel with you.
- Privacy switch disables location context; "Clear stored location data" erases
  the identifier and label.

## Scope taken, and left

**Built.** Real local adapter, connection/staleness/auth/offline states, context
budget, reset countdowns with dual timezones, safe-to-continue guidance, cost and
burn rate with printed assumptions, alerts with thresholds and quiet hours, quick
actions, recent sessions, insights, provider filtering, configurable compact
metric, five-tab preferences, in-app setup, checklist, one-time hints, 101 tests.

**Deliberately not built.** Provider API integration (needs credentials and a
network layer this app does not have), a global hotkey (would need Accessibility
or Input Monitoring permission — too much for a usage meter), and a true
drag-resize handle (a width preference plus auto-height covers the need without
a borderless-window resize implementation).
