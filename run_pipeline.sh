#!/usr/bin/env bash
#
# run_pipeline.sh — Spatial Transcriptomics pipeline runner
#
# Runs the analysis scripts in the required order:
#   1) ensemble_clustering.py
#   2) annotator.py        (uses ovarian_knowledge_base.py)
#   3) ai_agent.py         (needs OPENAI_API_KEY from .env)
#
# Usage:
#   ./run_pipeline.sh              # run all stages in order
#   ./run_pipeline.sh ensemble    # run a single stage (ensemble|annotator|agent)
#
# Aborts immediately if the GEF input file is missing or any stage fails.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

LOG_DIR="$PROJECT_DIR/logs"
RUN_TS="$(date +%Y%m%d_%H%M%S)"

# --- Resolve which Python to use ---------------------------------------------
# Preference order:
#   1) an already-active environment (conda or venv) — respect whatever the
#      caller has activated
#   2) the recommended conda env from environment.yml ("spatial-transcriptomics"),
#      found via `conda` on PATH
#   3) the same conda env, found by checking well-known install locations
#      directly — needed because launchd/cron run with a minimal PATH that
#      usually doesn't include Homebrew/Miniconda's bin directory, so step 2's
#      `command -v conda` silently fails even when conda is installed
#   4) a legacy .venv (the old pip/venv setup)
#   5) whatever python3 is on PATH
resolve_python() {
  if [[ -n "${CONDA_PREFIX:-}" || -n "${VIRTUAL_ENV:-}" ]] && command -v python3 >/dev/null 2>&1; then
    command -v python3
    return 0
  fi
  if command -v conda >/dev/null 2>&1; then
    local conda_py
    conda_py="$(conda run -n spatial-transcriptomics python -c 'import sys; print(sys.executable)' 2>/dev/null || true)"
    if [[ -n "$conda_py" && -x "$conda_py" ]]; then
      echo "$conda_py"
      return 0
    fi
  fi
  local base candidate
  for base in \
    "$HOME/miniconda3" \
    "$HOME/anaconda3" \
    "$HOME/miniforge3" \
    "/opt/homebrew/Caskroom/miniconda/base" \
    "/opt/homebrew/Caskroom/miniforge/base" \
    "/usr/local/Caskroom/miniconda/base" \
    "/opt/miniconda3" \
    "/opt/anaconda3"
  do
    candidate="$base/envs/spatial-transcriptomics/bin/python"
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  if [[ -x "$PROJECT_DIR/.venv/bin/python" ]]; then
    echo "$PROJECT_DIR/.venv/bin/python"
    return 0
  fi
  command -v python3 2>/dev/null
}

PY="$(resolve_python || true)"

