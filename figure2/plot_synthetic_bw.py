#!/usr/bin/env python3
"""Plot bandwidth bars from syntetic-data.csv."""

from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

plt.rcParams.update({
    "font.size": 8,
    "axes.labelsize": 8,
    "xtick.labelsize": 8,
    "ytick.labelsize": 8,
    "figure.dpi": 200,
    "font.family": "serif",
})


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate bandwidth_plot.pdf from syntetic-data.csv"
    )
    parser.add_argument(
        "-i",
        "--input",
        default="syntetic-data.csv",
        help="Input file (default: syntetic-data.csv)",
    )
    parser.add_argument(
        "-o",
        "--output",
        default="bandwidth_plot.pdf",
        help="Output PDF path (default: bandwidth_plot.pdf)",
    )
    return parser.parse_args()


def read_rows(path: Path) -> list[tuple[str, list[float]]]:
    with path.open("r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip() and not line.startswith("#")]
    if not lines:
        raise SystemExit(f"No data rows found in {path}")
    rows: list[tuple[str, list[float]]] = []
    for line in lines:
        fields = line.split()
        if len(fields) < 17:
            raise SystemExit(f"Expected >= 17 columns, got {len(fields)} in line: {line}")
        rows.append((fields[0], [float(v) for v in fields[1:17]]))
    return rows


def main() -> None:
    args = parse_args()
    rows = read_rows(Path(args.input))

    labels = ["ABr", "ABw", "SBr", "SBw"]
    device_positions = list(range(len(rows)))
    offsets = [-0.30, -0.10, 0.10, 0.30]
    width = 0.15

    fig, ax = plt.subplots(figsize=(4.0, 2.2), constrained_layout=True)
    ax.grid(axis="y", color="#E0E0E0", linewidth=0.5)
    ax.set_axisbelow(True)

    series_styles = [
        {"facecolor": "white", "edgecolor": "#808080", "hatch": "xx"},  # ABr
        {"facecolor": "white", "edgecolor": "black", "hatch": "xx"},    # ABw
        {"facecolor": "#BDBDBD", "edgecolor": "black", "hatch": ""},     # SBr
        {"facecolor": "black", "edgecolor": "black", "hatch": ""},       # SBw
    ]
    for dev_idx, (device, vals) in enumerate(rows):
        y = vals[0:4]
        for i in range(4):
            x = device_positions[dev_idx] + offsets[i]
            ax.bar(
                x,
                y[i],
                width=width,
                facecolor=series_styles[i]["facecolor"],
                edgecolor=series_styles[i]["edgecolor"],
                linewidth=0.6,
                hatch=series_styles[i]["hatch"],
                label=labels[i] if dev_idx == 0 else None,
                zorder=3,
            )
            # Keep bar borders black even when hatch color differs (e.g., ABr).
            ax.add_patch(
                Rectangle(
                    (x - width / 2.0, 0.0),
                    width,
                    y[i],
                    fill=False,
                    edgecolor="black",
                    linewidth=0.6,
                    zorder=3.2,
                )
            )

    ax.set_xlim(-0.6, len(rows) - 0.4)
    pretty_labels = []
    for device, _ in rows:
        pretty_labels.append(
            {"pi4": "Pi 4", "pi5": "Pi 5", "intel": "Intel", "agx": "AGX", "nano": "Nano"}.get(
                device.lower(), device
            )
        )
    ax.set_xticks(device_positions)
    ax.set_xticklabels(pretty_labels)
    ax.set_ylabel("Bandwidth (MB/s)")
    ax.set_ylim(0, 20000)

    ax.legend(
        loc="upper center",
        bbox_to_anchor=(0.5, 1.15),
        ncol=4,
        frameon=False,
        handlelength=1.4,
        columnspacing=1.0,
    )

    fig.savefig(args.output)


if __name__ == "__main__":
    main()
