#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="/Users/johannesdavidsson/Cursor Projects/Swiper"
OUT_DIR="$REPO_ROOT/output/autoresearch/2026-03-12-deep-ranker-research-07"
LOG_DIR="$OUT_DIR/logs"
RESULTS_TSV="$OUT_DIR/results.tsv"

mkdir -p "$LOG_DIR"

printf 'config\toracle_metric\tlikes_metric\tprobe_rank_window\tprobe_candidate_count\tprobe_cache_enabled\tprobe_cache_hit\tlatency_count\tlatency_avg_ms\tlatency_p95_ms\tlatency_max_ms\n' > "$RESULTS_TSV"

latency_stats() {
  local run_log="$1"
  local vals
  vals=$(rg -o 'latencyMs: [0-9]+' "$run_log" | awk '{print $2}')

  local count avg p95 max
  count=$(printf '%s\n' "$vals" | awk 'NF{c++} END{print c+0}')
  avg=$(printf '%s\n' "$vals" | awk 'NF{s+=$1;c++} END{if(c>0) printf "%.2f", s/c; else print "NA"}')
  p95=$(printf '%s\n' "$vals" | awk 'NF{print $1}' | sort -n | awk '{a[NR]=$1} END{if(NR==0){print "NA"} else {idx=int(0.95*NR); if(idx<1) idx=1; if(idx>NR) idx=NR; print a[idx]}}')
  max=$(printf '%s\n' "$vals" | awk 'NF{if($1>m)m=$1} END{if(m==0){print "NA"} else {print m}}')

  printf '%s\t%s\t%s\t%s\n' "$count" "$avg" "$p95" "$max"
}

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

  local oracle_metric likes_metric
  oracle_metric=$(awk '/^primary_metric_liked_in_top_k:/ {print $2}' "$oracle_log" | tail -n 1)
  likes_metric=$(awk '/^primary_metric_liked_in_top_k:/ {print $2}' "$likes_log" | tail -n 1)

  local probe_rank_window probe_candidate_count probe_cache_enabled probe_cache_hit
  probe_rank_window=$(jq -r '.rank.rankWindow // "NA"' "$probe_json")
  probe_candidate_count=$(jq -r '.rank.candidateCount // "NA"' "$probe_json")
  probe_cache_enabled=$(jq -r '.rank.retrievalCache.enabled // "NA"' "$probe_json")
  probe_cache_hit=$(jq -r '.rank.retrievalCache.hit // "NA"' "$probe_json")

  local latency_count latency_avg latency_p95 latency_max
  read -r latency_count latency_avg latency_p95 latency_max < <(latency_stats "$run_log")

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$oracle_metric" "$likes_metric" "$probe_rank_window" "$probe_candidate_count" \
    "$probe_cache_enabled" "$probe_cache_hit" "$latency_count" "$latency_avg" "$latency_p95" "$latency_max" \
    >> "$RESULTS_TSV"

  echo "Done: $name (oracle=$oracle_metric likes=$likes_metric avgLatencyMs=$latency_avg p95Ms=$latency_p95 cacheHit=$probe_cache_hit)"
}

COMMON_ENVS="RANKER_ENABLE_MMR_RERANK=false RANKER_ADAPTIVE_EXPLORATION_ENABLED=false RANKER_EXPLORATION_RATE=0 DECK_RANK_WINDOW_MULTIPLIER=48"

CONFIGS=(
  "cap800_cache_off|$COMMON_ENVS DECK_CANDIDATE_CAP=800 DECK_ITEMS_FETCH_LIMIT=1400 DECK_RETRIEVAL_DOCS_CACHE_TTL_MS=0"
  "cap800_cache_on|$COMMON_ENVS DECK_CANDIDATE_CAP=800 DECK_ITEMS_FETCH_LIMIT=1400 DECK_RETRIEVAL_DOCS_CACHE_TTL_MS=15000"
  "cap1200_cache_off|$COMMON_ENVS DECK_CANDIDATE_CAP=1200 DECK_ITEMS_FETCH_LIMIT=2000 DECK_RETRIEVAL_DOCS_CACHE_TTL_MS=0"
  "cap1200_cache_on|$COMMON_ENVS DECK_CANDIDATE_CAP=1200 DECK_ITEMS_FETCH_LIMIT=2000 DECK_RETRIEVAL_DOCS_CACHE_TTL_MS=15000"
)

for cfg in "${CONFIGS[@]}"; do
  run_config "$cfg"
done

echo "=== Cache/latency matrix complete ==="
echo "Results: $RESULTS_TSV"
