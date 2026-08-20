# Packet Format

모든 word는 16-bit이며 packet의 마지막 DATA word에서만 `out_last=1`이다.

## ROW packet

| Word | Bits | Width | Meaning |
|---|---|---:|---|
| HEADER | `[15:14]` | 2 | `11`: ROW type |
| HEADER | `[13:6]` | 8 | bank ID |
| HEADER | `[5:4]` | 2 | local tile row |
| HEADER | `[3:0]` | 4 | active column mask |
| TIME | `[15:0]` | 16 | base timestamp |
| DATA | `[15:11]` | 5 | unsigned delta from base, 0..31 |
| DATA | `[10:7]` | 4 | exact ON bitmap |
| DATA | `[6:3]` | 4 | exact OFF bitmap |
| DATA | `[2:0]` | 3 | reserved, zero |

Decoder는 column mask의 set bit를 낮은 column부터 DATA word에 대응시킨다.
같은 row에 delta 31을 넘는 tile이 있으면 그 tile은 다음 ROW packet에 남는다.

## BANK packet

| Word | Bits | Width | Meaning |
|---|---|---:|---|
| HEADER | `[15:14]` | 2 | `10`: BANK type |
| HEADER | `[13:6]` | 8 | bank ID |
| HEADER | `[5:1]` | 5 | active tile count, 1..16 |
| HEADER | `[0]` | 1 | reserved, zero |
| MASK | `[15:0]` | 16 | active local tile mask |
| TIME | `[15:0]` | 16 | minimum timestamp in snapshot |
| DATA | `[15:11]` | 5 | unsigned delta from base, 0..31 |
| DATA | `[10:7]` | 4 | exact ON bitmap |
| DATA | `[6:3]` | 4 | exact OFF bitmap |
| DATA | `[2:0]` | 3 | reserved, zero |

Decoder는 tile mask의 set bit를 local tile ID 0부터 오름차순으로 DATA word에
대응시킨다. 두 row 이상 active이고 모든 delta가 31 이하일 때만 선택된다.
범위를 넘으면 ROW fallback하므로 delta overflow를 잘라내지 않는다.

## Lossless definition

`valid && ready`로 accepted된 tile transaction의 local position, ON/OFF bitmap,
timestamp가 packet으로 복원되어야 한다. 입력 interface 자체는 같은 pixel의
반복 횟수가 아니라 한 capture cycle의 ON/OFF bitmap을 표현한다. 따라서 dataset
평가에서 source event와 canonical tile transaction을 별도 집계한다.
