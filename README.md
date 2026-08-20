# AER 이벤트 통신 회로 설계

이 저장소는 2026년 AI 반도체 회로설계 경진대회의 AER(Address-Event Representation) 연구 자료와 Verilog RTL 구현을 관리합니다.

현재 1차 설계 목표는 다음과 같습니다.

> 제한된 AER 링크에서 비동기적으로 발생하는 polarity 이벤트의 전송 효율과 처리량을 높이는 타일 기반 이벤트 인코딩 및 중재 회로 설계

## 현재 연구 방향

- `n × m` 이벤트 픽셀 배열에서 발생하는 희소·집중·폭주 트래픽 처리
- 픽셀 → 타일 → 뱅크 계층 구조와 공유 링크의 병목 분석
- 혼잡도에 따라 2×2 또는 4×4 단위로 묶는 적응형 픽셀 비닝 검토
- 시계열 정보와 비닝 이력을 이용한 소프트웨어 복원 확장 검토
- 처리량, 지연시간, 이벤트 손실률, 면적, 전력, 배선 비용 비교

## 초기 RTL

첫 기준 구현은 16×16 픽셀 배열을 16개의 4×4 타일과 4개의 뱅크로 나누고, 계층형 순환 중재를 거쳐 32비트 RAW 패킷을 출력합니다.

- [초기 RTL 구조와 인터페이스](docs/초기_RTL_구조.md)
- `rtl/`: 합성 가능한 Verilog-2001 소스
- `tb/`: 자동 검사 시험 환경
- `scripts/run_iverilog.ps1`: Icarus Verilog 실행 스크립트
- `scripts/check_yosys.sh`: Yosys 계층·합성 가능성 검사

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_iverilog.ps1
```

Linux 또는 WSL에서 Yosys가 설치되어 있다면 다음 검사도 실행할 수 있습니다.

```sh
sh scripts/check_yosys.sh
```

초기 `rtl/aer_top.v` 계열은 RAW 계층 통신의 비교 기준선입니다. 아래 v1은 별도 경로에서 2×2 비트맵 인코딩과 행 우선 뱅크 통신을 시험합니다. 4×4 비닝, 적응형 혼잡 제어 및 메시 통신망은 후속 단계입니다.

## 크기 가변형 균형 계층 RTL v1

2×2 타일의 ON/OFF 비트맵을 받아 4×4타일 뱅크에서 행 패킷으로 만듭니다. 센서 행·열 크기에 따라 뱅크 배열과 공간 selector 단계 수를 자동으로 계산하며, 각 selector의 fan-in은 기본 4×4 하위 블록으로 제한합니다. 선택된 패킷은 마지막 워드까지 유지하고, 각 단계의 2-entry FIFO와 look-ahead grant로 연속 전송을 지원합니다. 한 행의 BIN4 토큰은 두 개씩 16비트 워드에 패킹합니다.

- [v1 구조와 패킷 규약](docs/AER_v1_RTL_구조.md)
- [적응형 대 무비닝 RAW8 공정 비교 규약](docs/AER_v1_공정비교_규약.md)
- `rtl/v1/`: Verilog-2001 RTL
- `tb/v1/`: 타일 부호기, BIN 패킹, 균형 selector, 크기 가변 및 128×128 시험

적응형 `aer_v1_top_128`과 무비닝 `aer_v1_raw_top_128`은 같은 core를 공유하며 `ENABLE_BINNING`만 다릅니다. 따라서 이후 계층이나 패킷 구조를 수정해도 두 비교군이 함께 갱신됩니다.

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_v1_xsim.ps1
```

Xcelium 환경에서는 다음을 실행합니다.

```sh
sh scripts/run_v1_xcelium.sh
```

128×128 전체 시험의 전역 뱅크 선택·패킷 출력 파형을 Vivado XSim GUI에서 열려면 다음을 실행합니다.

```powershell
powershell -ExecutionPolicy Bypass -File scripts/open_v1_xsim_wave.ps1
```

## 사전 소프트웨어 검증

MASK·BIN·CARE-AER RTL을 작성하기 전에 전송 정책을 비교할 수 있는 Python 기준 모델을 제공합니다.

- [소프트웨어 검증 사용법](sw/README.md)
- `sw/`: 합성 트래픽, UZH 이벤트 로더, 정책·링크 모델, 패킷 pack/unpack
- `tests_sw/`: 자동 단위 시험
- `scripts/run_sw_validation.ps1`: 시험과 네 합성 시나리오 일괄 실행

~~~powershell
powershell -ExecutionPolicy Bypass -File scripts/run_sw_validation.ps1
~~~

이 결과는 구조 탐색용이며 RTL의 클록 정확 성능이나 PPA 결과를 대신하지 않습니다.

## 주요 문서

- [설계 제안서](AER_설계_제안서.md)
- [설계 제안서 상세 부록](docs/AER_설계_부록.md)
- [현재 구현의 기준 문서](docs/초기_RTL_구조.md)
- [CARE-AER 소프트웨어 초기 검증 결과](docs/SW_초기_검증_결과.md)
- [대회 오리엔테이션 정리](260723_오리엔테이션.md)
- [1차 Q&A 정리](1차_Q&A_정리.md)
- `Background/`: AER 관련 논문과 조사 자료

## 저장소에 포함하지 않는 로컬 자료

- 참가팀 서버 접속 정보
- 재배포가 제한된 대용량 Cadence 강의 자료
- PDF 변환 및 검토 과정에서 만들어진 임시 파일
- 시뮬레이션·합성·배치배선 도구의 재생성 가능한 산출물

향후 RTL 구현은 작은 배열과 기본 중재기부터 검증한 뒤, 배열 크기와 계층 구조를 단계적으로 확장합니다.
