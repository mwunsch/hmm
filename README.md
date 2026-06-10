# hmm

`hmm` is a small terminal-native wrapper around `codex exec`.

It lets you ask Codex something inline from your shell, keeps the conversation
sticky for the life of the terminal, and renders Codex's JSONL stream as compact
terminal output instead of a full coding TUI.

```sh
hmm I can never remember the flags for tar. Make this directory a tarball.
hmm --write now do it
hmm now scp that to my server
```

The goal is a terminal clippy: unobtrusive, shell-shaped, visually distinct, and
able to use Codex tools without becoming a second agent harness.

## Status

This repo currently implements a zsh-first v1:

- shell-native prompt capture via `shell/zsh.sh`
- sticky sessions scoped to the current terminal
- `codex exec --json` backend
- compact rendering for assistant output, shell tool use, and token usage
- safety presets for read-only, workspace-write, and danger mode
- raw JSON mode for debugging

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

Add `bin` to your `PATH` and source the zsh integration:

```zsh
export PATH="/path/to/hmm/bin:$PATH"
source /path/to/hmm/shell/zsh.sh
```

The zsh integration defines:

```zsh
alias hmm='noglob _hmm'
```

That `noglob` wrapper is what lets prompts contain `?` and `*` without zsh
treating them as filename patterns.

## Usage

```sh
hmm <anything you want, unquoted>
```

Examples:

```sh
hmm how do I flush DNS cache on macOS
hmm what does docker COPY do differently from ADD
hmm summarize what is in $PWD
hmm --write create a tarball of this directory
hmm --new explain rsync include and exclude rules
```

Everything after the recognized leading flags is joined into one prompt. If your
prompt itself starts with a flag-like token, use `--`:

```sh
hmm -- --force means what in git clean?
```

You can also pass the whole prompt on stdin. This is useful when you want to type
punctuation that would otherwise be shell syntax:

```sh
bin/hmm <<'EOF'
Hey here I can type whatever I'd like, right?
Can you explain `find . -name "*.log" -mtime +7 -delete`?
EOF
```

The quoted delimiter, `<<'EOF'`, is important: it prevents the shell from
expanding `$VARS`, command substitutions, globs, and backticks inside the block.
Use unquoted `<<EOF` if you intentionally want normal shell expansion.

## Flags

```text
--new, --reset          Start a fresh terminal session
--show                  Show the current terminal session id
--model, -m <model>     Use a Codex model for this turn
--profile, -p <name>    Use a Codex config profile
--config, -c <k=v>      Pass a Codex config override
--write                 Allow workspace writes for this turn
--danger                Bypass Codex approvals and sandboxing
--quiet                 Print only assistant messages
--verbose               Show extra event details
--json                  Print raw Codex JSONL events
--color <mode>          auto, always, or never
--no-color              Disable color
--no-spinner            Disable the loading spinner
--instructions <text>   Override the default hmm instruction prefix
--no-instructions       Send the prompt without hmm's instruction prefix
```

Common Codex passthrough flags such as `--enable`, `--disable`, `--image`,
`--cd`, `--add-dir`, `--ignore-user-config`, and `--ignore-rules` are also
accepted before the prompt.

## Sessions

`hmm` keeps one sticky Codex thread per terminal.

The zsh wrapper passes the parent shell PID and current TTY to `bin/hmm`:

```sh
HMM_SHELL_PID=$$ HMM_TTY="$(tty)" command hmm "$@"
```

Those values are hashed into a session key. The current session id is stored at:

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
hmm explain what this repo does
```

Internally that passes Codex:

```text
--config sandbox_mode="read-only"
```

For edits or local command execution that writes to the workspace:

```sh
hmm --write create a tarball of this directory
```

That passes:

```text
--config sandbox_mode="workspace-write"
```

For fully unsandboxed automation:

```sh
hmm --danger do the broad local task I just described
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

## Piped Input

Codex supports prompts plus piped stdin. `hmm` preserves that behavior:

```sh
git diff | hmm summarize this diff
```

If no prompt arguments are provided, stdin becomes the prompt itself:

```sh
hmm <<'EOF'
I can type ?, *, |, >, <, $(commands), "quotes", and apostrophes like I've here.
EOF
```

When stdin is piped, Codex may print its own note that it is reading additional
input. That comes from Codex, not from `hmm`.

## Shell Limitations

The zsh wrapper handles common prompt punctuation by using `noglob`, so `?` and
`*` are passed literally.

That only works when you call the shell-integrated command:

```sh
hmm Hey does this work?
```

It cannot work for direct debug calls like this:

```sh
bin/hmm Hey does this work?
```

In that form, zsh expands `work?` before `bin/hmm` starts and may fail with
`zsh: no matches found`. Use the sourced `hmm` command, quote the prompt, or run
`noglob bin/hmm ...` when debugging the executable directly.

Other shell metacharacters are still shell syntax before `hmm` ever sees them:

```text
| > < & ; ( ) ` $( ) ' "
```

Quote those prompts, escape the characters, or use `--` where appropriate.
An unescaped apostrophe in a contraction like `i've` starts a shell quote and can
leave zsh at a `quote>` continuation prompt. The shell blocks that before `hmm`
can run; use `ive`, `I have`, or quote/escape the apostrophe.

For long or punctuation-heavy prompts, prefer a single-quoted heredoc delimiter:

```sh
hmm <<'EOF'
Here's a prompt with ?, *, pipes |, redirects >, command substitution $(nope),
backticks `nope`, and quotes "like this".
EOF
```

`$VARS` are expanded by your shell before `hmm` sees the prompt. This is useful
for questions like:

```sh
hmm what is in $HOME
```

If you want the literal string `$HOME`, quote or escape it.

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

shell/zsh.sh
  provides the terminal-native unquoted prompt experience
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

Good shell-script tests for this project should:

- exercise scripts as black-box commands, not sourced internals
- isolate all state with `TMPDIR`, `HMM_STATE_DIR`, `HMM_SHELL_PID`, and `HMM_TTY`
- mock external programs by prepending a temporary directory to `PATH`
- disable color and spinners for stable output assertions
- test syntax with `sh -n` and `zsh -n`
- use fixture JSONL for renderer behavior
- assert generated Codex arguments instead of making model calls
- avoid exact assertions on timing values

Current coverage includes:

- shell syntax for all scripts
- `--help` without writable temp space
- session save/show/reset behavior
- `--reset --show` ordering
- renderer output for shell events, assistant text, usage, and unwritable metadata
- default instruction prefix and `--no-instructions`
- direct `bin/hmm` continuity without the zsh wrapper environment
- `--write` and `--danger` Codex flags
- Codex exit-status propagation
- zsh `noglob` alias behavior for `?`
