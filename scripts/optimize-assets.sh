#!/usr/bin/env bash
#
# Build an optimized distribution pack from the assets in themes/ and preview/.
#
# The committed originals are already lossy VP8, so this always re-encodes from
# the original -- never from a previous build. However many times CI runs, the
# published pack is exactly one generation away from what is in git.
#
# Each image is encoded down a quality ladder and scored with SSIMULACRA2
# against its original. The smallest candidate still above the quality floor
# wins. If nothing clears the floor, or the win is too small to be worth the
# extra generation of loss, the original is copied through untouched.

set -euo pipefail

SRC_DIRS="${SRC_DIRS:-themes preview}"
COPY_FILES="${COPY_FILES:-manifest.json LICENSE README.md}"
OUT_DIR="${OUT_DIR:-dist}"

# Descending: the last rung that clears SCORE_FLOOR is the one shipped.
# Bottoms out at q82 deliberately. Rungs below it were tested and rejected:
# blind review found q74-q80 visibly different from the originals on this
# artwork, and they only bought 115 KB (0.3%) across the whole pack anyway.
QUALITY_LADDER="${QUALITY_LADDER:-94 92 90 88 86 84 82}"

# SSIMULACRA2: 90 = visually lossless, 70 = high quality, 50 = medium.
# 80 was confirmed by blind A/B/C review against the originals: indistinguishable
# at 1:1 on this artwork, provided the ladder does not go below q82 (see above).
# Raise it if a future theme has finer detail.
SCORE_FLOOR="${SCORE_FLOOR:-80}"

# Every logo in the pack is <=25 KB; nothing that small is worth a lossy pass.
MIN_BYTES="${MIN_BYTES:-32768}"

# Below this saving, keep the original rather than spend a generation of loss.
MIN_SAVING_PCT="${MIN_SAVING_PCT:-10}"

JOBS="${JOBS:-$(nproc)}"

# ---------------------------------------------------------------- metric tool

detect_metric() {
  if command -v ssimulacra2 >/dev/null 2>&1; then
    SSIM_BIN=ssimulacra2; SSIM_ARGS=""; SSIM_NAME="libjxl ssimulacra2"
  elif command -v ssimulacra2_bin >/dev/null 2>&1; then
    SSIM_BIN=ssimulacra2_bin; SSIM_ARGS="image"; SSIM_NAME="ssimulacra2_bin (rust)"
  else
    echo "error: no SSIMULACRA2 implementation found." >&2
    echo "  Upstream static build (matches CI exactly):" >&2
    echo "    curl -sSLfO https://github.com/libjxl/libjxl/releases/download/v0.12.0/jxl-linux-x86_64-static.tar.lz" >&2
    echo "    lzip -d jxl-linux-x86_64-static.tar.lz" >&2
    echo "    tar -xf jxl-linux-x86_64-static.tar tools/ssimulacra2" >&2
    echo "    install -m755 tools/ssimulacra2 ~/.local/bin/ssimulacra2" >&2
    exit 1
  fi
}

# Both implementations print the score as the last number they emit.
ssim_score() {
  "$SSIM_BIN" $SSIM_ARGS "$1" "$2" 2>/dev/null \
    | grep -oE '[-+]?[0-9]+\.?[0-9]*' | tail -n1
}

# ------------------------------------------------------------------ one image

report() {
  # rel  action  orig_bytes  new_bytes  quality  score
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@" > "$(mktemp "$REPORT_DIR/r.XXXXXX")"
}

