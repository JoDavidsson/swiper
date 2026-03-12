#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="/Users/johannesdavidsson/Cursor Projects/Swiper"
OUT_DIR="$REPO_ROOT/output/autoresearch/2026-03-11-deep-ranker-research-03"
LOG_DIR="$OUT_DIR/logs"
OUT_TSV="$OUT_DIR/results_corrected.tsv"

printf 'config\toracle_metric\toracle_failed\tlikes_metric\tlikes_failed\tprobe_variant\tprobe_rank_window\tprobe_candidate_count\tprobe_exploration_rate\tprobe_mmr_enabled\tprobe_mmr_applied\tconfig_validation\n' > "$OUT_TSV"

CONFIGS=(
  "baseline_default|0.08|false"
  "no_exploration|0|false"
  "low_exploration|0.04|false"
  "high_exploration|0.12|false"
  "wide_pool_no_exploration|0|false"
  "wide_pool_default_exploration|0.08|false"
  "wide_pool_mmr95_no_exploration|0|true"
  "wide_pool_mmr95_default_exploration|0.08|true"
)

for cfg in "${CONFIGS[@]}"; do
  IFS='|' read -r name expected_explore expected_mmr <<< "$cfg"

  oracle_log="$LOG_DIR/${name}_oracle.log"
  likes_log="$LOG_DIR/${name}_likes.log"
  probe_json="$LOG_DIR/${name}_probe.json"

  oracle_metric=$(awk '/^primary_metric_liked_in_top_k:/ {print $2}' "$oracle_log" | tail -n 1)
  oracle_failed=$(awk '/^offline_eval_sessions_failed:/ {print $2}' "$oracle_log" | tail -n 1)
  likes_metric=$(awk '/^primary_metric_liked_in_top_k:/ {print $2}' "$likes_log" | tail -n 1)
  likes_failed=$(awk '/^offline_eval_sessions_failed:/ {print $2}' "$likes_log" | tail -n 1)

  probe_variant=$(jq -r '.rank.variant // "NA"' "$probe_json")
  probe_rank_window=$(jq -r '.rank.rankWindow // "NA"' "$probe_json")
  probe_candidate_count=$(jq -r '.rank.candidateCount // "NA"' "$probe_json")
  probe_explore=$(jq -r '.rank.adaptiveExploration.effectiveRate // "NA"' "$probe_json")
  probe_mmr_enabled=$(jq -r 'if (.rank | has("mmrPolicy")) then (.rank.mmrPolicy.enabled|tostring) else "NA" end' "$probe_json")
  probe_mmr_applied=$(jq -r 'if (.rank | has("mmrPolicy")) then (.rank.mmrPolicy.applied|tostring) else "NA" end' "$probe_json")

  validation="ok"
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
    >> "$OUT_TSV"
done

echo "$OUT_TSV"
