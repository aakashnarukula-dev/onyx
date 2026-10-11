# Onyx

A fast, pitch-black macOS terminal that tiles up to six terminals in one window. Every
terminal starts Claude Code in auto mode in `~/Developer`, using the GitHub and Vercel
accounts you picked. Terminals working in the same repo see each other and push safely.

## Use

| Key | Action |
|---|---|
| `⌘N` / `+` | New terminal (the 7th opens a new window) |
| `⌘⇧N` | New window |
| `⌘W` | Close terminal |
| `⌘1`…`⌘6` | Focus terminal |
| `⌘⌥←↑↓→` | Move focus |
| `⌘=` / `⌘-` | Font size |
| `⌘,` | Settings |

Layout follows the count: 1 full, 2 side by side, 3 = two stacked left + one right,
4 = 2×2, 5 = 2+2+1, 6 = 3×2. Drag the gaps to resize; adding or closing re-flows.

## Accounts

Click the chip at the top right (`● gh: … · ▲ …`).

- **GitHub:** lists the logins `gh` knows (`gh auth login` adds more). The active one gives
  new terminals `GH_TOKEN` plus matching `GIT_AUTHOR_*`/`GIT_COMMITTER_*`. "identity"
  overrides the commit name/email. HTTPS remotes only; SSH remotes ignore the token.
- **Vercel:** add a label and a token from vercel.com/account/tokens. Tokens live in the
  Keychain; the active one becomes `VERCEL_TOKEN`.

Changes apply to new terminals; open ones keep theirs.

## Same-repo safety: `onyx-pane`

Each Claude session is told to use this helper (it is on `PATH` in every terminal):

```
onyx-pane claim <dir> "<task>"   OK <root>  |  USE_WORKTREE <path> <branch>
onyx-pane who [<dir>]            panes in the repo and their tasks
onyx-pane push                   one pane at a time: fetch, rebase, push
                                 PUSHED <sha> | CONFLICT <files> | NO_REMOTE
onyx-pane release                drops the claim; removes a merged worktree
```

The first terminal in a repo works in the main checkout; later ones get a worktree under
`.onyx-worktrees/` (git-excluded) and push straight to the default branch. Conflicts are
resolved by Claude keeping both sides' intent; judgment calls go to you.

State lives in `~/Library/Application Support/Onyx` (`settings.json`, `panes/`, `locks/`,
`pane-prompt.md`).

## Build

Needs only the Command Line Tools.

```
scripts/test.sh      # unit tests (Swift Testing)
scripts/bundle.sh    # release build -> /Applications/Onyx.app
```

SwiftTerm is pinned to 1.11.2: newer versions ship a Metal shader that needs full Xcode.

Test hooks (inert unless set): `ONYX_PANE_COMMAND`, `ONYX_SNAPSHOT` + `ONYX_SCRIPT`,
`ONYX_TIMING` — see `Sources/Onyx/DebugHooks.swift`.