optimize_one() {
  local src="$1"
  local rel="${src#./}"
  local out="$OUT_DIR/$rel"
  mkdir -p "$(dirname "$out")"

  local orig_bytes
  orig_bytes=$(stat -c%s "$src")

  # Animated .gif backgrounds are permitted by the README; pass them through
  # rather than flatten them into a still.
  if [ "${src##*.}" != "webp" ]; then
    cp "$src" "$out"
    report "$rel" passthrough "$orig_bytes" "$orig_bytes" - -
    return
  fi

  if [ "$orig_bytes" -lt "$MIN_BYTES" ]; then
    cp "$src" "$out"
    report "$rel" too-small "$orig_bytes" "$orig_bytes" - -
    return
  fi

  # Deliberately not `local`: the EXIT trap below runs in global scope, after
  # this function's locals are gone. One image per process, so a global is safe.
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  dwebp -quiet "$src" -o "$tmp/ref.png"

  local best_q="" best_score="" best_bytes=""
  for q in $QUALITY_LADDER; do
    cwebp -quiet -q "$q" -m 6 -sharp_yuv -pass 10 -af -alpha_q 100 \
          -metadata none "$tmp/ref.png" -o "$tmp/cand.webp"
    dwebp -quiet "$tmp/cand.webp" -o "$tmp/cand.png"

    local score
    score=$(ssim_score "$tmp/ref.png" "$tmp/cand.png")
    [ -n "$score" ] || { echo "warn: no score for $rel at q$q" >&2; break; }

    # Quality falls monotonically down the ladder, so the first rung that
    # misses the floor ends the search.
    awk -v s="$score" -v f="$SCORE_FLOOR" 'BEGIN{exit !(s>=f)}' || break

    # Size is not monotonic in -q, so keep the smallest passing candidate
    # rather than assuming the lowest quality that clears the floor is it.
    local cand_bytes
    cand_bytes=$(stat -c%s "$tmp/cand.webp")
    if [ -z "$best_bytes" ] || [ "$cand_bytes" -lt "$best_bytes" ]; then
      mv "$tmp/cand.webp" "$tmp/best.webp"
      best_q="$q"; best_score="$score"; best_bytes="$cand_bytes"
    fi
  done

  if [ -n "$best_q" ] && awk -v n="$best_bytes" -v o="$orig_bytes" -v m="$MIN_SAVING_PCT" \
       'BEGIN{exit !((1-n/o)*100 >= m)}'; then
    cp "$tmp/best.webp" "$out"
    report "$rel" encoded "$orig_bytes" "$best_bytes" "$best_q" "$best_score"
  else
    cp "$src" "$out"
    report "$rel" kept-original "$orig_bytes" "$orig_bytes" - "${best_score:--}"
  fi
}

# ----------------------------------------------------------------------- main

# Re-entry point for the xargs workers below: one image per process, so the
# EXIT trap above is all the temp-dir cleanup we need.
if [ "${1:-}" = "--one-file" ]; then
  detect_metric
  optimize_one "$2"
  exit 0
fi

cd "$(dirname "$0")/.."
detect_metric

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

REPORT_DIR=$(mktemp -d)
trap 'rm -rf "$REPORT_DIR"' EXIT
export REPORT_DIR OUT_DIR QUALITY_LADDER SCORE_FLOOR MIN_BYTES MIN_SAVING_PCT

echo "metric:  $SSIM_NAME"
echo "floor:   SSIMULACRA2 >= $SCORE_FLOOR"
echo "ladder:  $QUALITY_LADDER"
echo "jobs:    $JOBS"
echo

find $SRC_DIRS -type f -print0 \
  | xargs -0 -P "$JOBS" -n1 "$0" --one-file

for f in $COPY_FILES; do
  [ -f "$f" ] && cp "$f" "$OUT_DIR/$f"
done

# The systems list is derived from the backgrounds present, so regenerate it
# against the built pack rather than trusting whatever was last committed to
# the source tree. Keeps the pack self-describing even if the source lists
# have not been synced yet.
if command -v jq >/dev/null 2>&1; then
  bash scripts/gen-theme-systems.sh "$OUT_DIR" | sed 's/^/  /'
else
  echo "warn: jq not found; dist theme.json systems lists left as copied" >&2
fi

cat "$REPORT_DIR"/r.* | sort > "$OUT_DIR/.optimization-report.tsv"

awk -F'\t' '
  { o+=$3; n+=$4; act[$2]++ }
  $2=="encoded" { qs[$5]++; sc+=$6; nsc++ }
  END {
    printf "%-14s %s\n", "encoded",      act["encoded"]+0
    printf "%-14s %s\n", "kept-original",act["kept-original"]+0
    printf "%-14s %s\n", "too-small",    act["too-small"]+0
    printf "%-14s %s\n", "passthrough",  act["passthrough"]+0
    printf "\n%-14s %.1f MB\n", "original:",  o/1048576
    printf "%-14s %.1f MB\n",   "optimized:", n/1048576
    printf "%-14s %.1f%% smaller\n", "saving:", (1-n/o)*100
    if (nsc) printf "%-14s %.1f\n", "mean score:", sc/nsc
    print "\nquality chosen:"
    for (q in qs) printf "  q%-4s %s files\n", q, qs[q]
  }
' "$OUT_DIR/.optimization-report.tsv"
