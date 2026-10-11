# Onyx — design spec

Date: 2026-10-11 · Status: draft, awaiting owner review

## 1. Intent

A blazing-fast, pitch-black, minimal macOS terminal app. One window holds up to six
independent terminals that tile themselves automatically. Every terminal starts Claude
Code in auto mode, uses the currently active GitHub + Vercel account, and follows shared
rules so two terminals working in the same repo never clobber each other or push
conflicting work.

UX inspiration: claude-fleet's terminal grid feel (dark, dense, header-light panes).
No code or logic is reused from claude-fleet; there is no orchestrator.

### Owner said
- Pitch-black background, minimal UI, very fast.
- App launch opens one terminal. `Cmd+N` or a `+` button adds a terminal inside the same window.
- Auto layout by count; panes resizable; max 6 per window. A 7th `Cmd+N` opens a new window with one terminal; same rules repeat.
- Terminals are independent (like macOS Terminal windows) — no coordinator.
- Multiple GitHub accounts and multiple Vercel accounts; new terminals use them.
- Every terminal auto-starts `claude` in auto mode.
- Terminals start in `~/Developer`.
- One **active default** GitHub + Vercel account; every new terminal uses it; open terminals keep theirs.
- Two terminals in the same project must not create conflicts; if conflicts happen they are resolved properly.
- Stack: native Swift.

### Assumptions (owner may correct)
- Closing a pane re-flows the rest of the layout; closing the last pane closes the window.
- Exiting Claude leaves a normal login `zsh` in that pane.
- App name "Onyx" is a working name.

### Success criteria
- Cold launch to typing-ready terminal < 300 ms (Claude's own startup excluded).
- New pane appears < 50 ms after `Cmd+N`.
- Layout matches §4 for every count 1–6, including after closes.
- `gh`, `git push` (HTTPS), and `vercel` inside a pane act as the account that was active when the pane opened.
- Two panes asked to change the same repo end up on separate worktrees, and both changes land on `main` without lost work.

## 2. Stack

- Swift 6, AppKit (no SwiftUI — the Command Line Tools on this Mac lack the SwiftUI macro plugin).
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) `LocalProcessTerminalView` for PTY + rendering.
- Swift Package Manager; `scripts/bundle.sh` wraps the built binary into `Onyx.app` and installs it to `/Applications`.
- Tests: XCTest via `swift test` (not swift-testing — its macro plugin is flaky under CLT).

## 3. Components

| Unit | Job | Depends on |
|---|---|---|
| `GridLayout` | Pure function: pane count → column structure (§4). | nothing |
| `GridView` | Places pane views per `GridLayout`, draws draggable dividers, keeps per-divider ratios until the next re-flow. | `GridLayout` |
| `PaneView` | Thin header (title, account badge, close ×) + SwiftTerm view. Spawns the shell (§5). | SwiftTerm, `SessionEnv` |
| `WindowController` | One window: top bar (`+`, accounts chip) + `GridView`. Owns ≤ 6 panes. | `GridView`, `PaneView` |
| `AppController` | Window list, menu + shortcuts, "7th pane → new window" rule. | `WindowController` |
| `AccountStore` | GitHub accounts (from `gh`), Vercel tokens (Keychain), active default. | `gh`, Security.framework |
| `SessionEnv` | Builds the env vars for a new pane from the active accounts. | `AccountStore` |
| `onyx-pane` CLI | Presence registry + per-repo push lock (§7). Second executable in the same package. | filesystem only |
| `PanePrompt` | Text appended to Claude's system prompt for every pane (§7). | — |

## 4. Layout

Rule:
- n = 1 → one full pane.
- n = 2 → two columns, side by side.
- n ≥ 3 → `ceil(n/2)` columns; columns fill left to right with 2 panes stacked; if n is odd the last column holds 1 full-height pane.

| n | columns (panes per column) |
|---|---|
| 1 | [1] |
| 2 | [1, 1] |
| 3 | [2, 1] |
| 4 | [2, 2] |
| 5 | [2, 2, 1] |
| 6 | [2, 2, 2] |

Panes keep creation order (column-major). Dividers drag freely (min pane 200×120 pt). Any add/close re-flows to equal sizes.

## 5. Terminal pane

