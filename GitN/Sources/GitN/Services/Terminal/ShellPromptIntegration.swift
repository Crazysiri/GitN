import Foundation

/// Builds opt-in shell wrappers that emit a GitN-owned, invisible prompt marker
/// so the terminal can locate where the prompt ends and user input begins.
///
/// Design constraints (SPEC §6.2):
/// - GitN uses its own CSI marker (`ESC [ 7000 ~`), not any reference app's name.
/// - The wrapper sources the user's own init files first and never overwrites
///   their PS1 / precmd / PROMPT_COMMAND hooks; it chains onto them.
/// - Loading is re-entrancy-safe (guarded so nested shells don't double-wrap).
/// - Only new terminal processes see this; the user's dotfiles are untouched.
enum ShellPromptIntegration {
    /// The private parameter sequence GitN emits at the end of each prompt.
    /// `ESC [ 7000 ~` — a CSI with a final byte `~` and a private code unlikely
    /// to collide with real terminal usage.
    static let promptMarkerCSI = "\u{001B}[7000~"

    enum Shell {
        case zsh
        case bash
    }

    /// Detect the supported shell family from an executable path. Shells other
    /// than zsh/bash return nil (they still run; integration is just disabled).
    static func shell(forExecutable path: String) -> Shell? {
        let name = (path as NSString).lastPathComponent
        switch name {
        case "zsh": return .zsh
        case "bash", "sh": return .bash
        default: return nil
        }
    }

    /// zsh: run with `ZDOTDIR` pointed at a GitN directory containing a `.zshrc`
    /// that sources the user's config, then appends the marker to the END of
    /// PS1. The marker must sit at the prompt's end (= the input start column)
    /// so the terminal records the right cursorX. It is wrapped in `%{...%}` so
    /// zsh counts it as zero-width. Done via precmd so it survives themes that
    /// rebuild PS1 each prompt, and guarded so it is appended only once.
    static func zdotdirZshrc() -> String {
        """
        # GitN terminal integration (opt-in, re-entrancy-safe). Do not edit.
        if [[ -z "$GITN_PROMPT_WRAPPED" ]]; then
          export GITN_PROMPT_WRAPPED=1
          # Restore the user's ZDOTDIR and source their real init files first.
          if [[ -n "$GITN_USER_ZDOTDIR" ]]; then
            export ZDOTDIR="$GITN_USER_ZDOTDIR"
          else
            unset ZDOTDIR
          fi
          [[ -f "${ZDOTDIR:-$HOME}/.zshrc" ]] && source "${ZDOTDIR:-$HOME}/.zshrc"

          # Append a zero-width marker to the END of PS1 (the input start). Runs
          # in precmd so it re-applies after frameworks rebuild PS1, and strips
          # any prior copy first so it is never duplicated.
          __gitn_prompt_mark=$'%{\\033[7000~%}'
          __gitn_apply_prompt() {
            PS1="${PS1//$__gitn_prompt_mark/}$__gitn_prompt_mark"
          }
          autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook precmd __gitn_apply_prompt
        fi
        """
    }

    /// bash: run with `--rcfile` pointing at a GitN rcfile that sources the
    /// user's profile then appends the marker to the END of PS1. The marker is
    /// wrapped in `\\[..\\]` so readline excludes it from line-length math.
    static func bashRCFile() -> String {
        """
        # GitN terminal integration (opt-in, re-entrancy-safe). Do not edit.
        if [ -z "$GITN_PROMPT_WRAPPED" ]; then
          export GITN_PROMPT_WRAPPED=1
          [ -f /etc/profile ] && source /etc/profile
          [ -f "$HOME/.bash_profile" ] && source "$HOME/.bash_profile"
          [ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"
          __gitn_prompt_mark=$'\\[\\033[7000~\\]'
          __gitn_apply_prompt() {
            case "$PS1" in
              *"$__gitn_prompt_mark"*) : ;;
              *) PS1="$PS1$__gitn_prompt_mark" ;;
            esac
          }
          case "$PROMPT_COMMAND" in
            *__gitn_apply_prompt*) : ;;
            "") PROMPT_COMMAND="__gitn_apply_prompt" ;;
            *) PROMPT_COMMAND="$PROMPT_COMMAND; __gitn_apply_prompt" ;;
          esac
        fi
        """
    }
}
