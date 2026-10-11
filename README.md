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
Drag a terminal by its header onto another's place to move it there; the ones in between
shift along (drop 3 on 1 in the three-pane layout and 1 moves down, 2 moves right).
New terminals start in `~/Developer` (home if it doesn't exist). Scrollback: 10,000 lines.
The selected terminal has an orange border. There is no scroll bar; scroll with the trackpad.
Each header shows the folder while the shell is in front, otherwise the running program's
own title — for Claude, the task it is working on, renamed as the task changes.
Closing the last window keeps Onyx running, like Terminal; click the Dock icon for a new one.

**Reopening.** Onyx keeps a record of what is open (`~/Library/Application Support/Onyx/session.json`,
updated every 2 s), so after quitting — or a force quit or crash — the next launch brings back
the same windows, terminals and order, each Claude back in its conversation
(`claude --resume <id> --permission-mode auto`, in the folder Claude ran in). Which conversation
a terminal holds is read from Claude's own `~/.claude/sessions/<pid>.json`, so a Claude you
started yourself, or one after `/clear`, is followed too. A conversation with no messages yet
starts fresh; programs other than Claude (dev servers, ssh) don't come back; a window you
close on purpose doesn't come back.

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

## License

MIT — see `LICENSE`. SwiftTerm (in `Vendor/SwiftTerm`) keeps its own MIT license.
