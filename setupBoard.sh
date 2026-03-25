#!/bin/bash

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }

CUR_DIR=$(pwd)

# Submodule directories
SD_VBS_DIR="$CUR_DIR/sd-vbs"
MATMULT_DIR="$CUR_DIR/matmult"
ISOLBENCH_DIR="$CUR_DIR/IsolBench"
DRAMA_PP_DIR="$CUR_DIR/drama-pp"

# --- Initialize submodules if not already done ---
if [[ -f "$CUR_DIR/.gitmodules" ]]; then
    info "Checking for uninitialized submodules..."
    
    # Check if any submodule directory is empty or missing
    NEEDS_INIT=false
    for SUBMOD_DIR in "$SD_VBS_DIR" "$MATMULT_DIR" "$ISOLBENCH_DIR" "$DRAMA_PP_DIR"; do
        if [[ ! -d "$SUBMOD_DIR" ]] || [[ -z "$(ls -A "$SUBMOD_DIR" 2>/dev/null)" ]]; then
            NEEDS_INIT=true
            break
        fi
    done
    
    if [[ "$NEEDS_INIT" == true ]]; then
        info "Initializing and updating submodules (this may take a while)..."
        git submodule update --init --recursive
    else
        info "All submodules appear to be initialized."
    fi
else
    warn "No .gitmodules file found. Are you in the repository root?"
fi

# --- Build matmult ---
if [[ -d "$MATMULT_DIR" ]]; then
    info "Building matmult..."
    make -C "$MATMULT_DIR"
else
    warn "$MATMULT_DIR not found"
fi

# --- Build DRAMA-PP ---
if [[ -d "$DRAMA_PP_DIR" ]]; then
    info "Building DRAMA-PP..."
    make -C "$DRAMA_PP_DIR/re" clean || true
    make -C "$DRAMA_PP_DIR/re"
else
    warn "$DRAMA_PP_DIR not found"
fi

# --- Build SD-VBS benchmarks ---
if [[ -d "$SD_VBS_DIR" ]]; then
    for b in disparity mser sift stitch tracking; do
        info "Building SD-VBS benchmark $b (fullhd)..."
        make -C "$SD_VBS_DIR/vision/benchmarks/$b/data/fullhd" clean || true
        make -C "$SD_VBS_DIR/vision/benchmarks/$b/data/fullhd"
    done
else
    warn "$SD_VBS_DIR not found"
fi

# --- Build IsolBench ---
if [[ -d "$ISOLBENCH_DIR" ]]; then
    info "Building IsolBench..."
    (cd "$ISOLBENCH_DIR" || true)

    if [[ -d "$ISOLBENCH_DIR/IsolBench/bench" ]]; then
        make -C "$ISOLBENCH_DIR/IsolBench/bench"
        sudo make -C "$ISOLBENCH_DIR/IsolBench/bench" install
    else
        make -C "$ISOLBENCH_DIR/bench"
        sudo make -C "$ISOLBENCH_DIR/bench" install
    fi
else
    warn "$ISOLBENCH_DIR not found"
fi

# --- Set hugepages ---
info "Setting hugepages..."
HUGEPAGE_KB=$(awk '/Hugepagesize:/ {print $2}' /proc/meminfo)
if [[ -n "$HUGEPAGE_KB" ]]; then
    NUM_HUGEPAGES=$((4194304 / HUGEPAGE_KB))  # 4 GB total
    echo "$NUM_HUGEPAGES" | sudo tee /proc/sys/vm/nr_hugepages >/dev/null
    sudo mkdir -p /dev/hugepages
    mountpoint -q /dev/hugepages || sudo mount -t hugetlbfs nodev /dev/hugepages
    info "hugepages configured: ${NUM_HUGEPAGES} pages (${HUGEPAGE_KB} KB each)"
else
    warn "Could not determine hugepage size; skipping hugepage setup"
fi

# --- CPU tuning ---
info "Setting CPU to max performance..."
MAX_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)
[[ -n "$MAX_FREQ" ]] && echo "$MAX_FREQ" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq >/dev/null
echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null

# --- Disable Turbo & SMT ---
[[ -w /sys/devices/system/cpu/intel_pstate/no_turbo ]] && echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo >/dev/null
[[ -w /sys/devices/system/cpu/smt/control ]] && echo off | sudo tee /sys/devices/system/cpu/smt/control >/dev/null

info "All done!"
