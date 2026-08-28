# Reference Versions

## Repository / Latest Architecture

| Item | Value |
|---|---|
| Repository | `https://github.com/chldjwls85/AER` |
| Working Branch | `AER_hyeonho` |
| Latest Architecture | **V5 Regional Timebase** |
| Top | `aer_top_v5_128` |
| Filelist | `rtl/filelist_v5.f` |
| Functional Checkpoint | `78b228d9f0d64943ec595fb80ff02f4c1fea0e54` |

## Traffic Reference

| Item | Value |
|---|---|
| Team Second Branch | `codex/aer-v1-global-readout` |
| Team Pinned SHA | `da686477ca054faada5f66d369f1fb253b2bf562` |
| Fair RAW Top | `aer_v1_raw_top_128`, `ENABLE_BINNING=0` |
| Team Second Top | `aer_v1_top_128`, `ENABLE_BINNING=1` |
| V3 Full-Evaluation Basis | `ad8fbd05b88e4645847dc438a5f3be668998882c` |
| Dataset | UZH Event-Camera Dataset `shapes_rotation` |
| UZH Archive SHA-256 | `56aade6bf53dcf73e8fe40905ccac8385cd7606bc9a85103bf2c9f9045117551` |

## V5 Functional Verification

- `AER_V5_TIMEBASE_SANITY_PASS` 확인함.
- `AER_V4_V5_EQUIV_PASS` 확인함.
- V4와 V5의 packet behavior가 동일하고 timestamp distribution만 변경되었음을 확인함.

## Research DC Result Reference

- Top: `aer_top_v5_128`임.
- Clock: 10 ns, uncertainty 0.2 ns임.
- Critical Path: 25.26 ns임.
- WNS: -15.49 ns임.
- TNS: -770,141.69 ns임.
- Design Area: 3,502,284.69임.
- Worst path: `pending_reg → sparse_pixel_reg`임.
- Result: `results/synthesis/dc_v5/`에 보존함.

## Competition Genus Result Reference

실제 최종 report 기준 결과임.

- Top: `aer_top_v5_128`임.
- Library: GSCLIB045 `slow_vdd1v0_basicCells.lib`임.
- PVT: 0.9 V / 125°C임.
- Clock: 10 ns, uncertainty 0.2 ns임.
- Timing: **MET**임.
- WNS: +0.5819 ns임.
- TNS: 0 ns임.
- Violating Paths: 0임.
- Worst Data Path: 9.075 ns임.
- Cell Area: 1,590,675.448임.
- Power Estimate: 약 43.84 mW임.
- Worst path: `pending_reg → sparse_pixel_reg`임.
- 상세: `docs/GENUS_V5_RESULTS.md`에 기록함.

## 비교 주의

- Research DC와 Competition Genus는 library/technology/optimization flow가 다름.
- 두 환경의 절대 area/timing 수치를 서로 직접 비교하지 않음.
- DC는 V4→V5 구조 변경의 상대 효과를 판단하는 데 사용함.
- Genus는 최종 Proposed AER의 대회 환경 100 MHz target 만족 여부를 판단하는 데 사용함.
