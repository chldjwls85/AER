# AER V3 → V4 → V5 Design Evolution

## 1. 배경

- 목표는 128×128 polarity-event sensor에서 Traditional AER의 event-by-event 전송 반복을 줄이면서 위치/ON-OFF/timestamp를 lossless하게 유지하는 것임.
- 공통 입력 단위는 2×2 tile, bank는 4×4 tiles = 8×8 pixels로 구성함.
- 최종 출력은 16-bit `valid/ready/last` stream을 사용함.
- 설계 판단 순서는 기능 정확성 → 전송 효율/accepted/latency → synthesis timing/area 순으로 진행함.

## 2. V3: SPARSE/ROW/BANK

### 설계 의도

- singleton transaction은 2-word SPARSE로 직접 전송함.
- 같은 row의 여러 tile은 ROW packet으로 묶음.
- multi-row locality가 충분하면 BANK packet을 선택해 metadata를 추가 공유하고자 함.

### 결과

- Functional regression 5/5 PASS함.
- Random round-trip 2,050/2,050 PASS함.
- UZH full sweep에서 RAW 대비 words/accepted를 약 28.45~33.24% 감소함.
- 1000×에서 RAW 2.9313 → V3 1.9960 words/accepted로 31.90% 감소함.
- 500× 이상에서 RAW보다 더 많은 event를 accepted함.
- 1000× 이상에서는 accepted traffic 증가와 single global output queue 영향으로 P99 latency가 증가함.

### NO-GO 판단

- BANK mode 사용률이 실제 workload에서 매우 낮음.
- bank-wide analysis와 추가 control logic 대비 실효 이득이 작음.
- full synthesis 비용과 timing risk가 커 lightweight 구조가 필요하다고 판단함.

## 3. V4: Lightweight SPARSE/ROW

### 변경

- BANK mode와 bank-wide analysis를 제거함.
- SPARSE/ROW packet format과 lossless semantics를 유지함.
- selected 4-tile row만 분석하도록 단순화함.
- Global Readout은 4×4 banks = 1 region, 총 16 region의 2-stage hierarchy를 사용함.

### 기능 검증

- Directed regression PASS함.
- Random exact reconstruction 2,050/2,050 PASS함.
- reset/backpressure/simultaneous request를 확인함.

### 연구실 DC 결과

- Critical Path: 28.05 ns임.
- WNS: -18.27 ns임.
- TNS: -1,058,885.12 ns임.
- Violating Paths: 77,829개임.
- Leaf Cell Count: 724,826개임.
- Design Area: 3,511,071.11임.
- Runtime: 2,776 s임.

### 발견한 병목

```text
global aer_timebase
  -> global time_now distribution
  -> bank capture logic
  -> stored_time_reg
```

- 하나의 16-bit global timestamp가 256개 bank로 fan-out되는 경로가 worst setup path의 주요 원인으로 확인됨.
- packet architecture를 다시 바꾸기보다 timestamp distribution만 locality에 맞게 분산하는 V5를 설계함.

## 4. V5: Regional Timebase

### 변경 원칙

V5는 새로운 packet architecture가 아님.

다음 V4 요소를 유지함.

- SPARSE packet
- ROW packet
- SPARSE/ROW selection
- bank FSM
- packet format
- hierarchical global readout
- region buffer
- root mux
- input/output protocol

Timestamp distribution만 변경함.

```text
Before
1 global 16-bit timebase
  -> 256 banks

After
16 regional 16-bit timebases
  -> each timebase serves 16 banks
```

Region mapping은 기존 Global Readout의 spatial 4×4-bank region과 동일하게 맞춤.

```text
bank_row   = bank_id / BANK_COLS
bank_col   = bank_id % BANK_COLS
region_row = bank_row / 4
region_col = bank_col / 4
region_id  = region_row * REGION_COLS + region_col
```

128×128 기준 `BANK_COLS=16`, `REGION_COLS=4`를 사용함.

### 기능 동일성 검증

`tb_aer_v5_timebase_sanity.v`

- 16개 counter elaboration을 확인함.
- reset 0, cycle마다 +1, 64 cycles lockstep을 확인함.
- re-reset 후 lockstep recovery를 확인함.
- 각 region이 정확히 16 banks를 포함함.
- 256 banks 전체 region mapping mismatch 0을 확인함.
- `AER_V5_TIMEBASE_SANITY_PASS`를 확인함.