- Spawns `/bin/zsh -l -i -c 'claude --permission-mode auto --append-system-prompt-file <PanePrompt path>; exec /bin/zsh -l -i'` with cwd `~/Developer`.
- Env = user's environment + `SessionEnv` vars + `ONYX_PANE_ID=<uuid>` + `TERM=xterm-256color`.
- Header shows the foreground process title (from the terminal's title escape) and the GitHub login badge.
- Pane process exit (shell `exit`) closes the pane.
- Font: SF Mono 13 (setting). Colors: background `#000000`, foreground `#d4d4d4`, cursor `#ffffff`, ANSI palette tuned for black.

## 6. Accounts

**GitHub.** Accounts come from `gh auth status` (gh already supports multiple logins). "Add GitHub account" opens a pane running `gh auth login`. For the active account, `SessionEnv` sets:
- `GH_TOKEN` = `gh auth token -u <login>` (covers `gh` and HTTPS `git push`, which uses gh as credential helper);
- `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, `GIT_COMMITTER_EMAIL` from that account's profile (name, public or noreply email). A per-account override for name/email is stored in settings — needed for identities like `Gyftalala <mail@gyftalala.com>`.

SSH remotes ignore `GH_TOKEN`; panes note this in the account popover only.

**Vercel.** The Vercel CLI keeps one login, so Onyx stores personal access tokens instead: "Add Vercel account" asks for a label + token (created at vercel.com/account/tokens), validates it with `vercel whoami --token`, saves it to the Keychain. Active account → `VERCEL_TOKEN`.

**UI.** Top-bar chip `● gh: <login> · ▲ <vercel label>`; click → popover listing accounts, pick active, add/remove. Change applies to new panes only. Settings live in `~/Library/Application Support/Onyx/settings.json` (no secrets); tokens only in the Keychain.

## 7. Same-repo safety

Goal: two panes never edit the same working tree at once, and pushes never race.

**Presence registry** — `~/Library/Application Support/Onyx/panes/<ONYX_PANE_ID>.json` = `{pid, repoRoot, worktree, branch, task, updatedAt}`. Entries whose `pid` is dead are pruned on every read.

**`onyx-pane` CLI** (on `PATH` inside panes):
- `onyx-pane claim <dir> "<task>"` — registers this pane in the repo containing `<dir>`. If another live pane already holds that repo's main checkout, prints `USE_WORKTREE <path> <branch>` and creates the worktree at `<repo>/.onyx-worktrees/<short-id>` on branch `onyx/<short-id>` (dir added to `.git/info/exclude`). Otherwise prints `OK <repoRoot>`.
- `onyx-pane who [<dir>]` — lists live panes in that repo and their tasks.
- `onyx-pane push` — takes the per-repo lock (atomic `mkdir` lock holding the pid, waits up to 5 min, stale-lock steal when pid dead), then `git fetch` + `git rebase origin/<target>`; prints `CONFLICT <files>` and stops (lock released) or pushes and prints `PUSHED <sha>`. For a worktree branch, target is the repo's default branch: rebase onto `origin/<default>`, push `HEAD` to `origin/<default>` (the main-checkout pane picks it up on its own next rebase); `release` then removes the merged worktree + branch. No `origin` → prints `NO_REMOTE`, exits 2, branch kept for the owner.
- `onyx-pane release` — drops this pane's claim; removes its worktree if merged.

**`PanePrompt`** (appended to every Claude session) tells Claude to:
1. Run `onyx-pane claim` before editing any git repo; if told `USE_WORKTREE`, `cd` there and work only there.
2. Always push via `onyx-pane push`; never `git push --force`.
3. On `CONFLICT`: resolve keeping both sides' intent, run the project's tests, re-run `onyx-pane push`. If the right resolution is a judgment call (both sides changed the same logic differently), stop and ask the owner.
4. Run `onyx-pane release` when the task is done.
5. Respect the repo's own `CLAUDE.md` rules (e.g. ship scripts) — they win over generic push steps.

## 8. Shortcuts & menu

| Key | Action |
|---|---|
| `Cmd+N` / `+` | New pane (7th → new window) |
| `Cmd+Shift+N` | New window |
| `Cmd+W` | Close focused pane |
| `Cmd+1`…`Cmd+6` | Focus pane |
| `Cmd+Opt+arrows` | Move focus |
| `Cmd+,` | Settings (font size, accounts) |
| `Cmd+=` / `Cmd+-` | Font size |

Focused pane: 1 pt `#2a2a2a` border vs `#111111` for others. No animations.

## 9. Errors

- `claude` missing → pane shows one dim line "claude not found — plain shell" and stays a shell.
- `gh` token fetch fails → pane opens without `GH_TOKEN`; badge shows `gh: none` in dim red.
- Invalid Vercel token on add → inline error, not saved.
- Registry dir unwritable → `onyx-pane` exits non-zero with a message; Claude falls back to asking the owner.

## 10. Testing

- Unit (XCTest): `GridLayout` for n = 0…7; `SessionEnv` env building; `onyx-pane` claim/who/release/lock against temp git repos with two fake pane ids, including dead-pid pruning, stale-lock steal, rebase conflict detection, worktree merge-back.
- Manual checklist: launch time, add 1→7 panes, closes re-flow, divider drag, account switch affects only new panes, `gh api user` + `vercel whoami` inside a pane, two panes on one test repo end with both commits on `main`.

## 11. Out of scope (v1)

Tabs, split-by-drag, session restore, themes, search, scrollback export, Windows/Linux.
