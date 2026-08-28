# V5 Genus 최종 합성 결과

## 1. 목적

- 최종 Proposed AER인 V5 `aer_top_v5_128`의 대회 서버 Logic Synthesis 결과를 기록함.
- 100 MHz constraint에서 timing closure 여부와 area/power estimate를 확인함.
- Regional Timebase 적용 후 실제 critical path가 어디로 이동했는지 확인함.

## 2. 합성 조건

| 항목 | 조건 |
|---|---|
| Tool | Cadence Genus 23.14-s090_1 |
| Top | `aer_top_v5_128` |
| Technology | GSCLIB 45 nm |
| Library | `slow_vdd1v0_basicCells.lib` |
| PVT | 0.9 V / 125°C |
| Clock | 10.000 ns (100 MHz) |
| Clock Uncertainty | 0.200 ns |

`check_design.rpt`에서 unresolved reference와 empty module이 없음을 확인함.

## 3. Timing 결과

`qor.rpt`와 `timing.rpt` 기준 결과임.

| 항목 | 결과 |
|---|---:|
| Target Clock | 100 MHz |
| Timing Status | **MET** |
| WNS | **+0.5819 ns** |
| TNS | **0 ns** |
| Violating Paths | **0** |
| Worst Data Path | **9.075 ns** |

Worst setup path는 다음과 같음.

```text
Startpoint : top_i/gen_bank[184].bank_packetizer_i/pending_reg[0]
Endpoint   : top_i/gen_bank[184].bank_packetizer_i/sparse_pixel_reg[0]

pending_reg[0]
  → bank packetizer internal analysis / selection logic
  → sparse_pixel_reg[0]
```

- 10 ns target에서 +0.5819 ns timing margin을 확보함.
- V4에서 확인된 global timestamp distribution 경로는 최종 worst path에 나타나지 않음.
- 새로운 critical path는 Bank Packetizer 내부 analyze/selection 경로로 이동함.
- 현재 WNS를 단순 환산하면 약 106 MHz 수준의 Fmax가 추정되지만, 별도 clock sweep 결과가 아니므로 확정 Fmax로 사용하지 않음.

## 4. Area / Cell 결과

`area.rpt`와 `qor.rpt` 기준 결과임.

| 항목 | 결과 |
|---|---:|
| Leaf Instances | 552,073 |
| Sequential Instances | 111,609 |
| Combinational Instances | 440,464 |
| Hierarchical Instances | 298 |
| Cell Area | **1,590,675.448** |

- Area report에서 `gen_regional_timebase[0]`부터 `[15]`까지 16개 Regional Timebase hierarchy가 각각 확인됨.
- 따라서 V5의 16개 Regional Timebase가 합성 결과에 유지됨을 확인함.

## 5. Power 결과

`power.rpt` 기준 결과임.

| 항목 | 결과 |
|---|---:|
| Total Power | **0.0438355 W ≈ 43.84 mW** |
| Register | 28.4872 mW (64.99%) |
| Logic | 15.3483 mW (35.01%) |

- 해당 값은 Logic Synthesis 단계의 power estimate임.
- 실제 workload switching activity, CTS, routing, extracted parasitic을 반영한 post-layout signoff power가 아니므로 참고값으로 사용함.

## 6. Run 완료 확인

실제 `genus_console.log`에서 다음 전체 stage 완료를 확인함.

- `read_hdl` DONE
- `elaborate` DONE
- `check_design` DONE
- `syn_generic` DONE
- `syn_map` DONE
- `syn_opt` DONE
- `report` DONE
- `AER_GENUS_V5_FULL_SYNTHESIS_DONE` 확인함.
- `Error:` / `Fatal:` marker는 확인되지 않음.

QoR report 기준 elapsed runtime은 **9,207 s**임.

## 7. 최종 해석

- V5 Proposed AER는 대회 Genus 환경에서 **100 MHz timing constraint를 만족함**.
- WNS +0.5819 ns, TNS 0 ns, violating path 0을 확인함.
- Regional Timebase 적용 후 timestamp fan-out이 최종 critical path에서 제외됨.
- 연구실 DC와 대회 Genus 모두 V5에서 `pending_reg → sparse_pixel_reg`를 다음 bank-local bottleneck으로 확인함.
- 따라서 Regional Timebase는 기존 timestamp distribution 병목을 제거하는 방향으로 유효했음을 확인함.

## 8. 원본 결과 파일

`results/synthesis/genus_v5/`에 실제 대회 서버에서 가져온 원본 report를 보존함.

- `genus_v5_summary.txt`
- `area.rpt`
- `check_design.rpt`
- `power.rpt`
- `qor.rpt`
- `timing.rpt`

대용량 console log는 repository에 중복 보존하지 않고, stage 완료 여부와 Error/Fatal 유무만 본 문서에 기록함.
