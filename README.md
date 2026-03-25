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

Run the setup command with `sudo`.

```bash
git clone --recurse-submodules https://github.com/amin-mamandi/RTAS26-Artifacts
cd RTAS26-Artifacts
sudo ./setupBoard.sh
```

### Figure 1: MLP Experiments

Run the experiment with `sudo`. For the paper results, use `<corun>` as `0` or `3`:
- `0`: one `pll` process
- `3`: four concurrent `pll` processes total


```bash
cd figure1
sudo ./mlptest.sh <maxmlp> <corun>
gnuplot plot-mlp.gp
```

### Figure 2: Synthetic Benchmark Experiments

Run the benchmark command with `sudo`.

```bash
cd figure2
sudo ./run-synthetic.sh
python3 plot_synthetic_sd.py [--err]
python3 plot_synthetic_bw.py
```

### Figure 3: Real-World Workload Experiments

Run the attack scripts with `sudo`. Use `<benchmark>` as either `sdvbs` or `matmult`.

```bash
cd figure3
sudo ./all-banks-attack.sh <benchmark>
sudo ./single-bank-attack.sh <benchmark>
python3 extract-data.py
gnuplot plot-slowdown.gp
```
