# Dataset Evaluation

## Provenance status

- Team reproduction dataset: UZH Event-Camera Dataset `shapes_rotation`.
- Official source encoded in the pinned tooling:
  `https://rpg.ifi.uzh.ch/datasets/davis/shapes_rotation.zip`.
- Pinned evaluation crop: `x=56, y=26, width=128, height=128`.
- Clock: 100 MHz.
- Pinned loader reads at most 200,000 source events before crop.
- Previous document reports 92,861 cropped events; this value must be reproduced
  from the downloaded file before it is accepted here.
- CIFAR10-DVS use was not found in repository refs/history or local files and is
  therefore not labelled as a team reproduction dataset.

Raw archives and extracted data live under `data/` and are ignored by Git.
Download checksum, actual event counts, canonical trace rules, playback sweep,
RTL representative windows, and measured results are added after execution.
