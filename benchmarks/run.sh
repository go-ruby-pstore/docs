#!/usr/bin/env bash
#
# Copyright (c) the go-ruby-pstore authors
# SPDX-License-Identifier: BSD-3-Clause
#
# Library-level cross-runtime benchmark runner for go-ruby-pstore.
#
# PStore is a Marshal-backed, file-backed transactional store, so this workload is
# I/O + Marshal bound. run.sh writes ONE fixed read-only store with MRI's own
# PStore (the oracle), points every runtime at it plus a scratch write file via
# $BENCH_STORE_R / $BENCH_STORE_W, and both the pure-Go driver (benchmarks/go) and
# each reference Ruby runtime (benchmarks/ruby/pstore.rb) run the SAME read and
# write transactions over the SAME fixed data.
#
# Before timing, every runtime is run with CHECK=1 and its per-op checksum (folded
# Marshal bytes of the fetched values, and of the written store file) is required
# to match MRI; a mismatch aborts.
#
# Usage:  bash benchmarks/run.sh
# Env:    OUTER (timed passes, default 25), WARM (untimed passes, default 3),
#         RUBY / JRUBY / TRUFFLERUBY (override runtime binaries).
set -u
cd "$(dirname "$0")"

RUBY=${RUBY:-ruby}
JRUBY=${JRUBY:-jruby}
TRUFFLERUBY=${TRUFFLERUBY:-truffleruby}

RB=ruby/pstore.rb
TMP=$(mktemp)
WORK=$(mktemp -d)
export BENCH_STORE_R="$WORK/read.pstore"
export BENCH_STORE_W="$WORK/write.pstore"
trap 'rm -f "$TMP"; rm -rf "$WORK"' EXIT

# --- Fixed read-only store, written once by MRI (the oracle) -------------------
echo "== writing fixed store with MRI PStore ($BENCH_STORE_R) ==" >&2
"$RUBY" "$RB" setup || { echo "FATAL: store setup failed" >&2; exit 1; }

# --- Correctness gate: every runtime's per-op checksums must equal MRI ---------
echo "== verifying results identical to MRI ==" >&2
gocheck=$( cd go && GOWORK=off CHECK=1 go run . 2>/dev/null )
mricheck=$( CHECK=1 "$RUBY" "$RB" 2>/dev/null )
if [ "$gocheck" != "$mricheck" ]; then
  echo "FATAL: go checksum differs from MRI" >&2
  echo "-- go --"  >&2; echo "$gocheck"  >&2
  echo "-- mri --" >&2; echo "$mricheck" >&2
  exit 1
fi
for pair in "jruby:$JRUBY" "truffleruby:$TRUFFLERUBY" "mri-yjit:$RUBY"; do
  lbl=${pair%%:*}; bin=${pair#*:}
  command -v "$bin" >/dev/null 2>&1 || continue
  if [ "$lbl" = "mri-yjit" ]; then oc=$( CHECK=1 "$bin" --yjit "$RB" 2>/dev/null )
  else oc=$( CHECK=1 "$bin" "$RB" 2>/dev/null ); fi
  [ -n "$oc" ] || continue
  if [ "$oc" != "$mricheck" ]; then
    echo "FATAL: $lbl checksum differs from MRI" >&2; exit 1
  fi
done
echo "  ok: all runtimes agree with MRI" >&2

# --- Timing --------------------------------------------------------------------
run() { # <runtime-label> <cmd...>
  local label=$1; shift
  command -v "$1" >/dev/null 2>&1 || { echo "  ($label: $1 not found — skipped)" >&2; return; }
  echo "  $label ..." >&2
  "$@" 2>/dev/null | awk -v r="$label" '$1=="RESULT"{printf "%s\t%s\t%s\n", r, $2, $3}' >> "$TMP"
}

echo "== go-ruby-pstore library-level benchmark ==" >&2
echo "  go ..." >&2
( cd go && command -v go >/dev/null 2>&1 && GOWORK=off go run . 2>/dev/null ) \
  | awk '$1=="RESULT"{printf "go\t%s\t%s\n", $2, $3}' >> "$TMP"
run "mri"         "$RUBY"                "$RB"
run "mri-yjit"    "$RUBY" --yjit        "$RB"
run "jruby"       "$JRUBY"              "$RB"
run "truffleruby" "$TRUFFLERUBY"        "$RB"

echo >&2
# Emit one Markdown table per sub-benchmark (label), runtimes as rows.
awk -F'\t' '
  { key=$2; rt=$1; ns=$3; labels[key]=1; val[rt SUBSEP key]=ns; rts[rt]=1 }
  END {
    order="go mri mri-yjit jruby truffleruby"
    n=split(order, ord, " ")
    ln=0; for (k in labels) lab[++ln]=k
    for (i=1;i<=ln;i++) for (j=i+1;j<=ln;j++) if (lab[j]<lab[i]){t=lab[i];lab[i]=lab[j];lab[j]=t}
    for (i=1;i<=ln;i++){
      k=lab[i]
      printf "\n#### %s\n\n", k
      print  "| Runtime | ns/op | vs MRI |"
      print  "| --- | ---: | ---: |"
      base=val["mri" SUBSEP k]
      for (o=1;o<=n;o++){
        rt=ord[o]; v=val[rt SUBSEP k]
        if (v=="") continue
        ratio=(base!=""&&base+0>0)? sprintf("%.2f×", v/base) : "—"
        name=rt
        if (rt=="go") name="**go-ruby (pure Go)**"
        else if (rt=="mri") name="MRI"
        else if (rt=="mri-yjit") name="MRI + YJIT"
        else if (rt=="jruby") name="JRuby"
        else if (rt=="truffleruby") name="TruffleRuby"
        printf "| %s | %s | %s |\n", name, v, ratio
      }
    }
  }
' "$TMP"
