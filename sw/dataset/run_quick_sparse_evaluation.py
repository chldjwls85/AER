"""Quick 1x/1000x software evaluation for the SPARSE/ROW/BANK iteration."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from sw.dataset.canonical_trace import canonicalize, load_uzh_source  # noqa: E402
from sw.metrics.architecture_models import DESIGNS, simulate  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--events", type=Path, default=ROOT / "data" / "uzh" / "events.txt")
    args = parser.parse_args()
    results: list[dict[str, object]] = []
    for speed in (1, 1000):
        source, _metadata = load_uzh_source(
            args.events,
            max_source_events=200_000,
            crop=(56, 26, 128, 128),
            clock_hz=100_000_000.0,
            playback_speed=float(speed),
        )
        transactions = canonicalize(source)
        for design in DESIGNS:
            result, _accepted = simulate(
                transactions,
                design=design,
                source_events=len(source),
                playback_speed=float(speed),
            )
            results.append(result)
            print(
                f"QUICK speed={speed} design={design} "
                f"accepted_events={result['accepted_events']} "
                f"accepted_transactions={result['accepted_transactions']} "
                f"words={result['output_words']} "
                f"words_per_event={float(result['words_per_accepted_event']):.6f} "
                f"mean={float(result['mean_latency_cycles']):.3f} "
                f"p99={result['p99_latency_cycles']} "
                f"sparse={result.get('sparse_packets', 0)} "
                f"row={result['row_packets']} bank={result['bank_packets']}"
            )
    output = ROOT / "results" / "metrics" / "sparse_quick_software.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(results, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("AER_SPARSE_QUICK_SOFTWARE_PASS")


if __name__ == "__main__":
    main()
