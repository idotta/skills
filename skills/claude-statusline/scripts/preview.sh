#!/usr/bin/env bash
# Render a status line script against several sample inputs, so a change to
# colors or segments can be seen without restarting Claude Code.
#
#   preview.sh [path-to-statusline-script]   # defaults to ~/.claude/statusline-command.sh
#
# Each case exercises a branch of the script: fields present, fields missing,
# and the context thresholds that switch the percentage between green, yellow
# and red. If a case prints nothing, that path is broken — the real status line
# fails the same silent way.

set -uo pipefail

SCRIPT="${1:-$HOME/.claude/statusline-command.sh}"
[ -f "$SCRIPT" ] || { echo "preview.sh: no such script: $SCRIPT" >&2; exit 1; }

render() {
    local label="$1" json="$2" out
    out=$(printf '%s' "$json" | bash "$SCRIPT" 2>&1)
    printf '%-22s %s\n' "$label" "${out:-<empty — this case is broken>}"
}

DIR="${PWD}"

render "full"          '{"model":{"display_name":"Claude Opus 5"},"workspace":{"current_dir":"'"$DIR"'"},"context_window":{"remaining_percentage":72.4},"effort":{"level":"high"}}'
render "no effort"     '{"model":{"display_name":"Claude Sonnet 5"},"workspace":{"current_dir":"'"$DIR"'"},"context_window":{"remaining_percentage":72.4}}'
render "effort MEDIUM" '{"model":{"display_name":"Claude Opus 5"},"workspace":{"current_dir":"'"$DIR"'"},"context_window":{"remaining_percentage":40},"effort":{"level":"MEDIUM"}}'
render "ctx mid"       '{"model":{"display_name":"Claude Opus 5"},"workspace":{"current_dir":"'"$DIR"'"},"context_window":{"remaining_percentage":45},"effort":{"level":"low"}}'
render "ctx low"       '{"model":{"display_name":"Claude Opus 5"},"workspace":{"current_dir":"'"$DIR"'"},"context_window":{"remaining_percentage":8},"effort":{"level":"low"}}'
render "no git"        '{"model":{"display_name":"Claude Opus 5"},"workspace":{"current_dir":"/tmp"},"context_window":{"remaining_percentage":72.4},"effort":{"level":"high"}}'
render "no context"    '{"model":{"display_name":"Claude Opus 5"},"workspace":{"current_dir":"'"$DIR"'"},"effort":{"level":"high"}}'
render "empty input"   '{}'
render "malformed"     'not json at all'
