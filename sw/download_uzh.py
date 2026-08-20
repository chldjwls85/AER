"""Download selected official UZH rotational event-camera sequences."""

from __future__ import annotations

import argparse
import shutil
import urllib.request
import zipfile
from pathlib import Path


DATASETS = {
    "shapes_rotation": {
        "url": "https://rpg.ifi.uzh.ch/datasets/davis/shapes_rotation.zip",
        "bytes": 157_446_920,
    },
    "poster_rotation": {
        "url": "https://rpg.ifi.uzh.ch/datasets/davis/poster_rotation.zip",
        "bytes": 833_672_602,
    },
    "boxes_rotation": {
        "url": "https://rpg.ifi.uzh.ch/datasets/davis/boxes_rotation.zip",
        "bytes": 893_172_313,
    },
}


def _safe_extract(archive: zipfile.ZipFile, destination: Path) -> None:
    root = destination.resolve()
    for member in archive.infolist():
        target = (destination / member.filename).resolve()
        if target != root and root not in target.parents:
            raise ValueError(f"unsafe ZIP member: {member.filename}")
    archive.extractall(destination)


def download_dataset(name: str, destination: Path, extract: bool) -> Path:
    info = DATASETS[name]
    destination.mkdir(parents=True, exist_ok=True)
    archive_path = destination / f"{name}.zip"
    partial_path = archive_path.with_suffix(".zip.part")
    print(f"downloading {info['url']}")
    with urllib.request.urlopen(str(info["url"])) as response:
        with partial_path.open("wb") as output:
            shutil.copyfileobj(response, output)
    partial_path.replace(archive_path)
    print(f"saved {archive_path} ({archive_path.stat().st_size} bytes)")
    if extract:
        extract_dir = destination / name
        extract_dir.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive_path) as archive:
            _safe_extract(archive, extract_dir)
        print(f"extracted {extract_dir}")
    return archive_path


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset", choices=sorted(DATASETS))
    parser.add_argument("--destination", type=Path, default=Path("data/uzh"))
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--extract", action="store_true")
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    info = DATASETS[args.dataset]
    size_mib = int(info["bytes"]) / (1024 * 1024)
    print(f"dataset={args.dataset}")
    print(f"url={info['url']}")
    print(f"expected_size_mib={size_mib:.1f}")
    if not args.download:
        print("dry run only; add --download to save the archive")
        return
    download_dataset(args.dataset, args.destination, args.extract)


if __name__ == "__main__":
    main()
