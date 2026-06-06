#!/usr/bin/env bash
set -euo pipefail

# install.sh — install agent-learn-mode into a target project.
#
# Usage:
#   ./install.sh [--target DIR] [--mode copy|submodule] [--wall hard|soft|off] [--repo URL]
#
# Interactive if --mode / --wall are omitted. Idempotent: safe to re-run.
#
# Examples:
#   cd ~/projects/my-app && bash ~/projects/agent-learn-mode/install.sh
#   bash install.sh --target ~/projects/my-app --mode copy --wall hard

# --- locate the SOURCE (this repo) independently of where we're invoked from ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_AI="$SCRIPT_DIR/.ai"

MARKER_START="<!-- agent-learn-mode:start -->"
MARKER_END="<!-- agent-learn-mode:end -->"
WALL_TOOLS='["Edit","Write","MultiEdit","NotebookEdit"]'
SUBMODULE_PATH=".agent-learn"

TARGET="$PWD"
MODE="" ; WALL="" ; REPO=""

usage() { sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'; }

# --- args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2;;
    --mode)   MODE="$2";   shift 2;;
    --wall)   WALL="$2";   shift 2;;
    --repo)   REPO="$2";   shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1;;
  esac
done

# --- sanity ---
[[ -d "$SOURCE_AI" ]] || { echo "ERROR: source '.ai/' not found next to install.sh ($SOURCE_AI)" >&2; exit 1; }
[[ -d "$TARGET" ]]    || { echo "ERROR: target dir does not exist: $TARGET" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"   # absolutize

# --- interactive fallback ---
if [[ -z "$MODE" ]]; then
  echo "Install mode into $TARGET:"
  select m in "copy (simplest)" "submodule (central updates)"; do
    [[ -n "${m:-}" ]] && { MODE="${m%% *}"; break; }
  done
fi
if [[ -z "$WALL" ]]; then
  echo "Wall mode (blocks the agent from writing code):"
  select w in "hard (deny)" "soft (ask each time)" "off"; do
    [[ -n "${w:-}" ]] && { WALL="${w%% *}"; break; }
  done
fi

# --- dependency checks ---
if [[ "$WALL" != "off" ]] && ! command -v jq >/dev/null; then
  echo "ERROR: jq is required to set the wall safely. Install jq or run with --wall off." >&2
  exit 1
fi

backup() { if [[ -f "$1" ]]; then cp "$1" "$1.bak.$(date +%s)"; fi; }

# --- 1. place source files, decide the import prefix ---
case "$MODE" in
  copy)
    mkdir -p "$TARGET/.ai"
    cp -R "$SOURCE_AI/." "$TARGET/.ai/"   # copy CONTENTS; idempotent, no .ai/.ai nesting
    AI_PREFIX=".ai"
    ;;
  submodule)
    command -v git >/dev/null || { echo "ERROR: git required for submodule mode." >&2; exit 1; }
    git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
      || { echo "ERROR: target is not a git repo; submodule mode needs one (run 'git init' first)." >&2; exit 1; }
    REPO="${REPO:-$SCRIPT_DIR}"   # default to this local repo path
    if [[ ! -e "$TARGET/$SUBMODULE_PATH" ]]; then
      git -C "$TARGET" submodule add "$REPO" "$SUBMODULE_PATH"
    else
      echo "note: $SUBMODULE_PATH already present, skipping submodule add."
    fi
    AI_PREFIX="$SUBMODULE_PATH/.ai"
    ;;
  *) echo "ERROR: unknown mode '$MODE'." >&2; exit 1;;
esac

# --- 2. inject import block into CLAUDE.md (plain text, NOT a code fence) ---
CLAUDE_MD="$TARGET/CLAUDE.md"
BLOCK="$MARKER_START
# Learning mode — the agent guides, it does not write code for me. Full contract in the imports below.
@$AI_PREFIX/core.md
@$AI_PREFIX/phases.md
@$AI_PREFIX/handoff.md
$MARKER_END"

backup "$CLAUDE_MD"
touch "$CLAUDE_MD"
if grep -qF "$MARKER_START" "$CLAUDE_MD"; then
  # strip the previous block so re-runs don't duplicate / can update the prefix
  tmp="$(mktemp)"
  awk -v s="$MARKER_START" -v e="$MARKER_END" '
    $0==s {skip=1} skip && $0==e {skip=0; next} !skip {print}' "$CLAUDE_MD" > "$tmp"
  mv "$tmp" "$CLAUDE_MD"
fi
printf '\n%s\n' "$BLOCK" >> "$CLAUDE_MD"

# --- 3. set the wall in .claude/settings.json (merge, don't clobber) ---
SETTINGS="$TARGET/.claude/settings.json"
case "$WALL" in
  hard) KEY="deny"; OTHER="ask"  ;;
  soft) KEY="ask";  OTHER="deny" ;;
  off)  KEY=""                   ;;   # leave settings.json untouched
  *) echo "ERROR: unknown wall '$WALL'." >&2; exit 1;;
esac

if [[ -n "$KEY" ]]; then
  mkdir -p "$TARGET/.claude"
  backup "$SETTINGS"
  [[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"
  tmp="$(mktemp)"
  # add tools to the chosen list (deduped); remove them from the other list to avoid deny/ask conflicts
  jq --argjson tools "$WALL_TOOLS" --arg key "$KEY" --arg other "$OTHER" '
    .permissions = (.permissions // {})
    | .permissions[$key]   = (((.permissions[$key]  // []) + $tools) | unique)
    | .permissions[$other] = ((.permissions[$other] // []) - $tools)
  ' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
  # validate: a parse failure here would silently disable the wall
  jq . "$SETTINGS" >/dev/null || { echo "ERROR: settings.json did not validate — check $SETTINGS and its .bak.* backup." >&2; exit 1; }
fi

# --- summary + smoke test ---
cat <<EOF

Installed agent-learn-mode into: $TARGET
  mode : $MODE   (imports use prefix '@$AI_PREFIX/...')
  wall : $WALL$([[ -n "$KEY" ]] && echo "  -> permissions.$KEY += Edit/Write/MultiEdit/NotebookEdit" || true)

Verify (do all three):
  1) start Claude Code in $TARGET, run  /memory  -> core.md, phases.md, handoff.md must be listed
  2) jq . "$SETTINGS"   -> parses cleanly
  3) ask the agent to edit a file -> it must refuse (hard) or prompt (soft)

Backups (*.bak.*) were written next to any file this script changed. Re-running is safe.
EOF