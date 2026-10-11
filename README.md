# Onyx

A fast, pitch-black macOS app that groups up to six normal terminals in one window. Each
terminal is exactly what Terminal.app gives you — your login shell started the same way, your
environment, your `gh`/git/vercel logins — except that `claude --permission-mode auto` is typed
for you at the first prompt. Ctrl-Z / `fg` work on it; quit Claude and you're in your shell.

## Use

| Key | Action |
|---|---|
| `⌘N` / `+` | New terminal (the 7th opens a new window) |
| `⌘⇧N` | New window |
| `⌘W` | Close terminal (asks first if something is still running) |
| `⌘K` | Clear |
| `⌘C` / `⌘V` | Copy / paste |
| `⌘`-click | Open a link |
| `⌘1`…`⌘6` | Focus terminal |
| `⌘⌥←↑↓→` | Move focus |
| `⌘+` / `⌘-` / `⌘0` | Font bigger / smaller / default |

Layout follows the count: 1 full, 2 side by side, 3 = two stacked left + one right,
4 = 2×2, 5 = 2+2+1, 6 = 3×2. Drag the gaps to resize; adding or closing re-flows.
New terminals start in `~/Developer` (home if it doesn't exist). Scrollback: 10,000 lines.
Each header shows the folder while the shell is in front, otherwise the running program.
Closing the last window keeps Onyx running, like Terminal; click the Dock icon for a new one.

## Build

Needs only the Command Line Tools.

```
scripts/test.sh      # unit tests (Swift Testing)
scripts/bundle.sh    # release build -> /Applications/Onyx.app
```

SwiftTerm v1.20.0 is vendored in `Vendor/SwiftTerm` with its Metal shader left out of the
build (the Command Line Tools have no `metal` compiler; Onyx uses the CoreText renderer).

Test hooks (inert unless set): `ONYX_PANE_COMMAND`, `ONYX_SNAPSHOT` + `ONYX_SCRIPT`,
`ONYX_TIMING` — see `Sources/Onyx/DebugHooks.swift`.
