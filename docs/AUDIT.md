# metr — audit of the Usage Pilot prototype

Audited by running the original build, not by reading it alone: it was compiled,
launched, and driven into each of its states with screenshots taken at every
step. Line references are to the original `Sources/UsagePilot/main.swift` (216
lines, single file).

## Strengths worth keeping

- **The core interaction idea is right.** An edge rail that blooms into a panel
  is a good answer for an always-on utility. It was kept and made physical.
- **Presentation was already separated from a `UsageStore`.** That seam is what
  made a real data layer cheap to add.
- **Restraint.** Native material, rounded geometry, no neon. The direction was
  sound; the execution had gaps.
- **Correct app class.** `LSUIElement` accessory app with a status item is the
  right shape for this product.

## Weaknesses found

### Correctness and honesty

| # | Finding | Evidence |
|---|---------|----------|
| 1 | **Every number was a literal.** Providers, percentages, `$1.84`, the 7-bar history, and the "2–5 pm" insight were all hardcoded. The app asserted facts it had never measured. | `providers` array; `Text("$1.84")`; `ForEach([0.33, 0.52, …])` |
| 2 | **Green "All clear" before any data existed.** The status was a constant, so the app claimed health it had not established. | `headline` returned a fixed string; `attentionCard` was always green |
| 3 | **Reset times were strings, not instants.** `"in 2h 18m"` never counted down and could not be wrong-but-fixable, only wrong. | `reset: "in 2h 18m"` |
| 4 | **No timezone anywhere.** A reset time with no zone is ambiguous for anyone who travels or whose provider resets in UTC. | absent |

### Interaction and window behaviour

| # | Finding | Evidence |
|---|---------|----------|
| 5 | **The panel was a fixed 388×590 in every state.** Collapsed, the card floated in the middle of a large invisible rectangle. Verified by screenshot: the compact card sat mid-screen, nowhere near an edge. | `positionPanel()` hardcoded `height: 590` |
| 6 | **"Side edge" was not an edge.** It placed a floating card 414pt from the right, vertically centred. | `visible.maxX - 414` |
| 7 | **`pinned` and `autoHide` did nothing.** Both toggles wrote to a property no code read. | `@Published var pinned` / `autoHide` |
| 8 | **The panel could never take keyboard focus.** A borderless `NSPanel` returns `false` from `canBecomeKey` by default, so no shortcut, tab order, or Esc could work. | no `canBecomeKey` override |
| 9 | **Single-screen only, and never re-laid out.** `NSScreen.main` at launch; no `didChangeScreenParametersNotification` observer. Unplugging a display left the panel off-screen. | `positionPanel()` |
| 10 | **Toggling a status-item window straight from target/action** is the pattern Apple's own AppKit-modernisation guidance flags as breaking keyboard navigation. | `@objc func togglePanel()` |

### Visual and accessibility

| # | Finding | Evidence |
|---|---------|----------|
| 11 | **Hardcoded white border.** `.stroke(.white.opacity(0.75))` rendered as a bright ring in dark mode — visible in the first screenshot taken. | `UsageView.body` |
| 12 | **No Dynamic Type.** Every font was `.system(size:)`, pinned in points, so the panel ignored the system text size entirely. | throughout |
| 13 | **Status by colour alone.** Provider dots were bare coloured circles with no symbol or word. | `compactContent`, `providerRow` |
| 14 | **No accessibility labels.** Meters had no value, buttons no label, the chart no description. | absent |
| 15 | **No reduced-motion path.** One spring, applied unconditionally. | `.animation(.spring(…))` |
| 16 | **Controls were invisible until hovered.** `QuietButtonStyle` drew no background at rest, so the pin and auto-hide buttons read as decoration. | `QuietButtonStyle` |

### Product gaps

Everything in the brief that did not exist at all: connection states, per-session
visibility, context budget, reset countdowns, safe-to-continue guidance, cost and
burn rate, alerts, quiet hours, quick actions, session history, insights,
provider filtering, configurable compact metrics, any preferences surface, and
offline / stale / unavailable / auth-required states. The `Settings` scene was
`EmptyView()`.

There was also **no onboarding of any kind** and **no tests** (the package had no
test target and no library target that could have been tested).

## Highest-impact opportunities, in the order they were taken

1. **Make the numbers real or say they are not.** Split measured from estimated
   and print the assumption next to every estimate.
2. **Make the window behave like a window.** Size to content, dock to a real
   edge, survive display changes, accept keyboard focus.
3. **Say status three ways.** Symbol, word, colour — in that order of priority.
4. **Give reset times a timezone**, and show the provider's too when it differs.
5. **Make it configurable and teachable** — preferences plus in-app setup.

## Bugs found while building, and fixed

- **Foundation reports legacy timezone aliases.** `TimeZone.knownTimeZoneIdentifiers`
  contains `Asia/Calcutta`, not `Asia/Kolkata`; `Europe/Kiev`, not `Europe/Kyiv`.
  The picker would have offered an Indian user "Calcutta". Now modernised for
  display, with the old spelling still searchable. Caught by a test.
- **Synthesised `Codable` requires every key.** Adding one preference in a future
  version would have made every existing preferences file fail to decode and
  silently reset all settings. Now decoded field-by-field with defaults.
- **Auto-hide on `windowDidResignKey` was too aggressive.** A non-activating
  panel loses key focus constantly, so the panel collapsed the moment you clicked
  back into your editor. Now a 2.5s debounce that cancels if the pointer is over
  the panel.
