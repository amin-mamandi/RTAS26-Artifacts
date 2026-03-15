#!/bin/bash

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# Base directories
SDVBS_DIR="$REPO_ROOT/sd-vbs/vision/benchmarks"
MATMULT_DIR="$REPO_ROOT/matmult"
MAP_FILE="$REPO_ROOT/IsolBench/bench/map.txt"

# number of attackers
ATTACKER_COUNT=3
# cores to use for attackers
ATTACKER_CORES=(1 2 3)
RUNS_PER_CASE=3

WORKLOADS=("disparity" "mser" "sift" "stitch" "tracking")

run_attackers() {
    local attk=$1
    local test_dir=$2

    attacker_pids=()
    for idx in $(seq 0 $((ATTACKER_COUNT-1))); do
        core=${ATTACKER_CORES[$idx]:-$(($idx + 1))}
        log="$test_dir/log-${attk}-attack-core${core}.log"
        # start attacker in background; adjust 'pll' args if needed
        pll -f "$MAP_FILE" -c "$core" -l 16 -m 512 -i 1000000000 -a "$attk" -u 64 >& "$log" &
        pid=$!
        attacker_pids+=("$pid")
        echo "Started attacker on core $core with PID: $pid (log: $log)"
    done

    n_attackers=${#attacker_pids[@]}
    echo "All $n_attackers attackers started: PIDs ${attacker_pids[*]}"
    sleep 30
}

# run matrix victim
run_matrix_victim() {
    local dim=$1
    local algo=$2
    # adapt taskset/core binding as desired
    taskset -c 0 "$MATMULT_DIR/matrix" -n "$dim" -a "$algo"
}

# run sd-vbs victim helper
run_victim() {
    local workload=$1

    # Use 'cif' for localization and svm, otherwise 'fullhd'
    local res_dir="fullhd"
    case "$workload" in
        localization|svm) res_dir="cif" ;;
    esac

    local input_dir="$SDVBS_DIR/$workload/data/$res_dir"
    local exec="$SDVBS_DIR/$workload/data/$res_dir/$workload"

    echo "running victim: $workload (input dir: $input_dir) ..."
    taskset -c 0 "$exec" "$input_dir"
}

kill_attackers() {
    for p in "${attacker_pids[@]:-}"; do
        if kill -2 "$p" 2>/dev/null; then
            echo "Sent SIGINT to PID $p"
        else
            echo "SIGINT failed for PID $p, trying SIGKILL"
            kill -9 "$p" 2>/dev/null || true
        fi
    done
    # give them a moment to terminate
    sleep 3
}

parse_metric_values() {
    local log="$1"
    if [ ! -f "$log" ]; then
        return
    fi
    awk '
    {
        if (match($0, /\([[:space:]]*[0-9]+\.[0-9]+[[:space:]]*s\)/)) {
            v = substr($0, RSTART, RLENGTH)
            sub(/^\([[:space:]]*/, "", v)
            sub(/[[:space:]]*s\)$/, "", v)
            printf "%.12f\n", v + 0
            next
        }
        if (match($0, /Elapsed time:[[:space:]]*[0-9]+\.[0-9]+/)) {
            v = substr($0, RSTART, RLENGTH)
            sub(/.*Elapsed time:[[:space:]]*/, "", v)
            printf "%.12f\n", v + 0
            next
        }
        if (match($0, /^[[:space:]]*[^[:space:]]+[[:space:]]+[0-9]+\.[0-9]+[[:space:]]+/)) {
            v = substr($0, RSTART, RLENGTH)
            sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+/, "", v)
            sub(/[[:space:]].*$/, "", v)
            printf "%.12f\n", v + 0
            next
        }
        if (match($0, /duration[[:space:]]+[0-9]+[[:space:]]+ns/)) {
            v = substr($0, RSTART, RLENGTH)
            sub(/.*duration[[:space:]]+/, "", v)
            sub(/[[:space:]]+ns.*/, "", v)
            printf "%.12f\n", (v + 0) / 1000000000
            next
        }
        if (match($0, /Cycles elapsed[[:space:]-]+[0-9]+/)) {
            v = substr($0, RSTART, RLENGTH)
            sub(/.*Cycles elapsed[[:space:]-]+/, "", v)
            printf "%.12f\n", v + 0
            next
        }
    }
' "$log"
}

