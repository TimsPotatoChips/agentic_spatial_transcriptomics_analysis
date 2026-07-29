#!/usr/bin/env bash
#
# watch_runner.sh — launchd-triggered handler for new GEF drops.
#
# Fired by the com.minjun.sttx-watch LaunchAgent whenever the project folder
# changes. Runs the pipeline once per newly-dropped *.gef, then notifies.
#
# Loop-safety: the pipeline writes outputs back into the watched folder, which
# re-fires this watcher. All watcher state lives OUTSIDE the folder, and we
# silently no-op when (a) no new GEF, (b) the GEF was already processed, or
# (c) a run is already in progress. So re-fires cost ~nothing.

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/Library/Logs/sttx-watch"
# notify.py only uses the standard library, so any system python3 works here —
# the actual pipeline environment (conda/venv) is resolved separately inside
# run_pipeline.sh.
PY="$(command -v python3 || echo python3)"

mkdir -p "$STATE_DIR"
LOCK="$STATE_DIR/run.lock"
PROCESSED="$STATE_DIR/processed.list"
WLOG="$STATE_DIR/watch.log"
touch "$PROCESSED"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$WLOG"; }

cd "$PROJECT_DIR" 2>/dev/null || exit 0
# shellcheck disable=SC1091
[[ -f "$PROJECT_DIR/.env" ]] && source "$PROJECT_DIR/.env" 2>/dev/null || true

# --- find newest *.gef (silent exit if none) --------------------------------
shopt -s nullglob
gefs=("$PROJECT_DIR"/*.gef)
shopt -u nullglob
[[ ${#gefs[@]} -eq 0 ]] && exit 0

newest=""; newest_mt=0
for g in "${gefs[@]}"; do
  mt=$(stat -f %m "$g" 2>/dev/null || echo 0)
  if (( mt > newest_mt )); then newest_mt=$mt; newest="$g"; fi
done
[[ -z "$newest" ]] && exit 0

# Identify this drop by path+size; re-dropping a different file reruns.
sig="$newest:$(stat -f %z "$newest" 2>/dev/null || echo 0)"
grep -qxF "$sig" "$PROCESSED" 2>/dev/null && exit 0

# --- atomic lock; silent exit if a run is active (prevents retrigger churn) --
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# Wait for the file size to stop changing (it may still be copying in).
prev=-1; cur=0
for _ in $(seq 1 60); do
  cur=$(stat -f %z "$newest" 2>/dev/null || echo 0)
  [[ "$cur" == "$prev" && "$cur" != "0" ]] && break
  prev=$cur; sleep 2
done

log "New GEF detected: $newest (size ${cur}B). Starting pipeline."
export ST_INPUT_GEF="$newest"
start=$(date +%s)
if "$PROJECT_DIR/run_pipeline.sh" >> "$WLOG" 2>&1; then
  status="SUCCESS"
else
  status="FAILED (exit $?)"
fi
dur=$(( $(date +%s) - start ))

# Mark processed (success or fail) so output-write re-fires don't loop.
echo "$sig" >> "$PROCESSED"

summary="Spatial Transcriptomics pipeline ${status} in ${dur}s — file: $(basename "$newest"). Outputs in project folder; details: $WLOG"
log "$summary"
"$PY" "$PROJECT_DIR/notify.py" "ST pipeline: ${status}" "$summary" >> "$WLOG" 2>&1 || true