# --- Load secrets / overrides (.env defines OPENAI_API_KEY, optional ST_* vars) ---
if [[ -f "$PROJECT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$PROJECT_DIR/.env"
fi

# Resolve the GEF input:
#   1) explicit ST_INPUT_GEF wins
#   2) else auto-detect if exactly one *.gef exists in the folder
# No hardcoded filename — this works with anyone's data, not just one sample.
GEF="${ST_INPUT_GEF:-}"
if [[ -z "$GEF" ]]; then
  shopt -s nullglob
  gef_matches=("$PROJECT_DIR"/*.gef)
  shopt -u nullglob
  if [[ ${#gef_matches[@]} -eq 1 ]]; then
    GEF="${gef_matches[0]}"
  elif [[ ${#gef_matches[@]} -gt 1 ]]; then
    echo "ERROR: multiple .gef files found; set ST_INPUT_GEF to pick one:" >&2
    printf '       %s\n' "${gef_matches[@]}" >&2
    exit 2
  fi
fi

# --- Preflight checks --------------------------------------------------------
if [[ -z "$PY" || ! -x "$PY" ]]; then
  echo "ERROR: could not find a Python interpreter to run the pipeline with." >&2
  echo "       Set up the environment first (recommended):" >&2
  echo "         conda env create -f environment.yml" >&2
  echo "       or, for the legacy pip/venv setup:" >&2
  echo "         python3 -m venv .venv && ./.venv/bin/pip install -r requirements.txt" >&2
  exit 1
fi
echo "Using Python: $PY"

if [[ -z "$GEF" || ! -f "$GEF" ]]; then
  echo "ERROR: no GEF input file found." >&2
  echo "       Place a single .gef file in $PROJECT_DIR, or set \$ST_INPUT_GEF" >&2
  echo "       to an explicit path, and re-run." >&2
  exit 2
fi

export ST_INPUT_GEF="$GEF"
export ST_RUN_ID="$RUN_TS"
mkdir -p "$LOG_DIR"

# How often to print a "still running" heartbeat while a stage executes.
# Override with $ST_HEARTBEAT_SECS if you want it chattier/quieter.
HEARTBEAT_SECS="${ST_HEARTBEAT_SECS:-60}"

format_duration() {
  local total=$1 m s
  m=$(( total / 60 ))
  s=$(( total % 60 ))
  if [[ $m -gt 0 ]]; then
    printf '%dm%02ds' "$m" "$s"
  else
    printf '%ds' "$s"
  fi
}

run_stage() {
  local name="$1" script="$2"
  local log="$LOG_DIR/${RUN_TS}_${name}.log"
  echo ">>> [$name] starting: $script"
  echo "    input : $ST_INPUT_GEF"
  echo "    log   : $log"
  local start; start=$(date +%s)

  "$PY" "$script" >"$log" 2>&1 &
  local pid=$!

  # Heartbeat so long silent stretches (clustering/embedding steps can run
  # many minutes with no console output) don't look like the pipeline hung.
  while kill -0 "$pid" 2>/dev/null; do
    sleep "$HEARTBEAT_SECS"
    if kill -0 "$pid" 2>/dev/null; then
      local elapsed=$(( $(date +%s) - start ))
      echo "    ... [$name] still running (elapsed: $(format_duration "$elapsed"))"
    fi
  done

  local status
  if wait "$pid"; then
    status=0
  else
    status=$?
  fi

  if [[ $status -eq 0 ]]; then
    local dur=$(( $(date +%s) - start ))
    echo "<<< [$name] done in $(format_duration "$dur")"
  else
    echo "!!! [$name] FAILED (exit $status) — see $log (last lines below):" >&2
    tail -20 "$log" >&2
    exit 3
  fi
}

# --- Notify on completion (success or failure) --------------------------------
# Mirrors what watch_runner.py/watch_runner.sh do for automatic runs, so a
# manual ./run_pipeline.sh also emails/desktop-notifies you when it's done.
# Best-effort: notify.py itself no-ops email if GMAIL_* isn't set in .env.
PIPELINE_START=$(date +%s)
notify_on_exit() {
  local exit_code=$?
  trap - EXIT
  local total_dur=$(( $(date +%s) - PIPELINE_START ))
  local status="SUCCESS"
  [[ $exit_code -ne 0 ]] && status="FAILED"
  local summary="Spatial Transcriptomics pipeline $status in $(format_duration "$total_dur") — file: $(basename "$GEF"). Logs: $LOG_DIR"
  echo "$summary"
  if [[ -n "${PY:-}" && -f "$PROJECT_DIR/notify.py" ]]; then
    "$PY" "$PROJECT_DIR/notify.py" "ST pipeline: $status" "$summary" || true
  fi
  exit "$exit_code"
}
trap notify_on_exit EXIT

STAGE="${1:-all}"
echo "=== Spatial Transcriptomics pipeline | run $RUN_TS | stage=$STAGE ==="

case "$STAGE" in
  ensemble)  run_stage ensemble  ensemble_clustering.py ;;
  annotator) run_stage annotator annotator.py ;;
  agent)     run_stage agent     ai_agent.py ;;
  all)
    run_stage ensemble  ensemble_clustering.py
    run_stage annotator annotator.py
    run_stage agent     ai_agent.py
    ;;
  *)
    echo "ERROR: unknown stage '$STAGE' (use: ensemble | annotator | agent | all)" >&2
    exit 1
    ;;
esac

echo "=== pipeline complete ==="
