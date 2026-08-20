# 센서 전역 이벤트 읽기 애니메이션

- `aer_global_readout_step_by_step.webp`: 1200×675, 12단계 애니메이션
- `aer_global_readout_contact_sheet.png`: 전체 단계 한눈에 보기
- `frames/`: 단계별 1200×675 PNG 원본

## 프레임 순서

1. `01_overview.png`: 128×128 센서의 타일·뱅크 계층
2. `02_bank_valid.png`: 이벤트가 있는 뱅크의 `bank_valid` 생성
3. `03_pointer_start.png`: 행 우선 탐색 포인터 시작
4. `04_skip_empty.png`: 빈 뱅크를 건너뛰고 bank 2 선택
5. `05_lock_bank.png`: 패킷 전송 중 선택 뱅크 잠금
6. `06_send_header.png`: 뱅크·행·열 비트맵 헤더 전송
7. `07_send_time.png`: 행 기준 타임스탬프 전송
8. `08_send_data_1.png`: 첫 번째 유효 열의 타일 데이터 전송
9. `09_send_last.png`: 마지막 타일 데이터와 `LAST` 전송
10. `10_next_bank.png`: 다음 포인터에서 bank 7 선택
11. `11_next_row.png`: 행 끝을 지나 다음 행의 bank 20 선택
12. `12_repeat.png`: 마지막 뱅크 뒤 bank 0으로 돌아가는 순환

주황색 탐색 경로는 우선순위 순서를 설명한다. 실제 RTL은 빈 뱅크마다 한 클록씩 검사하지 않고 `bank_valid` 우선순위 논리로 다음 유효 뱅크를 찾는다.

다시 생성하려면 저장소 루트에서 다음을 실행한다.

```powershell
pwsh -NoProfile -File scripts/generate_aer_global_readout_animation.ps1
```
