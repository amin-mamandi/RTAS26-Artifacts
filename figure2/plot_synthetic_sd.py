#!/usr/bin/env python3
"""Plot slowdown bars with red error bars from syntetic-data.csv."""

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
        description="Generate slowdown_plot.pdf from syntetic-data.csv"
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
        default="slowdown_plot.pdf",
        help="Output PDF path (default: slowdown_plot.pdf)",
    )
    parser.add_argument(
        "--err",
        action="store_true",
        help="Enable red error bars",
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
        y = vals[4:8]
        mins = [vals[8], vals[10], vals[12], vals[14]]
        maxs = [vals[9], vals[11], vals[13], vals[15]]
        # Guard against tiny rounding mismatches in input summaries.
        yerr_lower = [max(0.0, v - lo) for v, lo in zip(y, mins)]
        yerr_upper = [max(0.0, hi - v) for v, hi in zip(y, maxs)]

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
            if args.err:
                ax.errorbar(
                    x,
                    y[i],
                    yerr=[[yerr_lower[i]], [yerr_upper[i]]],
                    fmt="none",
                    ecolor="red",
                    elinewidth=0.6,
                    capsize=4.5,
                    capthick=0.7,
                    zorder=4,
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
    ax.set_ylabel("Slowdown")
    # ymax = max(max(vals[4:8]) for _, vals in rows)
    ymax = 100
    ax.set_ylim(0, ymax)

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
