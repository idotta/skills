#!/usr/bin/env bash
# Claude Code statusLine command
# Format: [Model] DirName  branch* | ctx 85% left
# Colorized with ANSI escapes.

input=$(cat)

# Parse JSON with python3 (no jq or node dependency: node is not on PATH in a
# non-interactive shell, where nvm is not loaded). One field per line.
parsed=$(printf '%s' "$input" | python3 -I -c '
import json, sys
try:
    j = json.load(sys.stdin)
except ValueError:
    j = {}
if not isinstance(j, dict):
    j = {}
g = lambda o, k: o.get(k) if isinstance(o, dict) else None
model = " ".join((g(g(j, "model"), "display_name") or "Claude").splitlines())
d = g(g(j, "workspace"), "current_dir") or ""
rem = g(g(j, "context_window"), "remaining_percentage")
effort = g(g(j, "effort"), "level") or ""
# Round here, not in bash: bash printf %.0f reads "72.4" against the shell
# locale and errors out where the decimal separator is a comma. Half up, as before.
sys.stdout.write("\n".join([model, d, "" if rem is None else str(int(float(rem) + 0.5)), effort]))
')

model=$(printf '%s' "$parsed" | sed -n '1p')
current_dir=$(printf '%s' "$parsed" | sed -n '2p')
remaining=$(printf '%s' "$parsed" | sed -n '3p')
effort=$(printf '%s' "$parsed" | sed -n '4p')

[ -z "$model" ] && model="Claude"
dir_name=$(basename "$current_dir")

# ANSI colors (256-color where useful)
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
MAGENTA=$'\033[38;5;170m'   # model
BLUE=$'\033[38;5;39m'       # dir
GREEN=$'\033[38;5;42m'      # branch / healthy ctx
YELLOW=$'\033[38;5;220m'    # mid ctx
RED=$'\033[38;5;203m'       # low ctx / dirty
GREY=$'\033[38;5;245m'      # separators
CYAN=$'\033[38;5;51m'       # effort level

# Git branch + dirty flag — skip optional locks to avoid contention
branch=""
dirty=""
if { [ -n "$current_dir" ] && [ -d "$current_dir/.git" ]; } || git -C "$current_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git -C "$current_dir" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
    if [ -n "$(git -C "$current_dir" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
        dirty="*"
    fi
fi

effort_label=""
if [ -n "$effort" ]; then
    effort_label=$(printf '%s' "$effort" | tr '[:upper:]' '[:lower:]')
fi

# Assemble output
sep="${GREY}|${RESET}"
model_label="${MAGENTA}${BOLD}${model}${RESET}"
[ -n "$effort_label" ] && model_label="${model_label} ${CYAN}- ${effort_label}${RESET}"
parts="${MAGENTA}${BOLD}[${RESET}${model_label}${MAGENTA}${BOLD}]${RESET} ${BLUE}${dir_name}${RESET}"

if [ -n "$branch" ]; then
    parts="${parts}  ${GREEN}⎇ ${branch}${RED}${dirty}${RESET}"
fi

if [ -n "$remaining" ]; then
    used=$((100 - remaining))
    if [ "$used" -ge 80 ]; then
        cc="$RED"
    elif [ "$used" -ge 50 ]; then
        cc="$YELLOW"
    else
        cc="$GREEN"
    fi
    parts="${parts} ${sep} ${DIM}ctx${RESET} ${cc}${used}%${RESET} ${DIM}used${RESET}"
fi

printf '%s\n' "$parts"
