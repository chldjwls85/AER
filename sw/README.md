# CARE-AER 사전 소프트웨어 검증

이 폴더는 MASK·BIN·적응형 선택 RTL을 작성하기 전에 전송 정책을 비교하는 순수 Python 기준 모델이다. 외부 패키지 없이 Python 3.10 이상에서 실행된다.

## 1. 검증 경계

입력은 이미 센서 픽셀에서 생성된 polarity 이벤트다.

~~~text
(timestamp, x, y, polarity)
→ RTL 클록으로 양자화
→ 4×4픽셀 타일과 시간 구간으로 분류
→ RAW / 고정 MASK / 고정 BIN / CARE-AER 부호화
→ 타일 FIFO
→ 순환 중재 방식의 단일 32비트 출력
→ 처리량·지연·손실·전송 비트·위치 보존률 계산
~~~

이 모델은 구조 탐색용이며 현재 Verilog의 클록 단위 복제품은 아니다.

- 모델링함: 4×4 타일, 타일별 FIFO 단어 용량, 한 번에 한 타일을 고르는 순환 중재, 1클록당 32비트 한 단어, 1·2단어 토큰의 연속 전송
- 모델링하지 않음: 2단 입력 동기화 지연, 픽셀별 ACK 상태 기계, 뱅크·전역 탄력 레지스터의 정확한 지연, 실제 표준셀 PPA
- 실제 데이터셋은 이미 직렬화된 이벤트이므로 픽셀 요청·ACK의 최악 조건은 합성 트래픽으로 따로 검증함

소프트웨어 결과는 RTL의 성능 증거가 아니다. 선택 기준과 패킷 비용이 합리적인지 확인하고 RTL 시험 벡터를 만들기 위한 선행 결과다.

## 2. 파일

| 파일 | 역할 |
|---|---|
| `aer_types.py` | 이벤트와 부호화 토큰 자료형 |
| `event_to_cycle.py` | 비동기 시각을 RTL 클록으로 변환 |
| `load_uzh_events.py` | UZH `events.txt` 로더와 영역 자르기 |
| `synthetic_traffic.py` | 균일 Poisson·집중·폭주·이동 윤곽 생성 |
| `care_aer_model.py` | 네 정책과 타일 FIFO·출력 링크 모의실험 |
| `analyze_features.py` | 실제 타일 밀도·극성·변화량 분포와 요약 가능 비율 분석 |
| `prepare_event_visual.py` | 가장 붐비는 구간을 찾아 원본·비닝 비교용 희소 JSON 생성 |
| `packet_decoder.py` | 현재 RAW v0와 제안 패킷의 비트 pack/unpack |
| `evaluate.py` | 정책 비교 표와 JSON 결과 생성 |
| `download_uzh.py` | 공식 회전 시퀀스 주소 확인·선택 다운로드 |

## 3. 빠른 실행

저장소 루트에서 실행한다.

~~~powershell
python -m unittest discover -s tests_sw -v

python -m sw.evaluate `
  --synthetic all `
  --cycles 2000 `
  --rate 0.5 `
  --window-cycles 8 `
  --fifo-words 8 `
  --json results/synthetic.json
~~~

또는 한 번에 실행한다.

~~~powershell
powershell -ExecutionPolicy Bypass -File scripts/run_sw_validation.ps1
~~~

`--rate`는 합성 트래픽의 클록당 평균 입력 이벤트 수다. 현재 출력은 클록당 32비트 한 단어이므로 값을 올리면 포화와 손실을 확인할 수 있다.

## 4. 정책

| 정책 | 모델 동작 |
|---|---|
| `raw` | 이벤트마다 32비트 한 단어 |
| `mask` | 기본적으로 활성 2×2 영역마다 32비트 한 단어 |
| `bin` | 기본적으로 활성 2×2 영역마다 개수 요약 한 단어 |
| `care` | FIFO 혼잡, 극성 우세, 직전 위치와의 차이, 마지막 정확 정보 나이로 선택 |

고정 방식의 영역 크기는 `--fixed-group-size 2` 또는 `4`로 바꾼다. 4×4 MASK는 문서 사양대로 두 단어, 4×4 BIN은 한 단어로 계산한다.

현재 CARE-AER 기준은 의도적으로 단순하다.

1. 처음 관측한 타일과 정확 정보 나이 기준을 넘은 타일은 위치를 보존한다.
2. FIFO가 여유로우면 단어 수가 가장 적은 정확 형식을 사용한다.
3. 혼잡하고, 직전 패턴과 비슷하며, 한 극성이 우세할 때만 개수 요약을 허용한다.
4. 4×4 활성 밀도가 높으면 4×4, 그렇지 않으면 활성 2×2별 요약을 후보로 사용한다.
5. 요약 단어 수가 정확 형식보다 적지 않으면 정확 형식을 유지한다.

기준값은 최종 회로 사양이 아니다. 여러 입력에서 결과를 비교해 변경하고, 변경 이유와 결과를 함께 기록한다.

## 5. 출력 지표

