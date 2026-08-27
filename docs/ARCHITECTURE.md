# Architecture

> 문서 범위: V3 `aer_top_128`과 `aer_bank_packetizer` 기준 Architecture임.
> V4 차이점은 `AER_V3_V4_DESIGN_EVOLUTION.md` 참조 필요함.

## Hierarchy

```text
128×128 polarity-event sensor
        |
        | 4096 × {valid, ON[3:0], OFF[3:0]}
        v
256 × aer_bank_packetizer
        | 4×4 tiles per bank / 8×8 pixels
        | SPARSE, ROW or BANK packet stream
        v
16 × regional aer_packet_mux
        |
16 × aer_stream_buffer2
        |
        v
root aer_packet_mux
        |
        v
16-bit out_data / out_valid / out_ready / out_last
```

- `aer_top`: sensor 크기를 8-pixel bank 단위로 parameterize함
- `aer_top_128`: 128×128 고정 wrapper임
- 입력 배열 순서: bank-major임
- Local tile ID 계산: `row*4+column`임

## Modules

| Module | Role |
|---|---|
| `aer_timebase` | 16-bit free-running capture timestamp |
| `aer_bank_packetizer` | 16 tile pending slots, SPARSE/ROW/BANK selection and serialization |
| `aer_packet_rr_arbiter` | packet-locked look-ahead round-robin grant |
| `aer_packet_mux` | selected stream ready/valid/last routing |
| `aer_stream_buffer2` | two-entry elastic word buffer |
| `aer_global_readout` | 4×4-bank regional muxes and root mux |
| `aer_top`, `aer_top_128` | bank generation and public interface |

## Bank behavior

- Pending storage: tile마다 accepted ON/OFF bitmap과 16-bit timestamp를 1개씩 저장함
- SPARSE 후보: ON/OFF 전체에서 polarity bit 1개만 set된 transaction임
- SPARSE 전송: address와 full timestamp를 2 words로 전송함
- ROW 포함 조건: base timestamp 대비 5-bit delta 범위에 들어오는 tile만 포함함
- BANK 선택 조건: 전체 timestamp span이 31 이하이고 BANK cost가 대안보다 strictly smaller여야 함
- Tie-break: 동일 cost이면 packet lock이 짧은 SPARSE/ROW를 우선함

한 row에서 사용하는 기호와 비용은 다음과 같음.

- `S`: singleton tile 수임
- `N`: non-singleton tile 수임
- `P=S+N`: active tile 수임

- ROW-only: `P + 2`
- SPARSE/ROW hybrid: `2*S + (N+2 if N>0 else 0)`
- BANK snapshot: `total P + 3`

- Row별 기준 cost: `ROW-only`와 `SPARSE/ROW hybrid` 중 작은 값 사용함
- BANK 사용 조건: active row 2개 이상, timestamp span 31 이하, row별 최소 cost 합보다 저렴해야 함
- Pending clear: DATA word가 `out_valid && out_ready`로 handshake될 때만 수행함
- Backpressure: `out_data/out_valid/out_last`를 handshake 전까지 안정적으로 유지함

## Global readout

- Region 구성: 16×16 banks를 4×4 spatial regions로 분할함
- Regional mux: packet 끝(`last`)까지 선택 bank를 고정함
- Buffer: regional mux 출력을 2-entry elastic buffer에 저장함
- Root mux: 동일한 packet lock을 적용해 bank packet 간 interleave를 방지함
- Arbitration: 각 arbitration point에서 round-robin pointer로 다음 packet을 선택함

## Architectural limits

- 지속 처리량: 16-bit word/clock인 single global link로 제한됨
- Tile pending depth: 1임. Source가 `ready`를 무시하면 해당 event를 수용하지 못함
- BANK delta 범위: 0..31 clocks임
- Timestamp wrap-around: oldest/min/max 판단에 대한 별도 검증 필요함
- 1000× 이상 overload: accepted event 증가와 함께 queue가 길어져 RAW보다 P99 latency가 높아질 수 있음
