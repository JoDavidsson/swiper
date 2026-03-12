#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="/Users/johannesdavidsson/Cursor Projects/Swiper"
OUT_DIR="$REPO_ROOT/output/autoresearch/2026-03-11-deep-ranker-research-04"
LOG_DIR="$OUT_DIR/logs"
RESULTS_TSV="$OUT_DIR/results.tsv"

mkdir -p "$LOG_DIR"

printf 'config\toracle_metric\toracle_failed\tlikes_metric\tlikes_failed\tprobe_variant\tprobe_rank_window\tprobe_rank_window_multiplier\tprobe_candidate_count\tprobe_exploration_rate\tprobe_mmr_enabled\tprobe_mmr_applied\n' > "$RESULTS_TSV"

run_config() {
  local cfg_line="$1"
  IFS='|' read -r name env_vars <<< "$cfg_line"

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

  local probe_variant probe_rank_window probe_rank_window_multiplier probe_candidate_count probe_explore probe_mmr_enabled probe_mmr_applied
  probe_variant=$(jq -r '.rank.variant // "NA"' "$probe_json")
  probe_rank_window=$(jq -r '.rank.rankWindow // "NA"' "$probe_json")
  probe_rank_window_multiplier=$(jq -r '.rank.rankWindowMultiplier // "NA"' "$probe_json")
  probe_candidate_count=$(jq -r '.rank.candidateCount // "NA"' "$probe_json")
  probe_explore=$(jq -r '.rank.adaptiveExploration.effectiveRate // "NA"' "$probe_json")
  probe_mmr_enabled=$(jq -r 'if (.rank | has("mmrPolicy")) then (.rank.mmrPolicy.enabled|tostring) else "NA" end' "$probe_json")
  probe_mmr_applied=$(jq -r 'if (.rank | has("mmrPolicy")) then (.rank.mmrPolicy.applied|tostring) else "NA" end' "$probe_json")

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$oracle_metric" "${oracle_failed:-NA}" "$likes_metric" "${likes_failed:-NA}" \
    "$probe_variant" "$probe_rank_window" "$probe_rank_window_multiplier" "$probe_candidate_count" \
    "$probe_explore" "$probe_mmr_enabled" "$probe_mmr_applied" \
    >> "$RESULTS_TSV"

  echo "Done: $name (oracle=$oracle_metric likes=$likes_metric rankWindow=$probe_rank_window)"
}

CONFIGS=(
  "wide_win12_exp0|RANKER_ENABLE_MMR_RERANK=false RANKER_ADAPTIVE_EXPLORATION_ENABLED=false RANKER_EXPLORATION_RATE=0 DECK_ITEMS_FETCH_LIMIT=2000 DECK_CANDIDATE_CAP=1200 DECK_RANK_WINDOW_MULTIPLIER=12"
  "wide_win24_exp0|RANKER_ENABLE_MMR_RERANK=false RANKER_ADAPTIVE_EXPLORATION_ENABLED=false RANKER_EXPLORATION_RATE=0 DECK_ITEMS_FETCH_LIMIT=2000 DECK_CANDIDATE_CAP=1200 DECK_RANK_WINDOW_MULTIPLIER=24"
  "wide_win36_exp0|RANKER_ENABLE_MMR_RERANK=false RANKER_ADAPTIVE_EXPLORATION_ENABLED=false RANKER_EXPLORATION_RATE=0 DECK_ITEMS_FETCH_LIMIT=2000 DECK_CANDIDATE_CAP=1200 DECK_RANK_WINDOW_MULTIPLIER=36"
  "wide_win48_exp0|RANKER_ENABLE_MMR_RERANK=false RANKER_ADAPTIVE_EXPLORATION_ENABLED=false RANKER_EXPLORATION_RATE=0 DECK_ITEMS_FETCH_LIMIT=2000 DECK_CANDIDATE_CAP=1200 DECK_RANK_WINDOW_MULTIPLIER=48"
  "wide_win72_exp0|RANKER_ENABLE_MMR_RERANK=false RANKER_ADAPTIVE_EXPLORATION_ENABLED=false RANKER_EXPLORATION_RATE=0 DECK_ITEMS_FETCH_LIMIT=2000 DECK_CANDIDATE_CAP=1200 DECK_RANK_WINDOW_MULTIPLIER=72"
  "wide_win24_exp8|RANKER_ENABLE_MMR_RERANK=false RANKER_ADAPTIVE_EXPLORATION_ENABLED=false RANKER_EXPLORATION_RATE=0.08 DECK_ITEMS_FETCH_LIMIT=2000 DECK_CANDIDATE_CAP=1200 DECK_RANK_WINDOW_MULTIPLIER=24"
  "wide_win48_exp8|RANKER_ENABLE_MMR_RERANK=false RANKER_ADAPTIVE_EXPLORATION_ENABLED=false RANKER_EXPLORATION_RATE=0.08 DECK_ITEMS_FETCH_LIMIT=2000 DECK_CANDIDATE_CAP=1200 DECK_RANK_WINDOW_MULTIPLIER=48"
)

for cfg in "${CONFIGS[@]}"; do
  run_config "$cfg"
done

echo "=== Wide window matrix complete ==="
echo "Results: $RESULTS_TSV"
