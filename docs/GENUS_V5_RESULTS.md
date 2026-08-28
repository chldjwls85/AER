# V5 Genus 최종 합성 결과

## 1. 목적

- V5 `aer_top_v5_128`을 대회 서버의 Cadence Genus 환경에서 full synthesis함.
- V4의 SPARSE/ROW packet architecture와 hierarchical readout을 유지하고, V5에서 적용한 16개 Regional Timebase가 실제 합성에서 유지되는지 확인함.
- 100 MHz constraint에서 최종 timing/area/power estimate를 확인함.

## 2. 실행 조건

| 항목 | 조건 |
|---|---|
| Tool | Cadence Genus 23.14-s090_1 |
| Top | `aer_top_v5_128` |
| Library | `slow_vdd1v0_basicCells.lib` |
| Technology | GSCLIB045 |
| PVT | 0.9 V / 125°C |
| Clock | 10.000 ns (100 MHz) |
| Clock uncertainty | 0.200 ns |
| Reset | `rst_n` false path |
| Effort | `syn_generic/map/opt = medium` |
| Run directory | `/tmp/aiasic26230_aer_genus_v5_20260827_195845_167663` |

- 실행은 기존 run과 분리된 user-specific `/tmp` directory에서 수행함.
- `HOME/TMPDIR/TMP/TEMP`를 run directory 내부로 격리함.
- `dont_touch`, `preserve`, `keep` attribute를 추가하지 않은 clean synthesis임.

## 3. Stage 완료

| Stage | 결과 | 시간 |
|---|---|---:|
| read_hdl | DONE | 0 s |
| elaborate | DONE | 281 s |
| check_design | DONE | 0 s |
| syn_generic | DONE | 5,795 s |
| syn_map | DONE | 2,717 s |
| syn_opt | DONE | 357 s |
| report | DONE | 132 s |

- 전체 marker `AER_GENUS_V5_FULL_SYNTHESIS_DONE`을 확인함.
- QoR report의 elapsed runtime은 9,207 s임.
- 최종 console에서 실제 `Error:`/`Fatal:` marker는 확인되지 않음.

## 4. Timing

| 항목 | 결과 |
|---|---:|
| Target | 100 MHz |
| WNS | **+0.5819 ns** |
| TNS | **0.0 ns** |
| Violating Paths | **0** |
| Timing status | **MET** |
| Worst data path | 9.075 ns |

Worst setup path는 다음과 같음.

```text
pending_reg[0]
  -> bank packetizer internal analysis/selection logic
  -> sparse_pixel_reg[0]
```

- Startpoint: `top_i/gen_bank[184].bank_packetizer_i/pending_reg[0]`
- Endpoint: `top_i/gen_bank[184].bank_packetizer_i/sparse_pixel_reg[0]`
- V4에서 문제였던 global timestamp distribution이 최종 worst path에 나타나지 않음.
- 연구실 DC V5에서도 `pending_reg -> sparse_pixel_reg`가 worst path로 확인되어 서로 다른 tool/library에서 다음 bank-local bottleneck이 동일하게 관찰됨.

## 5. Area / Cell

| 항목 | 결과 |
|---|---:|
| Leaf instances | 552,073 |
| Sequential instances | 111,609 |
| Combinational instances | 440,464 |
| Hierarchical instances | 298 |
| Cell Area | **1,590,675.448** |

- Area report에서 16개의 `gen_regional_timebase[*].regional_timebase_i` hierarchy가 확인됨.
- 따라서 Regional Timebase가 합성 과정에서 하나의 counter로 단순 merge된 것으로 보이지 않음.
- Genus 절대 area는 연구실 DC SAED32 area와 직접 비교하지 않음. Library/technology/optimization flow가 다르기 때문임.

## 6. Power

- Genus `report_power` 결과: **0.0438355 W ≈ 43.84 mW**임.
- Register category 약 64.99%, logic category 약 35.01%임.
- 해당 값은 synthesis 단계의 vectorless/default-activity estimate임.
- CTS, routing, extracted parasitic, real workload switching activity를 반영한 signoff power가 아니므로 참고값으로만 사용함.

## 7. 결론

- V5는 대회 Genus 환경에서 **100 MHz timing constraint를 만족함**.
- WNS +0.5819 ns, TNS 0 ns, violating path 0으로 확인함.
- Regional Timebase 16개가 hierarchy에 유지됨.
- Timestamp fan-out은 worst path에서 제외되고 bank-local `pending_reg -> sparse_pixel_reg` 경로가 다음 timing bottleneck으로 이동함.
- V5의 packet behavior는 V4와 equivalence verification으로 동일성을 확인한 상태이므로, V5는 최종 Proposed AER 후보로 사용할 수 있음.

## 8. 결과 파일

- `results/synthesis/genus_v5/genus_v5_summary.txt`
- `results/synthesis/genus_v5/results_summary.txt`

> 업로드된 대회 ZIP에는 full `area.rpt/qor.rpt/timing.rpt/power.rpt` 원본이 포함되지 않았으므로 GitHub에는 제공된 원본 summary와 최종 report 수치를 정리한 summary를 보존함.