`tb_aer_v4_v5_equiv.v`

- singleton ON/OFF, ROW, multi-region simultaneous, backpressure를 비교함.
- output mismatch 0, `tile_in_ready` mismatch 0을 확인함.
- deadlock 없음.
- `AER_V4_V5_EQUIV_PASS`를 확인함.

## 5. V4 → V5 연구실 DC 비교

동일 Synopsys DC/SAED32/10 ns 조건에서 비교함.

| 항목 | V4 | V5 | 변화 |
|---|---:|---:|---:|
| Critical Path | 28.05 ns | 25.26 ns | -9.9% |
| WNS | -18.27 ns | -15.49 ns | +2.78 ns |
| TNS | -1,058,885.12 ns | -770,141.69 ns | 약 27.3% 감소 |
| Violating Paths | 77,829 | 78,304 | 거의 동일 |
| Leaf Cells | 724,826 | 725,497 | +0.09% |
| Sequential Cells | 111,369 | 111,609 | +240 |
| Cell Area | 2,359,467.60 | 2,347,645.58 | -0.50% |
| Design Area | 3,511,071.11 | 3,502,284.69 | -0.25% |
| Runtime | 2,776 s | 3,045 s | +9.7% |

- Sequential +240은 추가 15 counters × 16 bit와 일치함.
- Area 감소 원인은 단정하지 않음.
- 중요한 판단은 Regional Timebase에 따른 유의미한 area penalty가 관찰되지 않았다는 점임.

## 6. Critical Path 변화

V5 연구실 DC worst path는 다음과 같음.

```text
pending_reg[0]
  -> bank packetizer internal logic
  -> sparse_pixel_reg[0]
```

- V4 worst path의 global timestamp distribution이 V5 worst path에서 사라짐.
- Regional Timebase가 목표한 timestamp fan-out 병목을 제거했음을 확인함.
- 이후 bank-local analyze/selection path가 새로운 critical path로 드러남.

## 7. 대회 Genus 최종 결과

- Cadence Genus 23.14-s090_1, GSCLIB045 slow, 0.9 V/125°C에서 실행함.
- Clock 10 ns, uncertainty 0.2 ns를 적용함.
- full `syn_generic → syn_map → syn_opt → report`를 완료함.

| 항목 | V5 Genus |
|---|---:|
| Timing | **MET** |
| WNS | **+0.5819 ns** |
| TNS | **0 ns** |
| Violating Paths | **0** |
| Worst data path | 9.075 ns |
| Leaf instances | 552,073 |
| Sequential | 111,609 |
| Combinational | 440,464 |
| Cell Area | 1,590,675.448 |
| Power estimate | 약 43.84 mW |
| Elapsed Runtime | 9,207 s |

- Genus worst path도 `pending_reg -> sparse_pixel_reg`로 확인함.
- 연구실 DC와 대회 Genus에서 동일한 다음 bank-local bottleneck이 관찰됨.
- 대회 Genus에서는 100 MHz timing constraint를 만족함.
- DC와 Genus의 절대 area는 library/technology/flow가 다르므로 직접 비교하지 않음.

## 8. 최종 판단

- V3: traffic 효율 개선은 확인했으나 BANK complexity의 실효성이 낮아 synthesis 관점에서 구조 단순화가 필요함.
- V4: lightweight SPARSE/ROW로 단순화했으나 global timestamp fan-out timing bottleneck을 확인함.
- V5: packet behavior를 유지하면서 Regional Timebase로 timestamp distribution 병목을 제거함.
- 최종 대회 Genus에서 100 MHz timing MET를 확인함.
- 다음 최적화 후보는 bank packetizer 내부 `pending_reg -> sparse_pixel_reg` analyze/selection 경로임.

## 9. 관련 파일

- RTL: `rtl/aer_top_v5.v`, `rtl/filelist_v5.f`
- Packetizer: `rtl/bank/aer_bank_packetizer_v4.v`
- Verification: `tb/regression/tb_aer_v5_timebase_sanity.v`, `tb/regression/tb_aer_v4_v5_equiv.v`
- DC: `scripts/dc/dc_v5.tcl`, `scripts/dc/run_dc_v5.csh`
- Genus: `scripts/genus/genus_v5_full.tcl`, `scripts/genus/run_genus_v5_tmp.sh`
- DC reports: `results/synthesis/dc_v5/`
- Genus summary: `results/synthesis/genus_v5/`
