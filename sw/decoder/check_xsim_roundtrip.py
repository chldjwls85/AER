"""Decode dataset XSim words and compare them with accepted RTL inputs."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path


def load_accepted(path: Path) -> Counter[tuple[int, int, int, int]]:
    records: Counter[tuple[int, int, int, int]] = Counter()
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            kind, _cycle, tile, on, off, timestamp = line.split()
            if kind != "A":
                raise ValueError(line)
            records[(int(tile), int(on, 16), int(off, 16), int(timestamp, 16))] += 1
    return records


def load_words(path: Path) -> list[tuple[int, bool]]:
    words = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            kind, _cycle, data, last = line.split()
            if kind != "W":
                raise ValueError(line)
            words.append((int(data, 16), bool(int(last))))
    return words


def tile_from(bank: int, row: int, column: int) -> int:
    return bank * 16 + row * 4 + column


def decode_current(words: list[tuple[int, bool]]) -> tuple[Counter[tuple[int, int, int, int]], dict[str, int]]:
    decoded: Counter[tuple[int, int, int, int]] = Counter()
    modes = {"SPARSE": 0, "ROW": 0, "BANK": 0}
    index = 0
    while index < len(words):
        header, last = words[index]
        if last:
            raise ValueError("header asserted last")
        index += 1
        if (header >> 15) == 0:
            modes["SPARSE"] += 1
            bank = (header >> 7) & 0xFF
            tile_local = (header >> 3) & 0xF
            pixel = (header >> 1) & 0x3
            polarity = header & 1
            timestamp, last = words[index]
            index += 1
            if not last:
                raise ValueError("SPARSE timestamp missing LAST")
            bitmap = 1 << pixel
            decoded[(bank * 16 + tile_local,
                     bitmap if polarity else 0,
                     0 if polarity else bitmap,
                     timestamp)] += 1
            continue
        bank = (header >> 6) & 0xFF
        kind = (header >> 14) & 0x3
        if kind == 3:
            modes["ROW"] += 1
            row = (header >> 4) & 0x3
            mask = (header & 0xF) << (row * 4)
            base, last = words[index]
            index += 1
        elif kind == 2:
            modes["BANK"] += 1
            mask, last = words[index]
            index += 1
            base, last = words[index]
            index += 1
        else:
            raise ValueError(f"bad current header {header:04x}")
        remaining = mask
        while remaining:
            tile_local = (remaining & -remaining).bit_length() - 1
            data, last = words[index]
            index += 1
            on = (data >> 7) & 0xF
            off = (data >> 3) & 0xF
            timestamp = (base + ((data >> 11) & 0x1F)) & 0xFFFF
            decoded[(bank * 16 + tile_local, on, off, timestamp)] += 1
            remaining &= ~(1 << tile_local)
            if last != (remaining == 0):
                raise ValueError("current LAST mismatch")
    return decoded, modes


def decode_team(words: list[tuple[int, bool]]) -> tuple[Counter[tuple[int, int, int, int]], dict[str, int]]:
    decoded: Counter[tuple[int, int, int, int]] = Counter()
    counts = {"ROW": 0, "RAW8": 0, "GROUP3": 0, "BIN4": 0, "BIN_PAIR_WORD": 0}
    index = 0
    while index < len(words):
        header, last = words[index]
        index += 1
        if (header >> 14) != 3 or last:
            raise ValueError(f"bad team header {header:04x}")
        counts["ROW"] += 1
        bank = (header >> 6) & 0xFF
        row = (header >> 4) & 0x3
        remaining = header & 0xF
        base, last = words[index]
        index += 1
        if last:
            raise ValueError("team time asserted last")
        while remaining:
            first_column = (remaining & -remaining).bit_length() - 1
            data, last = words[index]
            index += 1
            format_code = (data >> 14) & 0x3
            if format_code == 0:
                counts["RAW8"] += 1
                on = (data >> 6) & 0xF
                off = (data >> 2) & 0xF
                delta = (data >> 10) & 0xF
                decoded[(tile_from(bank, row, first_column), on, off, (base + delta) & 0xFFFF)] += 1
                remaining &= ~(1 << first_column)
            elif format_code == 1:
                counts["GROUP3"] += 1
                polarity = (data >> 9) & 1
                missing = (data >> 7) & 0x3
                bitmap = 0xF & ~(1 << missing)
                delta = (data >> 10) & 0xF
                decoded[(tile_from(bank, row, first_column), bitmap if polarity else 0, 0 if polarity else bitmap, (base + delta) & 0xFFFF)] += 1
                remaining &= ~(1 << first_column)
            elif format_code == 2:
                counts["BIN4"] += 1
                paired = (data >> 13) & 1
                delta = (data >> 9) & 0xF
                polarity = (data >> 8) & 1
                decoded[(tile_from(bank, row, first_column), 0xF if polarity else 0, 0 if polarity else 0xF, (base + delta) & 0xFFFF)] += 1
                remaining &= ~(1 << first_column)
                if paired:
                    counts["BIN4"] += 1
                    counts["BIN_PAIR_WORD"] += 1
                    second_column = (remaining & -remaining).bit_length() - 1
                    delta = (data >> 4) & 0xF
                    polarity = (data >> 3) & 1
                    decoded[(tile_from(bank, row, second_column), 0xF if polarity else 0, 0 if polarity else 0xF, (base + delta) & 0xFFFF)] += 1
                    remaining &= ~(1 << second_column)
            else:
                raise ValueError(f"reserved team format {format_code}")
            if last != (remaining == 0):
                raise ValueError("team LAST mismatch")
    return decoded, counts


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--design", choices=("raw_baseline", "team_second", "current_adaptive"), required=True)
    parser.add_argument("--window", required=True)
    parser.add_argument("--accepted", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--json", type=Path, required=True)
    args = parser.parse_args()

    expected = load_accepted(args.accepted)
    words = load_words(args.output)
    decoded, counts = decode_current(words) if args.design == "current_adaptive" else decode_team(words)
    missing = expected - decoded
    extra = decoded - expected
    result = {
        "design": args.design,
        "window": args.window,
        "accepted_transactions": sum(expected.values()),
        "decoded_transactions": sum(decoded.values()),
        "output_words": len(words),
        "missing_transactions": sum(missing.values()),
        "extra_transactions": sum(extra.values()),
        "mode_counts": counts,
        "roundtrip_pass": not missing and not extra,
    }
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if not result["roundtrip_pass"]:
        print(json.dumps(result, indent=2))
        raise SystemExit(1)
    print(
        f"AER_DATASET_ROUNDTRIP_PASS design={args.design} window={args.window} "
        f"accepted={result['accepted_transactions']} words={len(words)}"
    )


if __name__ == "__main__":
    main()
