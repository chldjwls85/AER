# Dataset Evaluation

> 명칭 주의: 본 문서의 `Current`는 V3 SPARSE/ROW/BANK candidate를 의미함.
> V4 full UZH sweep 결과는 현재 tracked result에 없음.

## Provenance

| Item | Recorded value |
|---|---|
| Dataset | UZH Event-Camera Dataset `shapes_rotation` |
| Official URL | `https://rpg.ifi.uzh.ch/datasets/davis/shapes_rotation.zip` |
| ZIP SHA-256 | `56aade6bf53dcf73e8fe40905ccac8385cd7606bc9a85103bf2c9f9045117551` |
| ZIP / `events.txt` size | 157,446,920 / 509,907,771 bytes |
| Source rows read | first 200,000 |
| Crop | `x=56, y=26, width=128, height=128` |
| Cropped events | 92,861 (pinned result reproduced exactly) |
| Clock | 100 MHz |
| Full evaluation date | 2026-08-26 KST |

- CIFAR10-DVS 검색 범위: 모든 Git refs/history와 local `C:\Project_V2\AI-semi` tree임
- 검색 keyword: `cifar10dvs`, `CIFAR10`, `cifar`, `.aedat`임
- 검색 결과: 기존 사용을 입증하는 script/result/dataset/commit을 찾지 못함
- 결론: **기존 team GitHub/local 자료에서 CIFAR10-DVS 사용 이력을 확인할 수 없음**
- 주의: 확인되지 않은 CIFAR10-DVS를 team reproduction dataset으로 표기하지 않음
- Raw/generated data: Git에서 제외된 `data/` 아래에 저장함
- 전체 flow 재현 명령은 다음과 같음

```powershell
powershell -ExecutionPolicy Bypass -File scripts\dataset\run_all_dataset.ps1
```

## Canonical trace and loss accounting

- Loader 순서: source 200,000 rows read → 첫 timestamp 기준 quantization → crop → coordinate rebase임
- Common event format: `event_id,timestamp,cycle,x,y,polarity`임
- Canonical transaction: 동일 `{cycle, 2x2 tile}` event를 OR-reduce함
- Transaction payload: `tile_id, ON[3:0], OFF[3:0]`임
- 1000× tile transaction: 92,669건임
- 1000× canonical polarity bits: 92,861개임
- Source-to-interface duplicate loss: 0임. Cropped source event 92,861개가 canonical bit 92,861개로 유지됨
- `ready=0` 미수용: internal loss가 아니라 input backpressure로 집계함
- Accepted RTL transaction: 모두 decode 후 원본과 비교함
- Nine XSim runs unintended loss: 0임

## Software sweep

- Link model: 16-bit word/cycle 1개임
- Arbitration: packet-locked bank round-robin임
- Pending storage: tile당 1 slot임
- Encoding: RTL과 동일한 packet cost와 format-selection rule 사용함
- 사용 목적: 긴 full sweep의 architecture/link latency 분석임
- 주의: software latency는 post-layout timing이 아님
- Model risk 확인: sparse/dense/burst window를 actual RTL XSim과 cross-check함

| Speed | Design | Accepted events/transactions | Backpressured events/transactions | Output words | Words/input | Words/accepted | Bits/accepted | Mean | P99 | Throughput | Max pending | S/R/B packets | Loss |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1x | RAW / Team | 92,861 / 92,772 | 0 / 0 | 278,066 | 2.9944 | 2.9944 | 47.91 | 2.13 | 5 | 0.000495 | 4 | 0/92,647/0 | 0 |
| 1x | Current | 92,861 / 92,772 | 0 / 0 | 185,633 | 1.9990 | 1.9990 | 31.98 | 1.09 | 3 | 0.000495 | 4 | 92,683/89/0 | 0 |
| 10x | RAW / Team | 92,861 / 92,772 | 0 / 0 | 278,066 | 2.9944 | 2.9944 | 47.91 | 2.13 | 5 | 0.004950 | 4 | 0/92,647/0 | 0 |
| 10x | Current | 92,861 / 92,772 | 0 / 0 | 185,633 | 1.9990 | 1.9990 | 31.98 | 1.09 | 3 | 0.004950 | 4 | 92,683/89/0 | 0 |
| 100x | RAW / Team | 92,791 / 92,702 | 70 / 69 | 277,858 | 2.9922 | 2.9944 | 47.91 | 2.56 | 8 | 0.049460 | 15 | 0/92,578/0 | 0 |
| 100x | Current | 92,806 / 92,717 | 55 / 54 | 185,523 | 1.9979 | 1.9990 | 31.98 | 1.25 | 4 | 0.049468 | 13 | 92,628/89/0 | 0 |
| 500x | RAW / Team | 78,430 / 78,307 | 14,431 / 14,411 | 233,149 | 2.5107 | 2.9727 | 47.56 | 51.39 | 303 | 0.208966 | 71 | 0/77,421/0 | 0 |
| 500x | Current | 91,636 / 91,493 | 1,225 / 1,225 | 183,106 | 1.9718 | 1.9982 | 31.97 | 8.35 | 76 | 0.244211 | 49 | 91,272/145/17 | 0 |
| 1000x | RAW / Team | 46,610 / 46,510 | 46,251 / 46,159 | 136,626 | 1.4713 | 2.9313 | 46.90 | 145.14 | 502 | 0.248127 | 111 | 0/45,058/0 | 0 |
| 1000x | Current | 63,458 / 63,327 | 29,403 / 29,342 | 126,665 | 1.3640 | 1.9960 | 31.94 | 149.38 | 2,577 | 0.337756 | 194 | 62,825/198/39 | 0 |
| 2000x | RAW / Team | 26,629 / 26,563 | 66,232 / 66,006 | 76,837 | 0.8274 | 2.8855 | 46.17 | 208.42 | 644 | 0.282893 | 143 | 0/25,137/0 | 0 |
| 2000x | Current | 36,277 / 36,174 | 56,584 / 56,395 | 72,354 | 0.7792 | 1.9945 | 31.91 | 320.48 | 5,051 | 0.384596 | 338 | 35,801/182/5 | 0 |
| 5000x | RAW / Team | 12,572 / 12,503 | 80,289 / 79,678 | 35,015 | 0.3771 | 2.7852 | 44.56 | 288.29 | 832 | 0.331426 | 205 | 0/11,256/0 | 0 |
| 5000x | Current | 17,165 / 17,093 | 75,696 / 75,088 | 34,207 | 0.3684 | 1.9928 | 31.89 | 504.79 | 4,710 | 0.447938 | 529 | 16,888/110/2 | 0 |

