#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="/Users/johannesdavidsson/Cursor Projects/Swiper"
LOG_DIR="$REPO_ROOT/output/autoresearch/2026-03-12-deep-ranker-research-07/logs"
OUT="$REPO_ROOT/output/autoresearch/2026-03-12-deep-ranker-research-07/results_corrected.tsv"
printf 'config\toracle_metric\tlikes_metric\tprobe_rank_window\tprobe_candidate_count\tprobe_cache_enabled\tprobe_cache_hit\tlatency_count\tlatency_avg_ms\tlatency_p95_ms\tlatency_max_ms\n' > "$OUT"
for name in cap800_cache_off cap800_cache_on cap1200_cache_off cap1200_cache_on; do
  oracle=$(awk '/^primary_metric_liked_in_top_k:/ {print $2}' "$LOG_DIR/${name}_oracle.log" | tail -n1)
  likes=$(awk '/^primary_metric_liked_in_top_k:/ {print $2}' "$LOG_DIR/${name}_likes.log" | tail -n1)
  probe="$LOG_DIR/${name}_probe.json"
  rw=$(jq -r '.rank.rankWindow // "NA"' "$probe")
  cc=$(jq -r '.rank.candidateCount // "NA"' "$probe")
  ce=$(jq -r 'if (.rank|has("retrievalCache")) then (.rank.retrievalCache.enabled|tostring) else "NA" end' "$probe")
  ch=$(jq -r 'if (.rank|has("retrievalCache")) then (.rank.retrievalCache.hit|tostring) else "NA" end' "$probe")
  run_log="$LOG_DIR/${name}_emulators_exec.log"
  vals=$(rg -o 'latencyMs: [0-9]+' "$run_log" | awk '{print $2}')
  count=$(printf '%s\n' "$vals" | awk 'NF{c++} END{print c+0}')
  avg=$(printf '%s\n' "$vals" | awk 'NF{s+=$1;c++} END{if(c>0) printf "%.2f", s/c; else print "NA"}')
  p95=$(printf '%s\n' "$vals" | awk 'NF{print $1}' | sort -n | awk '{a[NR]=$1} END{if(NR==0){print "NA"} else {idx=int(0.95*NR); if(idx<1) idx=1; if(idx>NR) idx=NR; print a[idx]}}')
  max=$(printf '%s\n' "$vals" | awk 'NF{if($1>m)m=$1} END{if(m==0){print "NA"} else {print m}}')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$oracle" "$likes" "$rw" "$cc" "$ce" "$ch" "$count" "$avg" "$p95" "$max" >> "$OUT"
done
