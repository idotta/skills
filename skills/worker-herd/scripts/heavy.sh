#!/usr/bin/env bash
# Runs a heavy command (build, full test suite, stress) in one of a few shared slots, so parallel workers on one
# machine take turns instead of all running at once.
#
#   heavy.sh [--all] [--deadline 30m] -- <command...>
#
#   (default)   take any one free slot: builds, full test suites, lint, e2e
#   --all       take every slot, so nothing else heavy runs: stress runs, timing-sensitive measurements
#   --deadline  bound a hang: on expiry, dump the stacks of every .NET process under the command, then kill it
#
#   HEAVY_SLOTS  slots on this machine (default 2)
#   HEAVY_DIR    lock folder (default ~/.herdr/worktrees/<repo>; shared by every worktree of the repo)
#
# Exit code is the command's; 124 means the deadline killed it (stacks are in $HEAVY_DIR/stacks-<time>.txt).
set -uo pipefail

all=0 deadline=""
while [ $# -gt 0 ]; do
  case "$1" in
    --all) all=1; shift ;;
    --deadline) deadline="$2"; shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || { echo "usage: heavy.sh [--all] [--deadline 30m] -- <command...>" >&2; exit 2; }

slots="${HEAVY_SLOTS:-2}"
if [ -z "${HEAVY_DIR:-}" ]; then
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || { echo "heavy.sh: not in a git repo; set HEAVY_DIR" >&2; exit 2; }
  HEAVY_DIR="$HOME/.herdr/worktrees/$(basename "$(dirname "$common")")"
fi
mkdir -p "$HEAVY_DIR"

# Slots are taken in a fixed order, so two --all callers can't deadlock; a single-slot caller never waits on a second.
if [ "$all" = 1 ]; then
  for i in $(seq 1 "$slots"); do
    exec {fd}>"$HEAVY_DIR/heavy.$i"
    flock "$fd"
  done
else
  got=0
  while [ "$got" = 0 ]; do
    for i in $(seq 1 "$slots"); do
      exec {fd}>"$HEAVY_DIR/heavy.$i"
      if flock -n "$fd"; then got=1; break; fi
      exec {fd}>&-
    done
    [ "$got" = 1 ] || sleep 5
  done
fi
echo "heavy.sh: running (load $(cut -d' ' -f1 /proc/loadavg)): $*" >&2

if [ -z "$deadline" ]; then
  "$@"
  exit $?
fi

setsid "$@" &
cmd=$!
timeout "$deadline" tail --pid="$cmd" -f /dev/null
if kill -0 "$cmd" 2>/dev/null; then
  out="$HEAVY_DIR/stacks-$(date +%Y%m%dT%H%M%S).txt"
  {
    echo "deadline $deadline passed: $*"
    for p in $(pstree -p "$cmd" | grep -o '([0-9]\+)' | tr -d '()'); do
      if grep -q libcoreclr "/proc/$p/maps" 2>/dev/null; then
        echo "=== pid $p: $(tr '\0' ' ' < "/proc/$p/cmdline" | cut -c1-200) (cpu $(ps -o time= -p "$p"))"
        command -v dotnet-stack >/dev/null && dotnet-stack report -p "$p" 2>&1
      fi
    done
  } > "$out"
  kill -TERM -- "-$cmd" 2>/dev/null
  sleep 5; kill -KILL -- "-$cmd" 2>/dev/null
  echo "heavy.sh: deadline $deadline passed; stacks in $out" >&2
  exit 124
fi
wait "$cmd"