- 전체 21-row table: `results/summary.csv`에 저장함
- RAW/Team word count: 이 trace에서 동일함
- GROUP3: 500×/1000×/2000×에서 각각 1회 선택되지만 total word cost는 변하지 않음
- 나머지 Team token: RAW8임
- BIN4/pair token: 선택되지 않음
- Workload 해석: real data 대부분이 tile-cycle당 polarity bit 1개인 singleton임

## Actual RTL XSim windows

- 기준 speed: 1000×임
- `sparse`: non-overlapping occupied bin 중 25th-percentile bin임
- `dense`: maximum 1024-cycle bin임
- `burst`: 1024-cycle 구간 안의 maximum 128-cycle burst임
- 선택 목적: manual cherry-picking 방지함

| Window | Design | Accepted transactions | Output words | Words/accepted | Round-trip |
|---|---|---:|---:|---:|---|
| sparse | Fair RAW | 111 | 333 | 3.0000 | PASS |
| sparse | Team second | 111 | 333 | 3.0000 | PASS |
| sparse | Current | 111 | 222 | 2.0000 | PASS |
| dense | Fair RAW | 416 | 1,228 | 2.9519 | PASS |
| dense | Team second | 416 | 1,228 | 2.9519 | PASS |
| dense | Current | 649 | 1,298 | 2.0000 | PASS |
| burst | Fair RAW | 423 | 1,237 | 2.9243 | PASS |
| burst | Team second | 423 | 1,237 | 2.9243 | PASS |
| burst | Current | 641 | 1,280 | 1.9969 | PASS |

- Compile/elaboration: 세 top을 Vivado 2019.1 XSim에서 각각 독립 수행함
- Current word-efficiency 개선: sparse 33.33%, dense 32.25%, burst 31.71%임
- Accepted transaction: dense/burst에서 크게 증가함
- Decoder result: missing/extra/payload/timestamp mismatch 모두 0임

## Evidence-driven iteration

- 시도: Previous ROW/BANK의 `ST_ANALYZE`를 지연하는 limited iteration 수행함
- Functional result: full regression PASS함
- Dense result: 1,516 words로 동일하고 accepted transaction은 533→531로 감소함
- Burst result: 1 word 감소했지만 accepted transaction도 1건 감소함
- 판단: 실익이 없어 해당 변경을 revert함
- 후속 변경: workload evidence에 따라 singleton용 SPARSE format 추가함
- 최종 결과: SPARSE/ROW/BANK candidate가 추가 redesign 없이 full gate 통과함

## Visual QA

- `results/figures/uzh_dense_event_comparison.png`: original/decoded event map 비교함. x는 오른쪽, y는 아래쪽, ON은 red, OFF는 blue임
- `results/figures/uzh_activity_mode_map.png`: bank activity와 multi-row opportunity 분포를 표시함
- `results/figures/uzh_performance_comparison.png`: efficiency/latency/throughput/backpressure/mode fraction을 표시함
- `results/animations/uzh_shapes_rotation_compare.gif`: 800×440, nonempty 24 frames로 original과 accepted/decoded event를 비교함
- Visual 확인: 생성 후 PNG와 animation 첫/마지막 frame을 직접 확인함
- 이상 여부: empty/corrupt image, coordinate inversion, single-frame animation 없음

## SPARSE/ROW/BANK full-evaluation conclusion (2026-08-26)

- 재현 조건: 기존 provenance/crop/canonicalization을 그대로 사용함
- 실행 범위: 7-speed sweep과 RTL window 9개임
- Word efficiency: RAW 대비 28.45~33.24% 개선함
- SPARSE fraction: Current에서 99.34% 이상임
- Acceptance: 500×부터 RAW보다 뚜렷하게 증가함
- Latency: 1000× 이상 P99는 RAW보다 높음
- 해석: 더 많은 traffic 수용으로 single global link queue가 길어지는 trade-off임
- Unintended loss: 0임
- 결과 위치: `results/summary.csv`, `results/metrics/dataset_results.json`임
