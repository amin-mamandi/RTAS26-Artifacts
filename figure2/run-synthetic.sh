#!/bin/bash

# run this script with sudo 
killall -9 pll bandwidth 2>/dev/null || true

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

CORES=(1 2 3)
VICTIM_TIME=20  # seconds to run victim for (should be long enough to get stable bandwidth but not too long to make the whole process take forever)
DEVICE="intel"
N_RUNS=3
memsize=2048 # in MB (you can adjust this based on your system's hugepage size and availability)
OUTDIR="synthetic-logs"
mkdir -p "$OUTDIR"

# Check required tools
if ! command -v bandwidth >/dev/null 2>&1; then
    echo "ERROR: 'bandwidth' command not found in PATH. Please install or add it to PATH." >&2
    exit 1
fi

if ! command -v bc >/dev/null 2>&1; then
    echo "ERROR: 'bc' command not found in PATH. Please install it (used for floating-point math)." >&2
    exit 1
fi

parse_bw() {
    # Parse an MB/s number from bandwidth output passed via stdin.
    local out
    out=$(cat)
    local v
    v=$(printf "%s" "$out" | sed -n 's/.*B\/W *= *\([0-9]\+\(\.[0-9]\+\)\).*/\1/p' | head -n1)
    if [ -z "$v" ]; then
        v=$(printf "%s" "$out" | sed -n 's/.*bandwidth *= *\([0-9]\+\(\.[0-9]\+\)\).*/\1/p' | head -n1)
    fi
    if [ -z "$v" ]; then
        v=$(printf "%s" "$out" | sed -n 's/.*\([0-9]\+\(\.[0-9]\+\)\)[[:space:]]*MB\/s.*/\1/ip' | head -n1)
    fi
    printf "%s" "$v"
}

calc_stats() {
    # Args: list of numeric values
    # Output: "median mean std" (std = sample stddev)
    local tmp
    tmp=$(mktemp)
    printf "%s\n" "$@" > "$tmp"

    local n mean std median
    n=$(wc -l < "$tmp" | tr -d ' ')

    mean=$(awk '{s+=$1} END{ if(NR>0) printf "%.6f", s/NR; else printf "0.000000" }' "$tmp")
    std=$(awk -v mean="$mean" '{d=$1-mean; ss+=d*d} END{ if(NR>1) printf "%.6f", sqrt(ss/(NR-1)); else printf "0.000000" }' "$tmp")
    median=$(sort -n "$tmp" | awk '{a[NR]=$1} END{ if(NR==0) {printf "0.000000"} else if(NR%2==1) printf "%.6f", a[(NR+1)/2]; else printf "%.6f", (a[NR/2]+a[NR/2+1])/2 }')

    rm -f "$tmp"
    printf "%s %s %s" "$median" "$mean" "$std"
}

calc_min_max() {
    # Args: list of numeric values
    # Output: "min max"
    printf "%s\n" "$@" | awk '
        NR==1 { min=max=$1 }
        { if ($1 < min) min=$1; if ($1 > max) max=$1 }
        END {
            if (NR == 0) {
                printf "0.000000 0.000000"
            } else {
                printf "%.6f %.6f", min, max
            }
        }'
}

# Run baseline N times
echo "Running baseline ($N_RUNS runs)..."
baseline_vals=()
for r in $(seq 1 "$N_RUNS"); do
    baseline_out=$(bandwidth -x -c 0 -m 256000 -t "$VICTIM_TIME" 2>&1 || true)
    baseline=$(printf "%s" "$baseline_out" | parse_bw)
    if [ -z "$baseline" ]; then
        echo "WARNING: could not parse baseline bandwidth on run $r. Raw output:\n$baseline_out" >&2
        continue
    fi
    baseline_vals+=("$baseline")
    echo "  baseline run $r: $baseline MB/s"
done

