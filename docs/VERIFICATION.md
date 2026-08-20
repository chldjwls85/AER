# Verification

## Current freeze gate

| Test | Purpose | Expected token | Status |
|---|---|---|---|
| `tb_aer_bank_packetizer` | delta 31/32, ROW/BANK words, backpressure | `AER_BANK_PACKETIZER_TB_PASS` | PASS |
| `tb_aer_top` | 16×16 hierarchy, mixed payload, multi-bank packet lock | `AER_ADAPTIVE_PACKET_TB_PASS` | PASS |
| `tb_aer_top_128_smoke` | 128×128 elaboration and bank 0/255 connectivity | `AER_128_SMOKE_PASS` | PASS |

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\regression\run_all_xsim.ps1
```

Comprehensive random/backpressure/reset/contention/round-trip regression 결과는
두 번째 verification commit에서 이 문서와 `results/logs/regression_summary.txt`에
고정한다.

2026-08-21 Windows PowerShell에서 Vivado v2019.1 build 2552052로 위 세 test의
compile, elaboration, simulation과 PASS token을 모두 확인했다. 구조 이동 후 처음
작성한 runner는 `Tee-Object`의 UTF-16 append 때문에 콘솔 PASS token을 UTF-8
로그 검색에서 찾지 못했다. RTL 실패가 아니었으며 runner를 단일 UTF-8 append로
수정한 후 전체 suite가 `TOTAL=3, PASS=3, FAIL=0`으로 완료됐다.
