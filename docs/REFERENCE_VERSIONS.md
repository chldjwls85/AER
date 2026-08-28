# Reference Versions

## Repository / latest

| Item | Value |
|---|---|
| Repository | `https://github.com/chldjwls85/AER` |
| Working branch | `AER_hyeonho` |
| Latest architecture | **V5 Regional Timebase** |
| V5 top | `aer_top_v5_128` |
| V5 filelist | `rtl/filelist_v5.f` |
| V5 functional checkpoint | `78b228d9f0d64943ec595fb80ff02f4c1fea0e54` |
| V5 DC flow checkpoint | `8d3f2bf7ccb56cc15a16963bb97b5a9f82199621` |
| V5 Genus flow checkpoint | `d655f227215efcc2ea60213cc77c74a3649dccbd` |
| Genus server invocation fix | `2ed285895d9b67fbcb99b4cd1f2f6d4ceaf73faa` |

## Traffic reference

| Item | Value |
|---|---|
| Team second branch | `codex/aer-v1-global-readout` |
| Team pinned SHA | `da686477ca054faada5f66d369f1fb253b2bf562` |
| Fair RAW top | `aer_v1_raw_top_128`, `ENABLE_BINNING=0` |
| Team second top | `aer_v1_top_128`, `ENABLE_BINNING=1` |
| V3 full-evaluation basis | `ad8fbd05b88e4645847dc438a5f3be668998882c` |
| Dataset | UZH Event-Camera Dataset `shapes_rotation` |
| UZH archive SHA-256 | `56aade6bf53dcf73e8fe40905ccac8385cd7606bc9a85103bf2c9f9045117551` |

## Final V5 result references

### Research DC

- Tool: Synopsys DC V-2023.12-SP4임.
- Top: `aer_top_v5_128`임.
- Run date: 2026-08-28임.
- Result summaries: `results/synthesis/dc_v5/`임.

### Competition Genus

- Tool: Cadence Genus 23.14-s090_1임.
- Library: GSCLIB045 `slow_vdd1v0_basicCells.lib`임.
- PVT: 0.9 V / 125°C임.
- Clock: 10 ns, uncertainty 0.2 ns임.
- Result: **Timing MET, WNS +0.5819 ns, TNS 0, violating paths 0**임.
- Summary: `results/synthesis/genus_v5/`임.

## 비교 주의

- DC와 Genus는 library/technology/optimization flow가 다름.
- 절대 area/timing 수치를 서로 직접 비교하지 않음.
- V4→V5 DC 상대 변화와 대회 Genus 최종 target 만족 여부를 각각 해석함.
