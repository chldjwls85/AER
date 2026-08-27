# Packet Format

> 문서 범위: V3 SPARSE/ROW/BANK packet format 기준임.
> V4는 SPARSE/ROW format을 재사용하고 BANK mode를 제거함.

- 모든 output word width: 16-bit임
- ROW/BANK 종료: 마지막 DATA word에서 `out_last=1`임
- SPARSE 종료: TIME word에서 `out_last=1`임

## SPARSE packet

- 사용 조건: ON/OFF 전체에서 polarity bit가 정확히 1개 set된 accepted tile transaction임

| Word | Bits | Width | Meaning |
|---|---|---:|---|
| ADDRESS | `[15]` | 1 | `0`: SPARSE type |
| ADDRESS | `[14:7]` | 8 | bank ID |
| ADDRESS | `[6:3]` | 4 | local tile ID, 0..15 |
| ADDRESS | `[2:1]` | 2 | pixel ID within 2x2, 0..3 |
| ADDRESS | `[0]` | 1 | polarity, `1=ON`, `0=OFF` |
| TIME | `[15:0]` | 16 | full timestamp; this word has `out_last=1` |

- Type 구분: ROW/BANK header는 `[15]=1`, SPARSE ADDRESS는 `[15]=0`이므로 충돌하지 않음
- Decoder 동작: pixel ID를 one-hot bitmap으로 바꾸고 polarity에 따라 ON 또는 OFF에 복원함
- Timestamp: full 16-bit 값을 직접 전달하므로 delta overflow가 없음

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

- DATA 대응 순서: column mask의 set bit를 낮은 column부터 DATA word에 대응함
- Delta 초과 처리: delta가 31을 넘는 tile은 현재 packet에서 제외하고 다음 ROW packet에 남김

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

- DATA 대응 순서: tile mask의 set bit를 local tile ID 0부터 오름차순으로 대응함
- BANK 선택 조건: active row 2개 이상, 모든 delta 31 이하, 대안보다 strictly smaller한 cost임
- Fallback: 범위/cost 조건 미충족 시 lossless SPARSE/ROW를 사용함
- 금지 사항: delta 값을 잘라내지 않음

## Lossless definition

- Lossless 기준: `valid && ready`로 accepted된 local position/ON/OFF/timestamp가 동일하게 복원돼야 함
- 입력 의미: 같은 pixel의 반복 횟수가 아니라 한 capture cycle의 ON/OFF bitmap을 표현함
- Dataset 집계: source event와 canonical tile transaction을 별도 집계함
- 검증 범위: random 2,050건과 UZH sparse/dense/burst accepted transaction 전체임
- 검증 결과: missing/extra/payload/timestamp mismatch 모두 0임
