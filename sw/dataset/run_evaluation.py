"""Run the reproducible UZH software sweep and generate curated artifacts."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from sw.dataset.canonical_trace import (  # noqa: E402
    canonicalize,
    choose_windows,
    load_uzh_source,
    write_canonical_csv,
    write_xsim_windows,
)
from sw.metrics.architecture_models import DESIGNS, simulate  # noqa: E402
from sw.visualization.render_results import (  # noqa: E402
    render_activity_mode_map,
    render_animation,
    render_event_comparison,
    render_performance,
)


SPEEDS = (1, 10, 100, 500, 1000, 2000, 5000)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--events",
        type=Path,
        default=ROOT / "data" / "uzh" / "events.txt",
    )
    parser.add_argument(
        "--archive",
        type=Path,
        default=ROOT / "data" / "uzh" / "shapes_rotation.zip",
    )
    args = parser.parse_args()

    results: list[dict[str, object]] = []
    accepted_at_1000: dict[str, list[tuple[int, int, int, int, int]]] = {}
    transactions_at_1000 = []
    base_metadata: dict[str, object] = {}

    for speed in SPEEDS:
        source, metadata = load_uzh_source(
            args.events,
            max_source_events=200_000,
            crop=(56, 26, 128, 128),
            clock_hz=100_000_000.0,
            playback_speed=float(speed),
        )
        transactions = canonicalize(source)
        canonical_events = sum(record.canonical_event_count for record in transactions)
        print(
            f"[dataset] speed={speed}x source={len(source)} "
            f"transactions={len(transactions)} canonical_events={canonical_events}"
        )
        for design in DESIGNS:
            result, accepted = simulate(
                transactions,
                design=design,
                source_events=len(source),
                playback_speed=float(speed),
            )
            results.append(result)
            print(
                f"  {design}: accepted={result['accepted_events']} "
                f"words={result['output_words']} "
                f"w/event={float(result['words_per_accepted_event']):.4f}"
            )
            if speed == 1000:
                accepted_at_1000[design] = accepted
        if speed == 1000:
            transactions_at_1000 = transactions
            base_metadata = metadata

    summary_path = ROOT / "results" / "summary.csv"
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = list(results[0].keys())
    with summary_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)

    metrics_dir = ROOT / "results" / "metrics"
    metrics_dir.mkdir(parents=True, exist_ok=True)
    (metrics_dir / "dataset_results.json").write_text(
        json.dumps(results, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    windows = choose_windows(transactions_at_1000, window_cycles=1024)
    generated_dir = ROOT / "data" / "generated" / "uzh_1000x"
    window_summary = write_xsim_windows(generated_dir, transactions_at_1000, windows)
    write_canonical_csv(generated_dir / "canonical.csv", transactions_at_1000)
    provenance = {
        **base_metadata,
        "archive_sha256": sha256(args.archive),
        "archive_bytes": args.archive.stat().st_size,
        "events_txt_bytes": args.events.stat().st_size,
        "canonical_transactions_1000x": len(transactions_at_1000),
        "canonical_events_1000x": sum(
            transaction.canonical_event_count for transaction in transactions_at_1000
        ),
        "windows": window_summary,
        "model_scope": "packet/link cycle model; representative windows cross-checked in XSim",
    }
    (metrics_dir / "dataset_provenance.json").write_text(
        json.dumps(provenance, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    figures = ROOT / "results" / "figures"
    animations = ROOT / "results" / "animations"
    render_performance(figures / "uzh_performance_comparison.png", results)
    render_event_comparison(
        figures / "uzh_dense_event_comparison.png",
        transactions_at_1000,
        accepted_at_1000,
        windows["dense"],
    )
    render_activity_mode_map(
        figures / "uzh_activity_mode_map.png",
        transactions_at_1000,
        windows["dense"],
    )
    render_animation(
        animations / "uzh_shapes_rotation_compare.gif",
        transactions_at_1000,
        accepted_at_1000["current_adaptive"],
        windows["burst"],
    )
    print(f"[dataset] summary={summary_path}")
    print("AER_DATASET_SOFTWARE_EVAL_PASS")


if __name__ == "__main__":
    main()
