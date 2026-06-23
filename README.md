# hmm

`hmm` is a small terminal-native wrapper around `codex exec`.

It lets you ask Codex something from your shell, keeps a sticky conversation for
the life of the terminal, and renders Codex's JSONL stream as compact terminal
output instead of a full coding TUI.

```sh
hmm "I can never remember the flags for tar. Make this directory a tarball."
hmm --write "now do it"
hmm "now scp that to my server"
```

The goal is a terminal clippy: unobtrusive, shell-shaped, visually distinct, and
able to use Codex tools without becoming a second agent harness.

## Status

This repo currently implements a portable shell v1:

- quoted prompt arguments
- stdin, heredoc, and file prompt input
- a small multiline compose prompt for interactive use
- sticky sessions scoped to the current terminal
- `codex exec --json` backend
- compact rendering for assistant output, shell tool use, and token usage
- safety presets for read-only, workspace-write, and danger mode

## Requirements

Required:

- `codex`
- `jq`
- POSIX-ish `/bin/sh`

Optional:

- `tput` for colors
- `perl` for prettier thousands separators in token counts
- `shasum` for stable session keys, with `cksum` fallback

`tput` is optional and broadly deployed on normal macOS/Linux systems through
terminfo/ncurses. If it is missing, or output is not a TTY, `hmm` falls back to
plain text.

## Install

From a cloned checkout:

```sh
./install.sh
```

One-line install from the latest GitHub release:

```sh
curl -fsSL https://github.com/mwunsch/hmm/releases/latest/download/install.sh | sh
```

This installs:

```text
~/.local/bin/hmm
~/.local/libexec/hmm-*
~/.local/share/man/man1/hmm.1
```

If `~/.local/bin` is not on your `PATH`, the installer prints the line to add.

Installer environment variables:

```text
HMM_PREFIX        install prefix, default: ~/.local
HMM_BIN_DIR       override binary directory, default: $HMM_PREFIX/bin
HMM_MAN_DIR       override man page directory, default: $HMM_PREFIX/share/man/man1
HMM_REPO=url      GitHub-style repo URL, default: https://github.com/mwunsch/hmm
HMM_REF=name      branch name for HMM_REPO archives, default: latest release
HMM_TARBALL_URL   explicit source archive URL for curl installs
```

To pin an install to a specific release archive:

```sh
curl -fsSL https://raw.githubusercontent.com/mwunsch/hmm/main/install.sh \
  | HMM_TARBALL_URL=https://github.com/mwunsch/hmm/releases/download/v0.1.0/hmm.tar.gz sh
```

For development installs from a branch:

```sh
curl -fsSL https://raw.githubusercontent.com/mwunsch/hmm/main/install.sh \
  | HMM_REF=main sh
```

## Usage

Use quoted strings for simple prompts:

```sh
hmm "how do I flush DNS cache on macOS?"
hmm "what does docker COPY do differently from ADD?"
hmm --write "create a tarball of this directory"
hmm --new "explain rsync include and exclude rules"
```

Use stdin or a heredoc for punctuation-heavy or multiline prompts:

```sh
hmm <<'EOF'
Hey, here I can type whatever I'd like, right?
Can you explain `find . -name "*.log" -mtime +7 -delete`?
EOF
```

Use `--file` / `-f` for durable prompts:

```sh
hmm --file prompt.md
hmm -f prompt.md
```

Use `-` to read the prompt from stdin explicitly:

```sh
hmm --file - < prompt.md
```

If no prompt arguments are provided and stdin is a TTY, `hmm` opens a small
in-terminal compose prompt:

```text
╭─ hmm compose
│  Type or paste your prompt. Enter adds a line. Ctrl-D sends. Ctrl-C cancels.
│
│ first line
│ second line
╰─ send
```

The compose prompt is intentionally lightweight and portable. Enter adds lines;
Ctrl-D sends; Ctrl-C cancels. It stays in the terminal, does not open `$EDITOR`,
and does not use a full TUI framework.

## Flags

```text
--new, --reset          Start a fresh terminal session
--show                  Show the current terminal session id
--model, -m <model>     Use a Codex model for this turn
--profile, -p <name>    Use a Codex config profile
--config, -c <k=v>      Pass a Codex config override
--file, -f <file>       Read the prompt from a file (- for stdin)
--write                 Allow workspace writes for this turn
--danger                Bypass Codex approvals and sandboxing
--quiet                 Print only assistant messages
--verbose               Show extra event details
--json                  Print raw Codex JSONL events
--color <mode>          auto, always, or never
--no-color              Disable color
--no-spinner            Disable the thinking indicator
--instructions <text>   Override the default hmm instruction prefix
--no-instructions       Send the prompt without hmm's instruction prefix
--version               Show hmm version
```

Common Codex passthrough flags such as `--enable`, `--disable`, `--image`,
`--cd`, `--add-dir`, `--ignore-user-config`, and `--ignore-rules` are also
accepted before the prompt.