| 출력 | 의미 |
|---|---|
| `accepted` | FIFO에 들어가 최종 링크에서 전송된 입력 이벤트 수 |
| `loss%` | FIFO 공간 부족으로 토큰에 담기지 못한 비의도 손실 |
| `bit/input` | 실제 전송 비트 수 ÷ 전체 입력 이벤트 수 |
| `bit/accepted` | 실제 전송 비트 수 ÷ 수용된 이벤트 수 |
| `mean_lat` | 이벤트 발생부터 해당 토큰의 마지막 단어 전송까지 평균 클록 |
| `p99_lat` | 같은 지연의 99백분위 |
| `event/cycle` | 유한 기록에서 수용한 이벤트 수 ÷ 전체 처리 클록 |
| `position%` | 정확한 픽셀 위치를 담은 수용 이벤트 수 ÷ 전체 입력 수 |
| `fifo_max` | 관측한 타일 FIFO 최대 점유 단어 수 |

손실이 큰 구조는 `bit/input`이 인위적으로 작아 보일 수 있으므로 반드시 `loss%`와 `bit/accepted`를 함께 본다. MASK와 BIN이 같은 픽셀·극성의 반복 발생을 하나로 합친 수는 `merged`로 별도 출력한다.

## 6. UZH 실제 데이터 사용

권장 시작 자료는 UZH Event-Camera Dataset의 `shapes_rotation`, `poster_rotation`, `boxes_rotation`이다.

- 공식 페이지: <https://rpg.ifi.uzh.ch/davis_data.html>
- 텍스트 형식: `timestamp x y polarity`
- 함께 제공되는 정보: 영상, IMU, 카메라 보정값, 자세 정답

다운로드 크기와 주소만 확인하는 명령은 파일을 저장하지 않는다.

~~~powershell
python -m sw.download_uzh shapes_rotation
~~~

실제로 약 150 MiB의 ZIP을 받고 풀려면 명시적으로 옵션을 추가한다.

~~~powershell
python -m sw.download_uzh shapes_rotation --download --extract
~~~

`poster_rotation`과 `boxes_rotation`은 각각 약 795 MiB와 852 MiB이므로 필요한 경우에만 받는다. 다운로드한 `data/`는 Git에서 제외된다.

압축 해제 뒤 정확한 `events.txt` 위치를 찾는다.

~~~powershell
Get-ChildItem -Path data/uzh -Filter events.txt -Recurse
~~~

128×128 적응형 패킷 초안과 같은 좌표 폭으로 비교하려면 DAVIS240C 중앙을 잘라 사용한다.

원본과 2×2·4×4 비닝 결과를 그릴 자료는 다음처럼 만든다. 출력은 활성 픽셀만 담은 JSON이다.

~~~powershell
python -m sw.prepare_event_visual `
  data/uzh/shapes_rotation/events.txt `
  --crop 56 26 128 128 `
  --duration-ms 20 `
  --max-events 200000
~~~

~~~powershell
python -m sw.evaluate `
  --uzh data/uzh/shapes_rotation/events.txt `
  --crop 56 26 128 128 `
  --clock-hz 100000000 `
  --playback-speed 1 `
  --max-events 200000 `
  --json results/shapes_rotation.json
~~~

실제 기록이 링크를 포화시키지 않으면 `--playback-speed 10`, `100`처럼 재생 속도를 올려 같은 공간 패턴을 더 짧은 클록에 넣는다. 이는 실제 카메라 속도를 측정한 결과가 아니라 입력률 민감도 실험임을 보고서에 명시한다.

전송 정책을 바꾸기 전에 실제 특성 분포를 확인한다.

~~~powershell
python -m sw.analyze_features `
  --uzh data/uzh/shapes_rotation/events.txt `
  --crop 56 26 128 128 `
  --clock-hz 100000000 `
  --playback-speed 1000 `
  --max-events 200000 `
  --window-cycles 8 16 32 64 `
  --json results/shapes_rotation_features.json
~~~

전체 240×180 좌표도 추상 전송 비용 모델에는 넣을 수 있지만, 현재 128×128 제안 패킷의 7비트 좌표 필드와 비트 단위로 일치하지 않는다. 비트 정확 검증은 128×128 자르기 또는 새로운 좌표 폭 사양 확정 뒤 수행한다.

## 7. 교수님 데이터가 제공되면

교수님 자료를 다음 두 파일로 변환한다.

~~~text
events.txt
timestamp x y polarity

groundtruth.txt
timestamp px py pz qx qy qz qw
~~~

1차 통신 검증에는 `events.txt`만 사용한다. 2차 구면 월드 메모리 검증에는 카메라 보정값과 회전 자세를 시각 보간해 함께 사용한다. 교수님 데이터가 동영상 형태뿐이라면 원본 이벤트 파일이나 프레임별 정확한 시각이 함께 제공되는지 먼저 확인해야 한다.

## 8. 다음 RTL 연결

소프트웨어에서 기준값을 고른 뒤 다음 순서로 RTL에 옮긴다.

1. `packet_decoder.py`와 동일한 pack/unpack 시험 벡터 생성
2. 2×2 MASK 생성기 구현 및 비트 단위 비교
3. 4×4 MASK와 BIN 구현
4. CARE-AER 선택기의 입력 특성과 선택 결과 비교
5. Python과 RTL에 같은 이벤트 기록을 넣고 패킷 흐름 대조
6. RTL 지연·손실·PPA는 실제 시험 환경과 합성 보고서로 다시 측정
