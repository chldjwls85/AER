# Architecture

## Hierarchy

```text
128×128 polarity-event sensor
        |
        | 4096 × {valid, ON[3:0], OFF[3:0]}
        v
256 × aer_bank_packetizer
        | 4×4 tiles per bank / 8×8 pixels
        | ROW or BANK packet stream
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
| `aer_bank_packetizer` | 16 tile pending slots, ROW/BANK selection and serialization |
| `aer_packet_rr_arbiter` | packet-locked look-ahead round-robin grant |
| `aer_packet_mux` | selected stream ready/valid/last routing |
| `aer_stream_buffer2` | two-entry elastic word buffer |
| `aer_global_readout` | 4×4-bank regional muxes and root mux |
| `aer_top`, `aer_top_128` | bank generation and public interface |

## Bank behavior

각 tile은 한 개의 pending slot에 accepted ON/OFF bitmap과 16-bit timestamp를
저장한다. pending snapshot의 active row가 둘 이상이고 unsigned
`max_timestamp-min_timestamp <= 31`이면 BANK packet을 만든다. 그렇지 않으면
가장 먼저 active인 row를 ROW packet으로 보낸다. ROW에서도 5-bit delta에
들어가는 tile만 현재 packet에 포함하고 나머지는 다음 packet으로 보낸다.

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