compute_stats_from_values() {
    local values="$1"
    if [ -z "$values" ]; then
        return
    fi

    local count mean min max std median
    read -r count mean min max std <<< "$(printf '%s\n' "$values" | awk '
        BEGIN { n=0; sum=0; sq=0; minv=""; maxv="" }
        NF {
            x=$1+0
            n++
            sum+=x
            sq+=x*x
            if (minv=="" || x<minv) minv=x
            if (maxv=="" || x>maxv) maxv=x
        }
        END {
            if (n==0) exit
            mean=sum/n
            var=(sq/n)-(mean*mean)
            if (var < 0) var=0
            std=sqrt(var)
            printf "%d %.12f %.12f %.12f %.12f", n, mean, minv, maxv, std
        }
    ')"

    median=$(printf '%s\n' "$values" | awk 'NF' | sort -n | awk '
        { a[++n]=$1 }
        END {
            if (n==0) exit
            if (n % 2 == 1) {
                printf "%.12f", a[(n+1)/2]
            } else {
                printf "%.12f", (a[n/2] + a[n/2+1]) / 2
            }
        }
    ')

    printf "%s,%s,%s,%s,%s,%s" "$count" "$mean" "$median" "$min" "$max" "$std"
}

compute_ratio_values() {
    local solo_values="$1"
    local with_values="$2"
    if [ -z "$solo_values" ] || [ -z "$with_values" ]; then
        return
    fi
    paste \
        <(printf '%s\n' "$solo_values" | awk 'NF') \
        <(printf '%s\n' "$with_values" | awk 'NF') \
        | awk 'NF==2 && $1 > 0 { printf "%.12f\n", $2 / $1 }'
}

sum_attacker_bandwidth() {
    local dir="$1"
    local prefix="$2"
    local total="0.0"
    local found_any=0
    for core in 1 2 3; do
        local fname="$dir/${prefix}${core}.log"
        if [ ! -f "$fname" ]; then
            continue
        fi
        local value
        value=$(awk '
        {
            if (match($0, /bandwidth[: ]*[0-9]+\.[0-9]+/)) {
                v = substr($0, RSTART, RLENGTH)
                sub(/.*bandwidth[: ]*/, "", v)
                print v
                exit
            }
            if (match($0, /[0-9]+\.[0-9]+[[:space:]]*MB\/s/)) {
                v = substr($0, RSTART, RLENGTH)
                sub(/[[:space:]]*MB\/s.*/, "", v)
                print v
                exit
            }
        }
        ' "$fname")
        if [ -n "$value" ]; then
            total=$(awk -v t="$total" -v v="$value" 'BEGIN { printf "%.9f", t + v }')
            found_any=1
        fi
    done
    if [ "$found_any" -eq 1 ]; then
        printf "%.9f" "$total"
    fi
}

extract_results() {
    local root_name="$1"
    local root_dir="$2"

    if [ ! -d "$root_dir" ]; then
        echo "Warning: $root_dir not found, skipping result extraction."
        return
    fi

    local slow_tmp
    local bw_tmp
    slow_tmp=$(mktemp)
    bw_tmp=$(mktemp)
    local slow_count=0
    local bw_count=0

    declare -a run_dirs
    mapfile -t run_dirs < <(
        find "$root_dir" -type f \( -name 'victim_solo.log' -o -name 'victim_with3_read_attackers.log' -o -name 'victim_with3_write_attackers.log' \) -printf '%h\n' 2>/dev/null | sort -u
    )

    for run_dir in "${run_dirs[@]:-}"; do
        [ -d "$run_dir" ] || continue
        local vs="$run_dir/victim_solo.log"
        local vwr="$run_dir/victim_with3_read_attackers.log"
        local vww="$run_dir/victim_with3_write_attackers.log"
        if [ ! -f "$vs" ] && [ ! -f "$vwr" ] && [ ! -f "$vww" ]; then
            continue
        fi

        local scope
        scope=$(basename "$run_dir")
        scope=$(printf "%s" "$scope" | sed -E 's/^dim[0-9]+_//')

        local solo_values
        local read_values
        local write_values
        solo_values=$(parse_metric_values "$vs")
        read_values=$(parse_metric_values "$vwr")
        write_values=$(parse_metric_values "$vww")

        local read_bw
        local write_bw
        read_bw=$(sum_attacker_bandwidth "$run_dir" "log-read-attack-core")
        write_bw=$(sum_attacker_bandwidth "$run_dir" "log-write-attack-core")

        local solo_stats
        solo_stats=$(compute_stats_from_values "$solo_values")
        if [ -n "$solo_stats" ]; then
            local metric_kind="time_s"
            local test_or_time="time"
            local solo_runs solo_mean solo_median solo_min solo_max solo_std
            IFS=, read -r solo_runs solo_mean solo_median solo_min solo_max solo_std <<< "$solo_stats"

            if [ -n "$read_values" ]; then
                local read_stats
                local ratio_values
                local ratio_stats
                read_stats=$(compute_stats_from_values "$read_values")
                ratio_values=$(compute_ratio_values "$solo_values" "$read_values")
                ratio_stats=$(compute_stats_from_values "$ratio_values")
                local with_runs with_mean with_median with_min with_max with_std
                local slowdown_runs slowdown_mean slowdown_median slowdown_min slowdown_max slowdown_std
                IFS=, read -r with_runs with_mean with_median with_min with_max with_std <<< "$read_stats"
                IFS=, read -r slowdown_runs slowdown_mean slowdown_median slowdown_min slowdown_max slowdown_std <<< "$ratio_stats"
                if [ -z "$slowdown_mean" ] && [ -n "$solo_mean" ] && [ -n "$with_mean" ]; then
                    slowdown_mean=$(awk -v w="$with_mean" -v s="$solo_mean" 'BEGIN { if (s > 0) printf "%.12f", w / s }')
                fi
                printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
                    "$scope" "read" "$test_or_time" "$metric_kind" \
                    "$solo_mean" "$with_mean" "$slowdown_mean" \
                    "$solo_runs" "$with_runs" "$slowdown_runs" \
                    "$solo_median" "$solo_min" "$solo_max" "$solo_std" \
                    "$with_median" "$with_min" "$with_max" "$with_std" \
                    "$slowdown_median" "$slowdown_min" "$slowdown_max" "$slowdown_std" >> "$slow_tmp"
                slow_count=$((slow_count + 1))
            fi
            if [ -n "$write_values" ]; then
                local write_stats
                local ratio_values
                local ratio_stats
                write_stats=$(compute_stats_from_values "$write_values")
                ratio_values=$(compute_ratio_values "$solo_values" "$write_values")
                ratio_stats=$(compute_stats_from_values "$ratio_values")
                local with_runs with_mean with_median with_min with_max with_std
                local slowdown_runs slowdown_mean slowdown_median slowdown_min slowdown_max slowdown_std
                IFS=, read -r with_runs with_mean with_median with_min with_max with_std <<< "$write_stats"
                IFS=, read -r slowdown_runs slowdown_mean slowdown_median slowdown_min slowdown_max slowdown_std <<< "$ratio_stats"
                if [ -z "$slowdown_mean" ] && [ -n "$solo_mean" ] && [ -n "$with_mean" ]; then
                    slowdown_mean=$(awk -v w="$with_mean" -v s="$solo_mean" 'BEGIN { if (s > 0) printf "%.12f", w / s }')
                fi
                printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
                    "$scope" "write" "$test_or_time" "$metric_kind" \
                    "$solo_mean" "$with_mean" "$slowdown_mean" \
                    "$solo_runs" "$with_runs" "$slowdown_runs" \
                    "$solo_median" "$solo_min" "$solo_max" "$solo_std" \
                    "$with_median" "$with_min" "$with_max" "$with_std" \
                    "$slowdown_median" "$slowdown_min" "$slowdown_max" "$slowdown_std" >> "$slow_tmp"
                slow_count=$((slow_count + 1))
            fi
            if [ -n "$read_bw" ]; then
                printf '%s,%s,%s,%s\n' "$scope" "read" "$test_or_time" "$read_bw" >> "$bw_tmp"
                bw_count=$((bw_count + 1))
            fi
            if [ -n "$write_bw" ]; then
                printf '%s,%s,%s,%s\n' "$scope" "write" "$test_or_time" "$write_bw" >> "$bw_tmp"
                bw_count=$((bw_count + 1))
            fi
        else
            echo "[INFO] Could not parse metrics for $run_dir"
            local test_or_time="unknown"
            if [ -n "$read_bw" ]; then
                printf '%s,%s,%s,%s\n' "$scope" "read" "$test_or_time" "$read_bw" >> "$bw_tmp"
                bw_count=$((bw_count + 1))
            fi
            if [ -n "$write_bw" ]; then
                printf '%s,%s,%s,%s\n' "$scope" "write" "$test_or_time" "$write_bw" >> "$bw_tmp"
                bw_count=$((bw_count + 1))
            fi
        fi
    done

    mkdir -p "$SCRIPT_DIR/results"
    if [ "$slow_count" -gt 0 ]; then
        local slow_out="$SCRIPT_DIR/results/slowdown_${root_name}.csv"
        if {
            printf "scope,attack_type,test_or_time,metric_kind,solo,with_attack,slowdown,solo_runs,with_runs,slowdown_runs,solo_median,solo_min,solo_max,solo_std,with_median,with_min,with_max,with_std,slowdown_median,slowdown_min,slowdown_max,slowdown_std\n"
            cat "$slow_tmp"
        } > "$slow_out"; then
            echo "Wrote $slow_out ($slow_count rows)"
        else
            echo "Failed to write $slow_out" >&2
        fi
    fi
    if [ "$bw_count" -gt 0 ]; then
        local bw_out="$SCRIPT_DIR/results/attackers_bw_${root_name}.csv"
        if {
            printf "scope,attack_type,test_or_time,bw_MB_s_total\n"
            cat "$bw_tmp"
        } > "$bw_out"; then
            echo "Wrote $bw_out ($bw_count rows)"
        else
            echo "Failed to write $bw_out" >&2
        fi
    fi

    rm -f "$slow_tmp" "$bw_tmp"
}

# Argument parsing: expect matmult, sdvbs, or extract
if [ "${1-}" = "extract" ]; then
    extract_results "matmult" "matmult-allbanks-results"
    extract_results "sdvbs" "sdvbs-allbanks-results"
elif [ "${1-}" = "matmult" ]; then

    RESULTS_DIR="matmult-allbanks-results"
    mkdir -p "$RESULTS_DIR"

    for dim in 2048; do
        for algo in 0 1; do
            TEST_DIR="$RESULTS_DIR/dim${dim}_algo${algo}"
            mkdir -p "$TEST_DIR"
            victim_log="$TEST_DIR/victim_solo.log"
            : > "$victim_log"
            echo "running matrix solo baseline ($RUNS_PER_CASE runs): dim=$dim algo=$algo"
            for run_idx in $(seq 1 "$RUNS_PER_CASE"); do
                echo "solo run $run_idx/$RUNS_PER_CASE for dim $dim algo $algo"
                run_matrix_victim "$dim" "$algo" 2>&1 | tee -a "$victim_log" || true
            done

            for attk in "write" "read"; do
                run_attackers "$attk" "$TEST_DIR"

                victim_log="$TEST_DIR/victim_with${n_attackers}_${attk}_attackers.log"
                : > "$victim_log"
                echo "running matrix victim with $attk attackers ($RUNS_PER_CASE runs): dim=$dim algo=$algo"
                for run_idx in $(seq 1 "$RUNS_PER_CASE"); do
                    echo "with_attack run $run_idx/$RUNS_PER_CASE for dim $dim algo $algo ($attk)"
                    run_matrix_victim "$dim" "$algo" 2>&1 | tee -a "$victim_log" || true
                done

                kill_attackers
            done
        done
    done

    echo "All matmult results saved in: $RESULTS_DIR"
    extract_results "matmult" "$RESULTS_DIR"

elif [ "${1-}" = "sdvbs" ]; then
    
    RESULTS_DIR="sdvbs-allbanks-results"
    mkdir -p "$RESULTS_DIR"

    for workload in "${WORKLOADS[@]}"; do
        echo ">>> Running workload: $workload"
        TEST_DIR="$RESULTS_DIR/$workload"
        mkdir -p "$TEST_DIR"
        victim_log="$TEST_DIR/victim_solo.log"
        : > "$victim_log"
        echo "running solo baseline ($RUNS_PER_CASE runs): $workload"
        for run_idx in $(seq 1 "$RUNS_PER_CASE"); do
            echo "solo run $run_idx/$RUNS_PER_CASE for $workload"
            run_victim "$workload" 2>&1 | tee -a "$victim_log" || true
        done

        for attk in "write" "read"; do
            run_attackers "$attk" "$TEST_DIR"

            victim_log="$TEST_DIR/victim_with${n_attackers}_${attk}_attackers.log"
            : > "$victim_log"
            echo "running victim ($workload) with $n_attackers attackers doing $attk ($RUNS_PER_CASE runs)"
            for run_idx in $(seq 1 "$RUNS_PER_CASE"); do
                echo "with_attack run $run_idx/$RUNS_PER_CASE for $workload ($attk)"
                run_victim "$workload" 2>&1 | tee -a "$victim_log" || true
            done

            kill_attackers
        done
    done

    echo "All sd-vbs results saved in: $RESULTS_DIR"
    extract_results "sdvbs" "$RESULTS_DIR"

else
    echo "Usage: $0 {matmult|sdvbs|extract}"
    exit 1
fi
