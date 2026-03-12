#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="/Users/johannesdavidsson/Cursor Projects/Swiper"
OUT_DIR="$REPO_ROOT/output/autoresearch/2026-03-11-deep-ranker-research-03"
LOG_DIR="$OUT_DIR/logs"
RESULTS_TSV="$OUT_DIR/results.tsv"

mkdir -p "$LOG_DIR"

printf 'config\toracle_metric\toracle_failed\tlikes_metric\tlikes_failed\tprobe_variant\tprobe_rank_window\tprobe_candidate_count\tprobe_exploration_rate\tprobe_mmr_enabled\tprobe_mmr_applied\tconfig_validation\n' > "$RESULTS_TSV"

run_config() {
  local cfg_line="$1"
  IFS='|' read -r name env_vars expected_explore expected_mmr <<< "$cfg_line"

  echo "=== Running config: $name ==="

  local oracle_log="$LOG_DIR/${name}_oracle.log"
  local likes_log="$LOG_DIR/${name}_likes.log"
  local probe_json="$LOG_DIR/${name}_probe.json"
  local run_log="$LOG_DIR/${name}_emulators_exec.log"
  local inner_script="$LOG_DIR/${name}_inside.sh"

  cat > "$inner_script" <<INNER
#!/usr/bin/env bash
set -euo pipefail
cd "$REPO_ROOT/firebase/functions"
export FIRESTORE_EMULATOR_HOST=localhost:8180

node scripts/generate_fake_db.js \
  --users 250 \
  --interactions-per-user 20 \
  --item-pool-limit 5000 \
  --seed 42 \
  > "$LOG_DIR/${name}_generator.log" 2>&1

node scripts/offline_eval_liked_topk.js \
  --sessions-prefix synth_ \
  --max-sessions 250 \
  --limit 10 \
  --requests-per-session 2 \
  --ground-truth-mode oracle_preference \
  --oracle-top-k 10 \
  --concurrency 8 \
  > "$oracle_log" 2>&1

node scripts/offline_eval_liked_topk.js \
  --sessions-prefix synth_ \
  --max-sessions 250 \
  --limit 10 \
  --requests-per-session 2 \
  --ground-truth-mode likes \
  --oracle-top-k 10 \
  --concurrency 8 \
  > "$likes_log" 2>&1

curl -s "http://127.0.0.1:5002/swiper-95482/europe-west1/api/items/deck?sessionId=synth_1&limit=10" > "$probe_json"
INNER
  chmod +x "$inner_script"

  local -a env_array=()
  if [ -n "$env_vars" ]; then
    # shellcheck disable=SC2206
    env_array=($env_vars)
  fi

  (
    cd "$REPO_ROOT"
    env "${env_array[@]}" firebase emulators:exec \
      --only firestore,functions,auth \
      --import emulator-data \
      --export-on-exit emulator-data \
      "bash '$inner_script'" \
      > "$run_log" 2>&1
  )

  local oracle_metric oracle_failed likes_metric likes_failed
  oracle_metric=$(awk '/^primary_metric_liked_in_top_k:/ {print $2}' "$oracle_log" | tail -n 1)
  oracle_failed=$(awk '/^offline_eval_sessions_failed:/ {print $2}' "$oracle_log" | tail -n 1)
  likes_metric=$(awk '/^primary_metric_liked_in_top_k:/ {print $2}' "$likes_log" | tail -n 1)
  likes_failed=$(awk '/^offline_eval_sessions_failed:/ {print $2}' "$likes_log" | tail -n 1)

  if [ -z "$oracle_metric" ] || [ -z "$likes_metric" ]; then
    echo "ERROR: missing metric for $name" >&2
    echo "See logs: $oracle_log $likes_log $run_log" >&2
    exit 1
  fi

  local probe_variant probe_rank_window probe_candidate_count probe_explore probe_mmr_enabled probe_mmr_applied
  probe_variant=$(jq -r '.rank.variant // "NA"' "$probe_json")
  probe_rank_window=$(jq -r '.rank.rankWindow // "NA"' "$probe_json")
  probe_candidate_count=$(jq -r '.rank.candidateCount // "NA"' "$probe_json")
  probe_explore=$(jq -r '.rank.adaptiveExploration.effectiveRate // "NA"' "$probe_json")
  probe_mmr_enabled=$(jq -r '.rank.mmrPolicy.enabled // "NA"' "$probe_json")
  probe_mmr_applied=$(jq -r '.rank.mmrPolicy.applied // "NA"' "$probe_json")

  local validation="ok"
  if [ "$probe_explore" != "$expected_explore" ]; then
    validation="unexpected_exploration"
  fi
  if [ "$probe_mmr_enabled" != "$expected_mmr" ]; then
    if [ "$validation" = "ok" ]; then
      validation="unexpected_mmr"
    else
      validation="unexpected_exploration_and_mmr"
    fi
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$oracle_metric" "${oracle_failed:-NA}" "$likes_metric" "${likes_failed:-NA}" \
    "$probe_variant" "$probe_rank_window" "$probe_candidate_count" "$probe_explore" \
    "$probe_mmr_enabled" "$probe_mmr_applied" "$validation" \
    >> "$RESULTS_TSV"

  echo "Done: $name (oracle=$oracle_metric likes=$likes_metric validation=$validation)"
}