## Sessions

`hmm` keeps one sticky Codex thread per terminal.

The session key is based on the parent shell process and current TTY. The current
session id is stored at:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/hmm/sessions/<key>
```

This intentionally does not include the current working directory. You can move
around in a terminal session and keep talking to the same assistant.

Use `hmm --new` or `hmm --reset` to forget the current terminal's thread.

Use `hmm --show` to print the stored Codex thread id.

## Safety

Default mode is read-only:

```sh
hmm "explain what this repo does"
```

Internally that passes Codex:

```text
--config sandbox_mode="read-only"
```

For edits or local command execution that writes to the workspace:

```sh
hmm --write "create a tarball of this directory"
```

That passes:

```text
--config sandbox_mode="workspace-write"
```

For fully unsandboxed automation:

```sh
hmm --danger "do the broad local task I just described"
```

That passes:

```text
--dangerously-bypass-approvals-and-sandbox
```

`--danger` is intentionally explicit and prints a warning. `hmm` does not try to
replace Codex's permission system; it provides small, memorable presets over it.

## Instructions

`hmm` prefixes each turn with a short instruction that biases Codex toward terse
terminal-assistant behavior:

```text
Answer briefly and directly. Prefer the smallest useful answer. Do not inspect
files or run tools unless needed to answer or act.
```

Override it for one call with `--instructions <text>`, set a default with
`HMM_INSTRUCTIONS`, or disable it with `--no-instructions`.

## Rendering

`hmm` always runs Codex in JSONL mode and renders the stream.

Normal mode shows:

```text
> shell: /bin/zsh -lc pwd
ok shell completed

done

45.2k in / 37 out · 45.2k total · 2.1s
```

The renderer is deliberately compact:

- while Codex is thinking, a spinner and yellow `hmmmm...` indicator grow across the terminal with a dim `(thinking)` label
- assistant messages are bold when color/style is available
- shell tool use is shown as dim start/completion lines
- token usage and elapsed time are shown at the end when Codex emits usage data
- `--no-spinner` disables the thinking indicator
- `--verbose` shows extra event details
- `--json` bypasses rendering and prints raw Codex JSONL

Context utilization is shown only when `hmm` knows the model's context window.
Unknown models show token counts without a percentage.

Stream behavior:

- assistant text and compact tool visualization go to stdout
- token usage, elapsed time, warnings, and errors go to stderr
- `--json` prints raw Codex JSONL to stdout and suppresses the usage footer

## Shell Parsing

`hmm` does not try to defeat shell parsing. Quote prompts that contain shell
syntax, or use stdin, heredocs, files, or the compose prompt.

These are safe patterns:

```sh
hmm "what does --force do in git clean?"
hmm 'what is the literal meaning of $PATH?'
hmm <<'EOF'
Explain `cmd`, $(substitution), pipes |, redirects >, and quotes "like this".
EOF
```

The quoted heredoc delimiter, `<<'EOF'`, prevents the shell from expanding
`$VARS`, command substitutions, globs, and backticks inside the block.

## Architecture

```text
bin/hmm
  parses hmm flags
  manages terminal session state
  invokes libexec/hmm-codex
  pipes JSONL into libexec/hmm-render

libexec/hmm-session
  computes the per-terminal session key
  saves, shows, and resets Codex thread ids

libexec/hmm-codex
  is the only script that knows how to call codex exec
  normalizes safety presets and passthrough Codex flags

libexec/hmm-render
  consumes Codex JSONL
  renders assistant text, shell tool use, and usage data

install.sh
  installs the CLI and private helpers
```

Codex remains responsible for tools, MCP, skills, sandboxing, approvals, and
model execution. `hmm` is just the inline terminal adapter.

`libexec` is intentional Unix packaging language: these are private executable
helpers used by `bin/hmm`, not user-facing commands or generic project scripts.

## Tests

Run the test suite with:

```sh
tests/run
```

The tests do not invoke real Codex. They put a fake `codex` executable at the
front of `PATH`, feed deterministic JSONL into the renderer, and isolate session
state under a temp directory.

Current coverage includes:

- shell syntax for all scripts
- local installer behavior
- `--help` without writable temp space
- session save/show/reset behavior
- `--reset --show` ordering
- renderer output for shell events, assistant text, usage, and unwritable metadata
- default instruction prefix and `--no-instructions`
- stdin, heredoc, and file prompt input
- direct `bin/hmm` continuity
- `--write` and `--danger` Codex flags
- Codex exit-status propagation

## Releases

CI runs `tests/run` on pushes and pull requests across Ubuntu and macOS.

To publish a versioned GitHub Release:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The release workflow runs the test suite, then creates a GitHub Release for the
tag. GitHub automatically provides source archives for each tag; use
`HMM_TARBALL_URL` to pin installs to one of those archives.
