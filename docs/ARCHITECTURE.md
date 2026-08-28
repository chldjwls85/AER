# Architecture

> 최신 기준: V5 `aer_top_v5_128`임. V3/V4 변화 과정은 `AER_V3_V5_DESIGN_EVOLUTION.md` 참조함.

## Hierarchy

```text
128×128 polarity-event sensor
  |
  | 4096 × {valid, ON[3:0], OFF[3:0]}
  v
256 × aer_bank_packetizer_v4
  | 4×4 tiles/bank = 8×8 pixels/bank
  | SPARSE / ROW packet
  v
16 spatial regions
  | each region = 4×4 banks = 16 banks
  | 16-bank packet mux
  | 2-entry region buffer
  v
root packet mux
  v
16-bit out_data / out_valid / out_ready / out_last
```

Timestamp distribution은 다음과 같음.

```text
16 × aer_timebase
  |
  | each 16-bit timebase serves one spatial 4×4-bank region
  v
16 banks / region
```

## V5 핵심 변경

- V4 packet architecture와 global readout을 유지함.
- 1개의 global 16-bit timebase를 16개의 regional 16-bit timebase로 변경함.
- 모든 regional counter는 동일 `clk/rst_n`, reset 0, cycle마다 +1로 lockstep 동작함.
- Global Readout region과 Regional Timebase region mapping을 동일하게 사용함.

Region mapping은 다음과 같음.

```text
bank_row   = bank_id / BANK_COLS
bank_col   = bank_id % BANK_COLS
region_row = bank_row / 4
region_col = bank_col / 4
region_id  = region_row * REGION_COLS + region_col
```

128×128 기준 `BANK_COLS=16`, `REGION_COLS=4`임.

## Modules

| Module | Role |
|---|---|
| `aer_timebase` | 16-bit free-running timestamp counter |
| `aer_bank_packetizer_v4` | 16 tile pending slots, SPARSE/ROW selection and serialization |
| `aer_packet_rr_arbiter` | packet-locked look-ahead round-robin grant |
| `aer_packet_mux` | selected stream ready/valid/last routing |
| `aer_stream_buffer2` | two-entry elastic word buffer |
| `aer_global_readout` | 4×4-bank regional muxes and root mux |
| `aer_top_v5`, `aer_top_v5_128` | regional timebase/bank generation and public interface |

## Bank behavior

- Pending storage: tile마다 accepted ON/OFF bitmap과 16-bit timestamp를 1개씩 저장함.
- SPARSE: singleton event를 address + full timestamp 2 words로 전송함.
- ROW: 같은 selected tile row의 multi-tile event를 header/time/data 형태로 전송함.
- V5에서는 BANK mode와 bank-wide analysis를 사용하지 않음.
- Backpressure 중 `out_data/out_valid/out_last`를 handshake 전까지 유지함.
- Pending clear는 실제 output handshake에 맞춰 수행함.

## Global readout

- Region: 16×16 banks를 spatial 4×4-bank region 16개로 분할함.
- Regional mux: packet 끝(`last`)까지 선택 bank를 고정함.
- Region buffer: 2-entry elastic buffer를 사용함.
- Root mux: 16 region streams를 packet-locked round-robin으로 선택함.
- Packet interleave를 방지함.

## V5 timing 의미

- V4 연구실 DC worst path는 global timestamp distribution → bank capture 경로였음.
- V5에서는 해당 path가 worst path에서 제거됨.
- 연구실 DC와 대회 Genus 모두 bank-local `pending_reg → sparse_pixel_reg`가 다음 worst path로 확인됨.
- 대회 Genus에서는 10 ns/100 MHz constraint를 만족함.

## Architectural limits

- 최종 sustained output은 16-bit word/clock single root link에 의해 제한됨.
- Tile pending depth는 1임.
- high-load에서는 accepted traffic 증가와 함께 root queue/tail latency가 증가할 수 있음.
- Timestamp wrap-around에 대한 formal proof는 수행하지 않음.
