<div align="center">
<img src="Branding/metr-icon-1024.png" width="128" alt="metr">

# metr

**Your AI, metered.**

A quiet native macOS utility for AI quota, reset windows, pace, and local activity.
</div>

## What it answers

In one glance: how much you have used, how much remains, when the window resets, whether your pace is safe, and which provider needs attention.

- **Side dock** hugs either screen edge and collapses to a 7pt usage rail.
- **Top bar** sits beneath the menu bar; the menu-bar glyph remains glanceable everywhere.
- **Both** keeps the side dock plus the menu-bar readout.
- Provider rows expand for source, context, cost assumptions, and exact reset detail.
- Weekly detail separates provider-reported limits from per-app local history for Claude Code and Codex.
- Overview, History, and Insights stay compact and only make claims supported by available data.

## Install

Download `metr-v0.1.0.dmg`, drag `metr.app` to Applications, then open it. This preview is ad-hoc signed rather than notarized, so another Mac may require right-click → Open once.

Build locally on macOS 13+ with Xcode Command Line Tools:

```bash
./build-app.sh
open metr.app
```

Run tests:

```bash
swift test
```

Create the Universal 2 DMG and ZIP:

```bash
./package-release.sh
```

## Data sources

| Provider | Usage and reset | Local activity | Confidence |
|---|---|---|---|
| Codex | `chatgpt.com/backend-api/wham/usage`, using the access token already stored in `~/.codex/auth.json` | `~/.codex/session_index.jsonl` | Provider quota measured; local fallback estimated |
| Claude Code | `api.anthropic.com/api/oauth/usage`, using Claude Code’s existing read-only OAuth credential | timestamps under `~/.claude/projects/` and `~/.claude/stats-cache.json` | Provider quota measured; local fallback estimated |

Credentials are sent only to their own provider endpoint. metr never refreshes, rewrites, stores, or uploads provider credentials. If an endpoint or credential is unavailable, metr says so or keeps an explicitly labelled local activity estimate; it never fabricates 0% usage.

## Privacy and timezone

metr is local-first and has no server or telemetry. The only external requests are the two provider usage endpoints above. Session transcript content is never read; only small indexes, timestamps, and provider-generated activity summaries are used.

Reset times use `TimeZone.autoupdatingCurrent` and follow macOS automatically. There is no GPS permission, city label, or timezone selector.

## Native behavior

- SwiftUI presentation with an AppKit non-activating panel
- Multiple Spaces/full-screen auxiliary behavior
- Magnetic edge snapping and persisted position
- System/Light/Dark appearance
- Reduce Motion support and semantic accessibility labels
- Launch at Login via `SMAppService`
- Deduplicated threshold notifications
- Efficient refresh timers with tolerance and local countdown updates

## Architecture

```text
Sources/MetrKit/   provider adapters, models, reset math, alerts, history logic
Sources/Metr/      SwiftUI views, glyph, AppKit panel and menu-bar lifecycle
Tests/             107 deterministic tests and provider response fixtures
```

Demo scenarios are available without touching real preferences:

```bash
METR_SCENARIO=atLimit METR_PREFS='{"dataSource":"mock","mode":"side"}' swift run metr
```

Scenarios: `healthy`, `approachingLimit`, `atLimit`, `mixed`, `offline`, `authRequired`, `stale`, `noData`.

## Known limitations

- This preview is not Developer ID signed or notarized because no valid signing identity is installed.
- Provider endpoints and credential formats are provider-controlled and may change.
- Claude’s usage endpoint can rate-limit; metr reports that state and retains honest local activity rather than inventing quota.
- Context budget is shown only when a trustworthy source supplies it.

MIT licensed. Interaction research includes [codex-island](https://github.com/ericjypark/codex-island); implementation and brand assets are original.
