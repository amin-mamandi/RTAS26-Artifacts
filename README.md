# RTAS 2026 Artifact

This repository contains the experimental artifact for the RTAS 2026 paper:
`Per-Bank Memory Bandwidth Regulation for Predictable and Performant Real-Time Systems`.

## Repository Layout

- `figure1/` - MLP experiments
- `figure2/` - Synthetic benchmark experiments
- `figure3/` - Real-world workload experiments
- `setupBoard.sh` - Board and test-environment setup script

## Requirements

- `python3`
- `gnuplot`

```bash
apt-get update
apt-get install gnuplot
```

## DRAM Address Mapping

Please refer to the [drama-pp README](https://github.com/CSL-KU/drama-pp/blob/a0858ddd7f6f0d055e76a609b4293d6367ea87e2/README.md) for DRAM address mapping instructions.
After generating `map.txt`, copy it into `IsolBench/bench/`.

## Reproducing Results

```bash
git clone --recurse-submodules https://github.com/amin-mamandi/RTAS26-Artifacts
cd RTAS26-Artifacts
./setupBoard.sh  # requires sudo
```

### Figure 1: MLP Experiments

```bash
cd figure1
./mlptest.sh <maxmlp> <corun>
gnuplot plot-mlp.gp
```

### Figure 2: Synthetic Benchmark Experiments

```bash
cd figure2
./run-synthetic.sh
python3 plot_synthetic_sd.py [--err]
python3 plot_synthetic_bw.py
```

### Figure 3: Real-World Workload Experiments

```bash
cd figure3
./all-banks-attack.sh sdvbs   # or matmult
./single-bank-attack.sh sdvbs # or matmult
python3 extract-data.py
gnuplot plot-slowdown.gp
```
