# Packet Format

모든 word는 16-bit다. ROW/BANK packet은 마지막 DATA word에서, SPARSE
packet은 TIME word에서 `out_last=1`이다.

## SPARSE packet

정확히 하나의 ON/OFF polarity bit만 set된 accepted tile transaction에 사용한다.

| Word | Bits | Width | Meaning |
|---|---|---:|---|
| ADDRESS | `[15]` | 1 | `0`: SPARSE type |
| ADDRESS | `[14:7]` | 8 | bank ID |
| ADDRESS | `[6:3]` | 4 | local tile ID, 0..15 |
| ADDRESS | `[2:1]` | 2 | pixel ID within 2x2, 0..3 |
| ADDRESS | `[0]` | 1 | polarity, `1=ON`, `0=OFF` |
| TIME | `[15:0]` | 16 | full timestamp; this word has `out_last=1` |

ROW/BANK header는 `[15]=1`이므로 packet 시작점에서 SPARSE와 충돌하지 않는다.
Decoder는 pixel ID의 one-hot bitmap을 polarity에 따라 ON 또는 OFF에 복원한다.
full timestamp를 그대로 전달하므로 delta overflow나 fallback 조건은 없다.

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
대응시킨다. 두 row 이상 active이고 모든 delta가 31 이하이며 BANK word cost가
최소 SPARSE/ROW 대안보다 strictly smaller일 때만 선택된다. 범위나 cost 조건을
만족하지 않으면 lossless SPARSE/ROW fallback하므로 delta를 잘라내지 않는다.

## Lossless definition

`valid && ready`로 accepted된 tile transaction의 local position, ON/OFF bitmap,
timestamp가 packet으로 복원되어야 한다. 입력 interface 자체는 같은 pixel의
반복 횟수가 아니라 한 capture cycle의 ON/OFF bitmap을 표현한다. 따라서 dataset
평가에서 source event와 canonical tile transaction을 별도 집계한다.

현재 candidate는 functional random 2,050건과 UZH sparse/dense/burst RTL window의
accepted transaction 전부를 decoder로 복원했으며 missing, extra, payload mismatch,
timestamp mismatch가 모두 0이다.
