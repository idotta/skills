#!/usr/bin/env bash
# Install the bundled status line and register it in settings.json.
#
#   install.sh              # personal:  ~/.claude/
#   install.sh --project    # this repo: ./.claude/   (committed, shared)
#   install.sh --dir DIR    # explicit target directory
#
# Idempotent: re-running overwrites the script and rewrites the statusLine
# entry, leaving every other setting untouched. Existing files are backed up
# with a .bak-<timestamp> suffix so nothing is lost silently.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$SKILL_DIR/assets/statusline-command.sh"
TARGET_DIR="$HOME/.claude"

while [ $# -gt 0 ]; do
    case "$1" in
        --project) TARGET_DIR="$PWD/.claude"; shift ;;
        --dir)     TARGET_DIR="$2"; shift 2 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "install.sh: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

[ -f "$SRC" ] || { echo "install.sh: missing bundled script at $SRC" >&2; exit 1; }
command -v node >/dev/null 2>&1 || {
    echo "install.sh: node is required (the status line parses its JSON input with it)" >&2
    exit 1
}

mkdir -p "$TARGET_DIR"
DEST="$TARGET_DIR/statusline-command.sh"
SETTINGS="$TARGET_DIR/settings.json"
STAMP=$(date +%Y%m%d-%H%M%S)

if [ -f "$DEST" ] && ! cmp -s "$SRC" "$DEST"; then
    cp "$DEST" "$DEST.bak-$STAMP"
    echo "backed up existing script -> $DEST.bak-$STAMP"
fi
cp "$SRC" "$DEST"
chmod +x "$DEST"
echo "installed $DEST"

[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak-$STAMP"

# Patch settings.json in place: read what is there (or start from {}), set only
# the statusLine key, write it back with 2-space indent. Everything else in the
# file survives untouched.
SETTINGS="$SETTINGS" DEST="$DEST" node -e '
  const fs = require("fs");
  const path = process.env.SETTINGS;
  let cfg = {};
  if (fs.existsSync(path)) {
    const raw = fs.readFileSync(path, "utf8").trim();
    if (raw) {
      try {
        cfg = JSON.parse(raw);
      } catch (e) {
        console.error("install.sh: " + path + " is not valid JSON (" + e.message + ").");
        console.error("A backup was made; fix the file by hand, then re-run.");
        process.exit(1);
      }
    }
  }
  cfg.statusLine = { type: "command", command: "bash " + process.env.DEST };
  fs.writeFileSync(path, JSON.stringify(cfg, null, 2) + "\n");
'
echo "registered statusLine in $SETTINGS"

# Prove it renders before claiming success — a status line that throws just
# shows up blank, with no error anywhere the user will see.
SAMPLE='{"model":{"display_name":"Claude Opus 5"},"workspace":{"current_dir":"'"$PWD"'"},"context_window":{"remaining_percentage":72.4},"effort":{"level":"high"}}'
echo "preview:"
printf '%s' "$SAMPLE" | bash "$DEST"
echo "Open a new Claude Code session (or run /statusline) to see it live."