CONFIGS=(
  "baseline_default|RANKER_ENABLE_MMR_RERANK=false RANKER_ADAPTIVE_EXPLORATION_ENABLED=false RANKER_EXPLORATION_RATE=0.08|0.08|false"
  "no_exploration|RANKER_ENABLE_MMR_RERANK=false RANKER_ADAPTIVE_EXPLORATION_ENABLED=false RANKER_EXPLORATION_RATE=0|0|false"
  "low_exploration|RANKER_ENABLE_MMR_RERANK=false RANKER_ADAPTIVE_EXPLORATION_ENABLED=false RANKER_EXPLORATION_RATE=0.04|0.04|false"
  "high_exploration|RANKER_ENABLE_MMR_RERANK=false RANKER_ADAPTIVE_EXPLORATION_ENABLED=false RANKER_EXPLORATION_RATE=0.12|0.12|false"
  "wide_pool_no_exploration|RANKER_ENABLE_MMR_RERANK=false RANKER_ADAPTIVE_EXPLORATION_ENABLED=false RANKER_EXPLORATION_RATE=0 DECK_ITEMS_FETCH_LIMIT=2000 DECK_CANDIDATE_CAP=1200|0|false"
  "wide_pool_default_exploration|RANKER_ENABLE_MMR_RERANK=false RANKER_ADAPTIVE_EXPLORATION_ENABLED=false RANKER_EXPLORATION_RATE=0.08 DECK_ITEMS_FETCH_LIMIT=2000 DECK_CANDIDATE_CAP=1200|0.08|false"
  "wide_pool_mmr95_no_exploration|RANKER_ENABLE_MMR_RERANK=true RANKER_MMR_LAMBDA=0.95 RANKER_MMR_TOP_N_MULTIPLIER=3 RANKER_ADAPTIVE_EXPLORATION_ENABLED=false RANKER_EXPLORATION_RATE=0 DECK_ITEMS_FETCH_LIMIT=2000 DECK_CANDIDATE_CAP=1200|0|true"
  "wide_pool_mmr95_default_exploration|RANKER_ENABLE_MMR_RERANK=true RANKER_MMR_LAMBDA=0.95 RANKER_MMR_TOP_N_MULTIPLIER=3 RANKER_ADAPTIVE_EXPLORATION_ENABLED=false RANKER_EXPLORATION_RATE=0.08 DECK_ITEMS_FETCH_LIMIT=2000 DECK_CANDIDATE_CAP=1200|0.08|true"
)

for cfg in "${CONFIGS[@]}"; do
  run_config "$cfg"
done

echo "=== Matrix complete ==="
echo "Results: $RESULTS_TSV"
