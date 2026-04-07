# AGENTS.md

## Project Snapshot

GitBar is a macOS menu bar app for working with a selected Git repository: branches, worktrees, stashes, and pull requests (via `gh` when available).

This repository is a VERY EARLY WIP. Proposing sweeping changes that improve long-term maintainability is encouraged.

## Core Feature

- **Menu bar + popover** — `NSStatusItem`, `NSPopover`, SwiftUI `ContentView` hosted in `AppDelegate`.
- **Git and GitHub CLI** — `git` and `gh` invoked through `ShellExecutor`; parsing lives in `GitService` and related models.

## Core Priorities

1. Performance first.
2. Reliability first.
3. Keep behavior predictable when switching repositories, opening and closing the popover, refreshing from the file watcher or timers, and when `git` / `gh` exit with errors or missing tools.

If a tradeoff is required, choose correctness and robustness over short-term convenience.

## Maintainability

Long term maintainability is a core priority. If you add new functionality, first check if there is shared logic that can be extracted to a separate module. Duplicate logic across multiple files is a code smell and should be avoided. Don't be afraid to change existing code. Don't take shortcuts by just adding local logic to solve a problem.

## Practices

- Match existing **naming** and layout under `GitBar/` (`Views/`, `Services/`, `Models/`, `App/`). Prefer **`@MainActor`** for app/UI and services that touch UI; run blocking shell work off the main actor (e.g. `Task.detached` + `ShellExecutor`) and merge results back on the main actor.
- **Deduplicate** — extract shared rules; avoid one-off forks.
- **Fix causes**, not symptoms; comments **brief and intent-only**.
- **Verify** — Debug build passes; smoke the flows you touched. Add focused tests for non-trivial logic when practical.

Treat **`git`** / **`gh`** and system paths as external; the app should degrade clearly when they are missing or misconfigured.

## Stack conventions

- Swift 5.x, arm64, deployment **macOS 14.6+** (see `GitBar.xcodeproj` for exact target).
- **`@Observable`** — `GitService`, `SettingsService`; environment-injected from `AppDelegate`.

## Model (rough)

```
AppDelegate
  ├── GitService (@Observable) — repo path, branches, worktrees, stashes, pull requests, refresh, watcher, optional auto-fetch
  └── SettingsService (@Observable) — repo list, selected repo, tab visibility, tab order, preferred terminal/editor
```

Persistence: **UserDefaults** for settings keys (see `SettingsService`).

## UI / layout

SwiftUI: tabbed main surface (`AppTab`: branches, worktrees, stashes, pull requests), repo picker and settings as sliding panels. Popover size and hosting are owned by **`AppDelegate`** (`NSHostingController`).

**Git** — `GitRepositoryWatcher` can trigger refreshes; `GitService` coordinates `git` / `gh` calls and model updates.

## Build

```bash
xcodebuild -project GitBar.xcodeproj -scheme GitBar -configuration Debug build
```

Release: `Scripts/release/` (ZIP/DMG, notarize, Sparkle-style flow as configured); CI on tag `v*` via `.github/workflows/release.yml`.
