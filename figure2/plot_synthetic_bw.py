#!/usr/bin/env python3
"""Plot bandwidth bars from synthetic-data.csv."""

from __future__ import annotations

import argparse
import csv
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
        description="Generate bandwidth_plot.pdf from synthetic-data.csv"
    )
    parser.add_argument(
        "-i",
        "--input",
        default="synthetic-data.csv",
        help="Input file (default: synthetic-data.csv)",
    )
    parser.add_argument(
        "-o",
        "--output",
        default="bandwidth_plot.pdf",
        help="Output PDF path (default: bandwidth_plot.pdf)",
    )
    parser.add_argument(
        "--err",
        action="store_true",
        help="Enable red error bars",
    )
    return parser.parse_args()


def read_rows(path: Path) -> list[dict[str, float | str]]:
    with path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        raise SystemExit(f"No data rows found in {path}")
    required = [
        "device",
        "ABr_bw", "ABw_bw", "SBr_bw", "SBw_bw",
        "ABr_bw_min", "ABr_bw_max", "ABw_bw_min", "ABw_bw_max",
        "SBr_bw_min", "SBr_bw_max", "SBw_bw_min", "SBw_bw_max",
    ]
    missing = [name for name in required if name not in (reader.fieldnames or [])]
    if missing:
        raise SystemExit(f"Missing required columns in {path}: {', '.join(missing)}")
    parsed_rows: list[dict[str, float | str]] = []
    for row in rows:
        parsed_rows.append({
            "device": row["device"],
            "ABr_bw": float(row["ABr_bw"]),
            "ABw_bw": float(row["ABw_bw"]),
            "SBr_bw": float(row["SBr_bw"]),
            "SBw_bw": float(row["SBw_bw"]),
            "ABr_bw_min": float(row["ABr_bw_min"]),
            "ABr_bw_max": float(row["ABr_bw_max"]),
            "ABw_bw_min": float(row["ABw_bw_min"]),
            "ABw_bw_max": float(row["ABw_bw_max"]),
            "SBr_bw_min": float(row["SBr_bw_min"]),
            "SBr_bw_max": float(row["SBr_bw_max"]),
            "SBw_bw_min": float(row["SBw_bw_min"]),
            "SBw_bw_max": float(row["SBw_bw_max"]),
        })
    return parsed_rows


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
    for dev_idx, row in enumerate(rows):
        y = [row["ABr_bw"], row["ABw_bw"], row["SBr_bw"], row["SBw_bw"]]
        mins = [row["ABr_bw_min"], row["ABw_bw_min"], row["SBr_bw_min"], row["SBw_bw_min"]]
        maxs = [row["ABr_bw_max"], row["ABw_bw_max"], row["SBr_bw_max"], row["SBw_bw_max"]]
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
    for row in rows:
        device = str(row["device"])
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
