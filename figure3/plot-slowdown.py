#!/usr/bin/env python3
"""Plot slowdown bars from median slowdown values with min/max error bars."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

plt.rcParams.update(
    {
        "font.size": 8,
        "axes.labelsize": 8,
        "xtick.labelsize": 8,
        "ytick.labelsize": 8,
        "figure.dpi": 200,
        "font.family": "serif",
    }
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate platform_matmult_sdvbs_slowdown.pdf from results/*.csv"
    )
    parser.add_argument(
        "-r",
        "--results-dir",
        type=Path,
        default=Path("results"),
        help="Input directory containing slowdown CSVs (default: results)",
    )
    parser.add_argument(
        "-o",
        "--output",
        default="platform_matmult_sdvbs_slowdown.pdf",
        help="Output PDF path (default: platform_matmult_sdvbs_slowdown.pdf)",
    )
    return parser.parse_args()


def load_attack_rows(csv_paths: list[Path], attack_type: str) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for path in csv_paths:
        with path.open("r", encoding="utf-8", newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row.get("attack_type") == attack_type:
                    rows.append(row)
    return rows


def build_plot_rows(results_dir: Path) -> list[tuple[str, list[float]]]:
    allbanks_files = [results_dir / "slowdown_matmult.csv", results_dir / "slowdown_sdvbs.csv"]
    onebank_files = [results_dir / "slowdown_matmult_one.csv", results_dir / "slowdown_sdvbs_one.csv"]

    abr = load_attack_rows(allbanks_files, "read")
    abw = load_attack_rows(allbanks_files, "write")
    sbr = load_attack_rows(onebank_files, "read")
    sbw = load_attack_rows(onebank_files, "write")

    labels_abr = [row["scope"] for row in abr]
    labels_abw = [row["scope"] for row in abw]
    labels_sbr = [row["scope"] for row in sbr]
    labels_sbw = [row["scope"] for row in sbw]
    if not (labels_abr == labels_abw == labels_sbr == labels_sbw):
        raise SystemExit("CSV rows are not aligned across ABr/ABw/SBr/SBw series")

    rows: list[tuple[str, list[float]]] = []
    for i, label in enumerate(labels_abr):
        y_abr = float(abr[i]["slowdown_median"])
        y_abw = float(abw[i]["slowdown_median"])
        y_sbr = float(sbr[i]["slowdown_median"])
        y_sbw = float(sbw[i]["slowdown_median"])

        min_abr = float(abr[i]["slowdown_min"])
        max_abr = float(abr[i]["slowdown_max"])
        min_abw = float(abw[i]["slowdown_min"])
        max_abw = float(abw[i]["slowdown_max"])
        min_sbr = float(sbr[i]["slowdown_min"])
        max_sbr = float(sbr[i]["slowdown_max"])
        min_sbw = float(sbw[i]["slowdown_min"])
        max_sbw = float(sbw[i]["slowdown_max"])

        # Keep the same value layout as the provided template script:
        # [dummy x4] + [medians x4] + [mins/maxs per series]
        vals = [
            0.0,
            0.0,
            0.0,
            0.0,
            y_abr,
            y_abw,
            y_sbr,
            y_sbw,
            min_abr,
            max_abr,
            min_abw,
            max_abw,
            min_sbr,
            max_sbr,
            min_sbw,
            max_sbw,
        ]
        rows.append((label, vals))
    return rows


def main() -> None:
    args = parse_args()
    rows = build_plot_rows(args.results_dir)

    labels = ["ABr", "ABw", "SBr", "SBw"]
    device_positions = list(range(len(rows)))
    width = 0.15
    offsets = [(-1.5 + i) * width for i in range(4)]

    fig, ax = plt.subplots(figsize=(4.0, 2.2), constrained_layout=True)
    ax.grid(axis="y", color="#E0E0E0", linewidth=0.5)
    ax.set_axisbelow(True)

    series_styles = [
        {"facecolor": "white", "edgecolor": "#808080", "hatch": "xx"},  # ABr
        {"facecolor": "white", "edgecolor": "black", "hatch": "xx"},  # ABw
        {"facecolor": "#BDBDBD", "edgecolor": "black", "hatch": ""},  # SBr
        {"facecolor": "black", "edgecolor": "black", "hatch": ""},  # SBw
    ]

    for dev_idx, (_, vals) in enumerate(rows):
        y = vals[4:8]
        mins = [vals[8], vals[10], vals[12], vals[14]]
        maxs = [vals[9], vals[11], vals[13], vals[15]]
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
            ax.errorbar(
                x,
                y[i],
                yerr=[[yerr_lower[i]], [yerr_upper[i]]],
                fmt="none",
                ecolor="lightblue",
                elinewidth=1.2,
                capsize=1.2,
                capthick=0.4,
                zorder=4,
            )

    # Divider between matmult and sdvbs groups, matching gnuplot logic.
    matmult_count = len(load_attack_rows([args.results_dir / "slowdown_matmult.csv"], "read"))
    if 0 < matmult_count < len(rows):
        divider_x = (device_positions[matmult_count - 1] + device_positions[matmult_count]) / 2.0
        ax.axvline(divider_x, color="#808080", linestyle="--", linewidth=1.5)

    ax.set_xlim(device_positions[0] - 0.5, device_positions[-1] + 0.5)
    ax.set_xticks(device_positions)
    ax.set_xticklabels(
        [device for device, _ in rows],
        rotation=-30,
        ha="left",
        rotation_mode="anchor",
    )
    ax.set_ylabel("Slowdown")
    ax.set_ylim(0, 100)

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
