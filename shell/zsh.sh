# zsh integration for hmm.
# Source this file from ~/.zshrc to enable unquoted prompts with noglob.

_hmm_source=${(%):-%N}
_hmm_dir=${_hmm_source:A:h}
_hmm_root=${_hmm_dir:h}

_hmm() {
  local hmm_bin="$_hmm_root/bin/hmm"
  if [[ ! -x "$hmm_bin" ]]; then
    hmm_bin=$(whence -p -- hmm 2>/dev/null)
  fi

  if [[ -z "$hmm_bin" || ! -x "$hmm_bin" ]]; then
    print -u2 'hmm: executable not found'
    return 127
  fi

  HMM_SHELL_PID=$$ HMM_TTY="$(tty 2>/dev/null)" command "$hmm_bin" "$@"
}

alias hmm='noglob _hmm'