if [ ${#baseline_vals[@]} -eq 0 ]; then
    echo "ERROR: no valid baseline measurements; cannot continue." >&2
    exit 1
fi

read -r baseline_med baseline_mean baseline_std <<<"$(calc_stats "${baseline_vals[@]}")"
echo "Baseline stats: median=$baseline_med mean=$baseline_mean std=$baseline_std (MB/s)"

# Declare arrays to store per-run victim values for each scenario
declare -a ABr_victim_vals ABw_victim_vals SBr_victim_vals SBw_victim_vals

# Run each attack scenario N times
for bank in all single; do
    for atype in read write; do
        echo "Running $bank bank $atype ($N_RUNS runs)..."

        scenario_att_vals=()
        scenario_victim_vals=()

        for r in $(seq 1 "$N_RUNS"); do
            # Start attackers and collect their output
            echo "  run $r: starting attackers..."
            pids=""
            logs=""
            att_mem="$memsize"
            [ "$bank" = "single" ] && att_mem="$memsize"
            for c in "${CORES[@]}"; do
                logfile="$OUTDIR/att_${c}.log"
                if [ "$bank" = "single" ]; then
                    pll -f "$REPO_ROOT/IsolBench/bench/map.txt" -c $c -l 16 -m "$att_mem" -i 100000000000 -a $atype -u 64 -e 0 > $logfile 2>&1 &
                else
                    pll -f "$REPO_ROOT/IsolBench/bench/map.txt" -c $c -l 16 -m "$att_mem" -i 100000000000 -a $atype -u 64 > $logfile 2>&1 &
                fi
                pids="$pids $!"
                logs="$logs $logfile"
            done

            # Wait a bit for attackers to start
            sleep 60

            # Run victim and capture its bandwidth (robust parse)
            victim_out=$(bandwidth -x -c 0 -m 256000 -t "$VICTIM_TIME" 2>&1 || true)
            victim_bw=$(printf "%s" "$victim_out" | parse_bw)

            # Kill attackers and wait for them to print final stats
            if [ -n "${pids// /}" ]; then
                kill -2 $pids 2>/dev/null || true
            fi
            sleep 2  # Give them time to print final bandwidth

            # Sum up attacker bandwidths
            total_bw=0
            for log in $logs; do
                bw=$(grep "bandwidth" $log 2>/dev/null | tail -1 | sed 's/.*bandwidth \([0-9.]*\).*/\1/')
                if [ -n "$bw" ]; then
                    total_bw=$(echo "$total_bw + $bw" | bc)
                fi
            done

            if [ -n "$victim_bw" ]; then
                scenario_victim_vals+=("$victim_bw")
            else
                echo "  WARNING: could not parse victim bandwidth on run $r" >&2
                printf "%s\n" "$victim_out" > "$OUTDIR/victim_run${r}_${bank}_${atype}.log"
                echo "  NOTE: raw victim output saved to $OUTDIR/victim_run${r}_${bank}_${atype}.log" >&2
            fi
            scenario_att_vals+=("$total_bw")

            echo "  run $r: attackers=$total_bw MB/s, victim=$victim_bw MB/s"
            rm -f $logs
        done

        if [ ${#scenario_victim_vals[@]} -eq 0 ]; then
            echo "ERROR: no valid victim measurements for $bank $atype; cannot continue." >&2
            exit 1
        fi

        read -r att_med att_mean att_std <<<"$(calc_stats "${scenario_att_vals[@]}")"
        read -r vic_med vic_mean vic_std <<<"$(calc_stats "${scenario_victim_vals[@]}")"
        read -r att_min att_max <<<"$(calc_min_max "${scenario_att_vals[@]}")"

        # Store for legacy one-line output AND save victim arrays for slowdown calculation
        if [ "$bank" = "all" ]; then
            if [ "$atype" = "read" ]; then
                ABr_bw=$att_med
                ABr_victim=$vic_med
                ABr_victim_vals=("${scenario_victim_vals[@]}")
                ABr_att_stats="$att_med $att_mean $att_std"
                ABr_vic_stats="$vic_med $vic_mean $vic_std"
                ABr_bw_min=$att_min
                ABr_bw_max=$att_max
            else
                ABw_bw=$att_med
                ABw_victim=$vic_med
                ABw_victim_vals=("${scenario_victim_vals[@]}")
                ABw_att_stats="$att_med $att_mean $att_std"
                ABw_vic_stats="$vic_med $vic_mean $vic_std"
                ABw_bw_min=$att_min
                ABw_bw_max=$att_max
            fi
        else
            if [ "$atype" = "read" ]; then
                SBr_bw=$att_med
                SBr_victim=$vic_med
                SBr_victim_vals=("${scenario_victim_vals[@]}")
                SBr_att_stats="$att_med $att_mean $att_std"
                SBr_vic_stats="$vic_med $vic_mean $vic_std"
                SBr_bw_min=$att_min
                SBr_bw_max=$att_max
            else
                SBw_bw=$att_med
                SBw_victim=$vic_med
                SBw_victim_vals=("${scenario_victim_vals[@]}")
                SBw_att_stats="$att_med $att_mean $att_std"
                SBw_vic_stats="$vic_med $vic_mean $vic_std"
                SBw_bw_min=$att_min
                SBw_bw_max=$att_max
            fi
        fi
    done
done

# Calculate slowdowns using victim median bandwidths
ABr_sd=$(echo "scale=6; $baseline_med / $ABr_victim" | bc)
ABw_sd=$(echo "scale=6; $baseline_med / $ABw_victim" | bc)
SBr_sd=$(echo "scale=6; $baseline_med / $SBr_victim" | bc)
SBw_sd=$(echo "scale=6; $baseline_med / $SBw_victim" | bc)

# Calculate slowdown stats (baseline median divided by each victim run)
calc_slowdown_stats() {
    local base="$1"; shift
    local vals=()
    local v
    for v in "$@"; do
        vals+=("$(echo "scale=12; $base / $v" | bc)")
    done
    local med mean std min max
    read -r med mean std <<<"$(calc_stats "${vals[@]}")"
    read -r min max <<<"$(printf "%s\n" "${vals[@]}" | awk 'NR==1{min=max=$1} {if($1<min)min=$1; if($1>max)max=$1} END{printf "%.6f %.6f", min, max}')"
    printf "%s %s %s %s %s" "$med" "$mean" "$std" "$min" "$max"
}

read -r ABr_sd_med ABr_sd_mean ABr_sd_std ABr_sd_min ABr_sd_max <<<"$(calc_slowdown_stats "$baseline_med" "${ABr_victim_vals[@]}")"
read -r ABw_sd_med ABw_sd_mean ABw_sd_std ABw_sd_min ABw_sd_max <<<"$(calc_slowdown_stats "$baseline_med" "${ABw_victim_vals[@]}")"
read -r SBr_sd_med SBr_sd_mean SBr_sd_std SBr_sd_min SBr_sd_max <<<"$(calc_slowdown_stats "$baseline_med" "${SBr_victim_vals[@]}")"
read -r SBw_sd_med SBw_sd_mean SBw_sd_std SBw_sd_min SBw_sd_max <<<"$(calc_slowdown_stats "$baseline_med" "${SBw_victim_vals[@]}")"

ABr_sd_stats="$ABr_sd_med $ABr_sd_mean $ABr_sd_std"
ABw_sd_stats="$ABw_sd_med $ABw_sd_mean $ABw_sd_std"
SBr_sd_stats="$SBr_sd_med $SBr_sd_mean $SBr_sd_std"
SBw_sd_stats="$SBw_sd_med $SBw_sd_mean $SBw_sd_std"

# Write summary with explicit CSV columns for bandwidth and slowdown min/max.
cat > "synthetic-data.csv" <<EOF
device,ABr_bw,ABw_bw,SBr_bw,SBw_bw,ABr_bw_min,ABr_bw_max,ABw_bw_min,ABw_bw_max,SBr_bw_min,SBr_bw_max,SBw_bw_min,SBw_bw_max,ABr_sd,ABw_sd,SBr_sd,SBw_sd,ABr_sd_min,ABr_sd_max,ABw_sd_min,ABw_sd_max,SBr_sd_min,SBr_sd_max,SBw_sd_min,SBw_sd_max
$DEVICE,$ABr_bw,$ABw_bw,$SBr_bw,$SBw_bw,$ABr_bw_min,$ABr_bw_max,$ABw_bw_min,$ABw_bw_max,$SBr_bw_min,$SBr_bw_max,$SBw_bw_min,$SBw_bw_max,$ABr_sd,$ABw_sd,$SBr_sd,$SBw_sd,$ABr_sd_min,$ABr_sd_max,$ABw_sd_min,$ABw_sd_max,$SBr_sd_min,$SBr_sd_max,$SBw_sd_min,$SBw_sd_max
EOF

# Write stats summary in a separate file
cat > "synthetic-stats.csv" <<EOF
device,metric,median,mean,std
$DEVICE,baseline_bw,$baseline_med,$baseline_mean,$baseline_std
$DEVICE,ABr_attack_bw,${ABr_att_stats// /,}
$DEVICE,ABr_victim_bw,${ABr_vic_stats// /,}
$DEVICE,ABr_slowdown,${ABr_sd_stats// /,}
$DEVICE,ABw_attack_bw,${ABw_att_stats// /,}
$DEVICE,ABw_victim_bw,${ABw_vic_stats// /,}
$DEVICE,ABw_slowdown,${ABw_sd_stats// /,}
$DEVICE,SBr_attack_bw,${SBr_att_stats// /,}
$DEVICE,SBr_victim_bw,${SBr_vic_stats// /,}
$DEVICE,SBr_slowdown,${SBr_sd_stats// /,}
$DEVICE,SBw_attack_bw,${SBw_att_stats// /,}
$DEVICE,SBw_victim_bw,${SBw_vic_stats// /,}
$DEVICE,SBw_slowdown,${SBw_sd_stats// /,}
EOF

echo "Done. Results in synthetic-data.csv and synthetic-stats.csv"
