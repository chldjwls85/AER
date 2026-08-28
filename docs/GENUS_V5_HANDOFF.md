# V5 Genus 합성 Handoff / Final Result

## 최종 상태

- Top: `aer_top_v5_128`임.
- Cadence Genus 23.14-s090_1에서 full synthesis를 완료함.
- `read_hdl → elaborate → check_design → syn_generic → syn_map → syn_opt → report` 전 단계를 완료함.
- `AER_GENUS_V5_FULL_SYNTHESIS_DONE` marker를 확인함.
- 최종 console에서 실제 `Error:`/`Fatal:` marker는 확인되지 않음.

## 실행 조건

- Technology: GSCLIB045임.
- Library: `slow_vdd1v0_basicCells.lib`임.
- PVT: 0.9 V / 125°C임.
- Clock: 10.000 ns / 100 MHz임.
- Clock uncertainty: 0.200 ns임.
- Reset: `rst_n` false path임.
- Effort: `syn_generic/map/opt = medium`임.
- `dont_touch`, `preserve`, `keep` attribute를 추가하지 않음.

## 최종 결과

| 항목 | 결과 |
|---|---:|
| Timing | **MET** |
| WNS | **+0.5819 ns** |
| TNS | **0 ns** |
| Violating Paths | **0** |
| Worst data path | 9.075 ns |
| Leaf Instances | 552,073 |
| Sequential Instances | 111,609 |
| Combinational Instances | 440,464 |
| Cell Area | 1,590,675.448 |
| Power estimate | 약 43.84 mW |
| Elapsed Runtime | 9,207 s |

- Area report에서 16개 Regional Timebase hierarchy를 확인함.
- Worst path는 `pending_reg → sparse_pixel_reg` bank-local path로 확인함.
- V4의 global timestamp distribution path는 worst path에서 제외됨.
- Power는 synthesis-stage vectorless/default-activity estimate이며 signoff power가 아님.

## 결과 문서

- 상세 분석: `docs/GENUS_V5_RESULTS.md`
- Original run summary: `results/synthesis/genus_v5/genus_v5_summary.txt`
- Curated result summary: `results/synthesis/genus_v5/results_summary.txt`

## 실행 구조

- user-specific unique `/tmp` directory에서 실행함.
- `HOME/TMPDIR/TMP/TEMP`를 run directory 내부로 격리함.
- launcher: `scripts/genus/run_genus_v5_tmp.sh`
- synthesis driver: `scripts/genus/genus_v5_full.tcl`

## 재현 주의

- server-specific library/setup과 reset constraint는 environment hook으로 전달함.
- 연구실 DC와 Genus의 절대 PPA는 직접 비교하지 않음.
- Genus 결과는 logic synthesis 기준이며 Innovus P&R/post-layout signoff 결과가 아님.
