# Architecture

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

`aer_top`은 sensor 크기를 8-pixel bank 단위로 parameterize하며
`aer_top_128`은 128×128 wrapper다. 입력은 bank-major이고 local tile ID는
`row*4+column`이다.

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

각 tile은 한 개의 pending slot에 accepted ON/OFF bitmap과 16-bit timestamp를
저장한다. 한 polarity bit만 가진 transaction은 SPARSE 후보이며 주소와 full
timestamp를 2 words로 보낸다. packetizer는 row별 ROW cost와 SPARSE/ROW 혼합
cost를 합산하고, 전체 BANK cost가 그보다 엄격히 작으며 timestamp span이 31
이하일 때만 BANK를 선택한다. 동률이면 packet lock이 짧은 SPARSE/ROW를 택한다.
ROW에서는 5-bit delta에 들어가는 tile만 현재 packet에 포함한다.

한 row에서 `S`는 singleton, `N`은 non-singleton, `P=S+N`이라 할 때 비용은
다음과 같다.

- ROW-only: `P + 2`
- SPARSE/ROW hybrid: `2*S + (N+2 if N>0 else 0)`
- BANK snapshot: `total P + 3`

각 row는 앞의 두 비용 중 작은 값을 쓰며, BANK는 active row가 둘 이상이고 전체
timestamp span이 31 이하이면서 row별 최소 비용 합보다 strictly cheaper일 때만
선택한다. 동률이면 더 짧은 SPARSE/ROW packet lock을 우선한다.

DATA word가 `out_valid && out_ready`로 수용될 때만 해당 pending slot을 해제한다.
역압 동안 `out_data/out_valid/out_last`는 안정적으로 유지된다.

## Global readout

128×128 구성은 16×16 banks를 4×4 spatial regions로 나눈다. 각 region은
packet 끝(`last`)까지 한 bank를 고정하고, 선택 결과를 2-entry buffer에 넣는다.
root mux도 같은 packet-lock을 적용하므로 서로 다른 bank packet이 interleave되지
않는다. 각 arbitration point는 round-robin pointer로 다음 packet 후보를 고른다.

## Architectural limits

- 지속 처리량은 16-bit word/clock인 single global link로 제한된다.
- tile pending depth는 1이다. source가 ready를 무시하면 event를 수용하지 않는다.
- BANK delta 범위는 0..31 clocks다.
- timestamp wrap-around에 대한 oldest/min/max 판단은 별도 제한 사항이다.
- 1000x 이상 overload에서는 더 많은 event를 수용하는 대신 pending queue가
  커져 RAW보다 P99 latency가 높아질 수 있다.
