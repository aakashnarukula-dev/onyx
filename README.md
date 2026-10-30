# Onyx

A fast, pitch-black macOS app that groups up to six normal terminals in one window. Each
terminal is exactly what Terminal.app gives you — your login shell started the same way, your
environment, your `gh`/git/vercel logins — with Claude Code or OpenAI Codex (sign in with your ChatGPT account).
The selected assistant is started at the first prompt; Claude remains the default. Ctrl-Z / `fg` work on it; quit Claude and you're in your shell.

![Four Claude terminals in one Onyx window, each header named after its task](docs/screenshots/four-terminals.png)

## Use

| Key | Action |
|---|---|
| `⌘N` / `+` | New terminal (the 7th opens a new window) |
| `⌘⌥N` | New Claude terminal |
| `⌘⌃N` | New Codex terminal (ChatGPT) |
| `⌘⇧N` | New window |
| `⌘W` | Close terminal (asks first if it holds a Claude conversation or something is working) |
| `⌘K` | Clear |
| `⌘C` / `⌘V` | Copy / paste |
| `⌘`-click | Open a link |
| Drop files | Types their paths, escaped like Terminal (Claude attaches dropped images) |
| `⌘1`…`⌘6` | Focus terminal |
| `⌘⌥←↑↓→` | Move focus |
| `⌘+` / `⌘-` / `⌘0` | Font bigger / smaller / default (14 pt) |

Layout follows the count: 1 full, 2 side by side, 3 = two stacked left + one right,
4 = 2×2, 5 = 2+2+1, 6 = 3×2. Drag the gaps to resize; adding or closing re-flows.
Drag a terminal by its header onto another's place to move it there; the ones in between
shift along (drop 3 on 1 in the three-pane layout and 1 moves down, 2 moves right).
Drag a terminal out of the window and let go to give it a window of its own (or let go over
another Onyx window with room to move it there); it keeps running throughout.

![Three terminals: two stacked on the left, one on the right](docs/screenshots/three-terminals.png)

New terminals start in `~/Developer` (home if it doesn't exist). Scrollback: 10,000 lines.
The cursor is a blinking line. The selected terminal has an orange border. There is no scroll bar; scroll with the trackpad.
Each header shows the folder while the shell is in front, otherwise the running program's
own title — for Claude, the task it is working on, renamed as the task changes.
Closing the last window keeps Onyx running, like Terminal; click the Dock icon for a new one.

**Reopening.** Onyx keeps a record of what is open (`~/Library/Application Support/Onyx/session.json`,
updated every 2 s), so after quitting — or a force quit or crash — the next launch asks
"Reopen your last terminals?" and can bring back the same windows, terminals and order, each
Claude back in its conversation
(`claude --resume <id> --permission-mode auto`, in the folder Claude ran in). Which conversation
a terminal holds is read from Claude's own `~/.claude/sessions/<pid>.json`, so a Claude you
started yourself, or one after `/clear`, is followed too. A conversation with no messages yet
starts fresh, and if none had messages Onyx doesn't ask and just opens one terminal; programs other than Claude (dev servers, ssh) don't come back; a window you
close on purpose doesn't come back.

Choose **Shell > Default Assistant > Claude / Codex (ChatGPT)** to set what `⌘N`, `+`,
new windows, and fresh launches open. Use **Shell > New Claude Terminal** or
**New Codex Terminal (ChatGPT)** to mix both in one window without changing the default.
Codex uses its normal permissions and login; Onyx does not add approval-bypass flags.

Saved Codex panes reopen `codex resume` in their saved folder, where you choose a conversation.
Onyx does not yet track the exact Codex conversation ID. Claude's automatic conversation
restore remains unchanged. File drops paste paths; image attachment behavior depends on the CLI.

## Install

Needs macOS 14 or newer and Apple's Command Line Tools (`xcode-select --install`) or Xcode.
For terminals to start Claude, install [Claude Code](https://docs.claude.com/en/docs/claude-code)
so `claude` is on your PATH. For ChatGPT, install [Codex CLI](https://learn.chatgpt.com/docs/cli)
(`npm install -g @openai/codex`), run `codex`, and select **Sign in with ChatGPT**.
Both CLIs use your existing local login. If the selected CLI is missing, Onyx leaves a plain shell
with a message; install the CLI and run `claude` or `codex` there.

```
git clone https://github.com/aakashnarukula-dev/onyx.git
cd onyx
scripts/bundle.sh          # builds (first time takes a few minutes, ~8 on a MacBook Air), installs /Applications/Onyx.app, pins it to the Dock
open /Applications/Onyx.app
```

Optional, once per Mac: `scripts/make-signing-cert.sh` adds a self-signed "Onyx Local Signing"
certificate to your keychain (the first build after asks you to allow codesign to use it — enter
your password, click Always Allow). Builds are then signed with it, so macOS keeps Onyx's
permissions (microphone for Claude's voice input, folders) across updates instead of asking again.

The install pins Onyx to the Dock once (it never adds a second icon); set `ONYX_NO_DOCK=1` to skip that.

Built on your Mac, so Gatekeeper doesn't block it. To update: `git pull && scripts/bundle.sh`
(quit Onyx first). To uninstall: delete `/Applications/Onyx.app` and
`~/Library/Application Support/Onyx`.

New terminals start in `~/Developer`, or your home folder if that doesn't exist.

## Build

```
scripts/test.sh      # unit tests (Swift Testing)
scripts/bundle.sh    # release build -> /Applications/Onyx.app
```

SwiftTerm v1.20.0 is vendored in `Vendor/SwiftTerm` with its Metal shader left out of the
build (the Command Line Tools have no `metal` compiler; Onyx uses the CoreText renderer).
One patch: `CSI 0 SP q` restores the user's cursor shape (Onyx's blinking line) instead of a block.

Test hooks (inert unless set): `ONYX_PANE_COMMAND`, `ONYX_SNAPSHOT` + `ONYX_SCRIPT`,
`ONYX_TIMING` — see `Sources/Onyx/DebugHooks.swift`.

## License

MIT — see `LICENSE`. SwiftTerm (in `Vendor/SwiftTerm`) keeps its own MIT license.
