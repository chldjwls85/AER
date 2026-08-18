# 1차 Q&A 정리

> 원본: `1차 Q&A 정리.pdf` (18쪽)  
> 용도: 검색과 재참조를 위한 Markdown 정리본  
> 편집 원칙: PDF의 내용과 확정 수준을 유지하고, 페이지 단위 줄바꿈과 중복 머리말만 정리했다. 확정되지 않은 내용을 임의로 확정하지 않았다.

## 목차

- [핵심 요약](#핵심-요약)
- [조건의 확정 수준](#조건의-확정-수준)
  - [확정된 방향](#확정된-방향)
  - [예시 또는 권고 사항](#예시-또는-권고-사항)
  - [팀이 정의해야 하는 사항](#팀이-정의해야-하는-사항)
- [팀별 질문과 답변](#팀별-질문과-답변)
  - [REDRED · 박준영](#redred--박준영)
  - [Boomhill · 윤지웅](#boomhill--윤지웅)
  - [회로의 민족 · 임채균](#회로의-민족--임채균)
  - [전전긍긍 · 곽호준](#전전긍긍--곽호준)
  - [도통 모르겠네 · 이상엽](#도통-모르겠네--이상엽)
  - [제이엔유 · 박준수](#제이엔유--박준수)
  - [SKK하이닉스 · 조민석](#skk하이닉스--조민석)
  - [MAC가이버 · 지영빈](#mac가이버--지영빈)
  - [찌릿찌릿 · 이윤재](#찌릿찌릿--이윤재)
- [1차 과제 추가 설명](#1차-과제-추가-설명)
- [교수님 추가 설명](#교수님-추가-설명)
- [제출 및 운영 안내](#제출-및-운영-안내)

---

## 핵심 요약

- 설계 구조와 인터페이스는 전반적으로 자유롭게 정할 수 있다. 다만 왜 그 방식을 선택했는지와 기존 방식보다 무엇이 좋아졌는지를 반드시 설명해야 한다.
- 아이디어의 참신성뿐 아니라 실제 동작 가능성과 PPA(Performance, Power, Area)를 함께 입증해야 한다.
- 특정한 단일 평가 조건이나 점수 가중치에 맞추기보다 해결할 문제와 사용 시나리오를 먼저 정의하고, 동일 기능의 baseline과 정량 비교해야 한다.
- 공정은 아날로그와 디지털 모두 45 nm 교육용 PDK 범위에서 진행한다.
- 센서 이벤트 발생은 비동기적이지만 처리 회로는 클록 기반 동기식으로 설계해도 된다. 비동기식을 선택할 경우에도 그 이점을 입증해야 한다.
- 이번 과제의 기본 처리 정보는 intensity를 제외한 polarity event이다.
- 이벤트를 일부 손실하는 구조도 허용된다. 다만 입력 이벤트 수, 출력 이벤트 수, 손실률과 PPA 사이의 trade-off를 정량적으로 제시해야 한다.
- Bus width, packet 형식, timestamp, arbitration, handshake, 입력 interface 등은 팀이 정할 수 있으며 선택 근거와 장단점을 설명해야 한다.
- 1차 과제에서 설계한 효율적인 AER 통신·표현 구조는 2차 과제의 sensor coordinate → world coordinate 변환 및 world memory mapping으로 이어져야 한다.
- 교수님이 제공할 실제 이벤트 영상과 회전·촬영 상황 정보를 참고할 수 있다. 공식 단일 traffic pattern이나 고정된 평가 가중치는 제공되지 않는다.

## 조건의 확정 수준

### 확정된 방향

| 항목 | 내용 |
|---|---|
| 공정 | 45 nm 교육용 PDK 범위 |
| 기본 이벤트 | Polarity event |
| 제외 범위 | Intensity 복원은 요구하지 않음 |
| World memory | On-chip SRAM |
| 센서 회전 | Yaw, pitch, roll 모두 포함 |
| 초기 관측 환경 | Static 3D 환경으로 단순화 |
| 1차 결과물 | PPT 형식 |

### 예시 또는 권고 사항

- 센서 해상도는 128×128 또는 256×256에서 시작하고, 확장 목표로 약 1000×1000을 고려할 수 있다.
- FOV는 인간의 시야를 참고해 약 70-80도를 하나의 기준으로 사용할 수 있다.
- 외부 출력 대역폭은 일반적인 컴퓨터 연결을 가정할 때 10-20 Gbps, 전용 processor interface를 가정하면 약 40 Gbps까지 예시로 언급됐다. 의무 target은 아니다.
- 포토커런트는 매우 낮은 영역부터 최대 약 1 μA까지 폭넓게 시뮬레이션해 볼 것을 권고한다.
- PVT variation과 Monte Carlo는 수행 가능한 범위까지 검증해 볼 것을 권고한다.

### 팀이 정의해야 하는 사항

- 목표 clock, 세부 PVT corner, I/O delay와 load, switching activity 조건
- Bus width, packet format, timestamp, handshake, input interface
- Event traffic의 sparse·dense·burst 조건과 성능 지표
- Event를 보존할 범위와 허용 손실률
- FOV, sensor·world resolution, memory cell 표현 방식과 bit width

> **FOV와 yaw·pitch·roll의 차이**  
> FOV는 센서가 한 번에 보는 수평·수직 각도이고, yaw·pitch·roll은 센서 자체의 회전축이다.

---

## 팀별 질문과 답변

### REDRED · 박준영

#### Q1. PPA 평가는 Genus 합성 결과만으로 가능한가? Innovus P&R과 post-route timing 결과가 필수이거나 가산점 대상인가?

- 초반 직접 답변이 녹화에 완전하게 남아 있지 않아 Genus만으로 충분한지, Innovus 결과가 필수 또는 가산점인지 확정할 수 없다.
- 후속 발언에서 확인되는 평가 원칙은 단순 아이디어가 아니라 실제로 구현 가능한 회로인지와 전체 시스템의 현실성을 평가한다는 것이다.
- Genus synthesis 결과는 기본적인 PPA 근거로 사용할 수 있다.
- Innovus P&R, post-route timing, RC parasitic 반영 결과까지 제시하면 실제 구현 가능성을 더 강하게 입증할 수 있다.
- 다만 Q&A만으로 Innovus 결과가 절대적인 필수 제출물이라고 단정하면 안 된다.
- 결과를 제시할 때 synthesis, pre-layout, post-route 중 어느 단계의 수치인지 명확히 표시해야 한다.

#### Q2. 공정·library, PVT corner, 목표 clock, I/O delay와 load 등의 물리 조건이 공통 지정되는가?

- 아날로그와 디지털 모두 45 nm 교육용 PDK 범위에서 진행한다.
- 세부 PVT corner, 목표 clock, I/O delay·load까지 하나의 공통 조건으로 고정한다는 답변은 확인되지 않았다.
- 팀이 합리적인 조건을 설정하고 해당 조건을 선택한 이유와 현실성을 제출 자료에 명시해야 한다.
- 다른 구조와 PPA를 비교할 때는 동일한 공정·clock·load·activity 조건을 적용해 공정한 비교가 되도록 해야 한다.

#### Q3. 전력 평가는 vectorless 추정으로 충분한가? VCD·SAIF 기반 activity power가 요구되는가?

- Vectorless와 VCD·SAIF 중 하나를 의무 방식으로 지정했다는 직접 답변은 확인되지 않았다.
- Switching activity의 공통 기준도 별도로 고정되지 않았으며 각 팀이 현실적인 동작 조건을 정의해야 한다.
- Vectorless 결과를 사용할 경우 toggle rate와 입력 activity 가정을 명확히 기재해야 한다.
- 가능하면 실제 traffic simulation에서 얻은 VCD·SAIF 기반 power도 함께 제시하는 것이 설계의 현실성을 입증하는 데 유리하다.
- VCD·SAIF 기반 분석은 권장 가능한 보강 근거이며 필수 조건으로 확정된 것은 아니다.

#### Q4. 평가 범위는 핵심 처리 회로만인가? Encoder·decoder·serializer·buffer·clock 등 전체 입출력 경로까지 포함하는가?

- 문제의 최종 범위는 시스템 전체이다.
- Encoder·decoder 등의 성능이 낮으면 실제 사용 시 전체 시스템 성능도 낮아지므로 end-to-end 관점에서 본다.
- 시간이 제한적이므로 처음부터 모든 블록의 완성도를 동시에 높이기보다 가장 핵심적인 문제를 정확히 정의하고 핵심 회로를 먼저 구현한 뒤 나머지 블록을 단계적으로 확장하는 접근을 권장한다.
- 평가는 핵심 문제 정의와 핵심 기능의 타당한 동작을 먼저 확인한 후 전체 시스템으로의 확장 수준을 살펴보는 방향이다.

#### Q5. Event loss는 correctness 실패인가? 손실률과 PPA의 trade-off가 인정되는가?

- Event loss가 발생한다고 해서 자동으로 correctness 실패가 되는 것은 아니다.
- 처리 용량보다 많은 이벤트가 발생하면 일부 손실이 생길 수 있으며, 이를 성능 특성으로 정량화해야 한다.
- 입력 이벤트 총량, 실제 출력 이벤트 총량, loss rate, throughput, latency를 함께 보고해야 한다.
- 높은 손실률은 시스템 성능 저하로 이어지므로 어떤 조건에서 어느 정도의 손실을 허용했는지와 그 대신 얻은 area·power·speed 이점을 설명해야 한다.
- 이벤트를 최대한 보존할지 일부를 버릴지는 팀이 선택할 수 있지만 선택한 전략과 trade-off를 명확히 제시해야 한다.

#### Q6. 공식 traffic pattern과 throughput·latency·loss·area·power의 평가 우선순위가 제공되는가?

- Uniform, hotspot, burst, simultaneous input 등을 포함한 하나의 공식 traffic pattern과 고정된 평가 가중치는 제공되지 않는다.
- 팀이 목표 application과 출력 bandwidth를 가정해 sparse부터 dense·burst까지 여러 시나리오를 정의하고 처리 한계를 확인해야 한다.
- 교수님은 과거 연구에서 큰 pixel array에 Poisson arrival 형태로 이벤트를 임의 발생시키고 낮은 발생률부터 높은 발생률까지 처리 가능 범위를 확인한 사례를 언급했다.
- 교수님이 실제 센서로 촬영한 이벤트 영상과 촬영·회전 상황 정보를 별도로 제공할 예정이며, 현실적인 test stimulus의 참고 자료로 사용할 수 있다.

#### Q7. DDR, multi-edge clocking, clock gating, vendor-specific primitive를 사용할 수 있는가?

- 모든 설계는 45 nm 교육용 PDK에서 구현 가능한 범위 안에서 진행해야 한다.
- Clock gating이나 clock 구조는 PDK와 제공 환경에서 구현 가능하고 이점을 검증할 수 있다면 설계 선택지로 고려할 수 있다.
- 교육용 PDK에 존재하지 않는 DDR IP나 특정 vendor 전용 primitive·hard IP는 사실상 사용할 수 없다.
- 특정 primitive를 사용했다면 portability, timing, area, power에 미친 영향과 사용 가능 근거를 명시해야 한다.

### Boomhill · 윤지웅

#### Q1. Photodiode를 광전류 step, junction capacitance, dark current를 포함한 Verilog-A 모델로 구현해도 되는가? 추가 파라미터가 필요한가?

- 제안한 Verilog-A 모델링 방식으로 진행해도 된다.
- Photocurrent source, junction capacitance, dark current를 포함해 transient response를 볼 수 있도록 구성하는 방향이 적절하다.
- 예시로 제시한 100 pA보다 더 낮은 영역도 확인할 필요가 있다. 적어도 1 pA 수준까지 낮추고 필요하면 수십 fA 수준도 검토할 수 있다.
- 하나의 전류값에만 맞추기보다 조도에 따른 넓은 current range에서 회로가 어떻게 반응하는지 확인해야 한다.

#### Q2. 기준 photocurrent bias와 step 변화율·rise time의 공통 test condition이 있는가?

- 하나의 고정된 bias와 rise time을 공통 조건으로 지정하지 않는다.
- 입력광은 pulse나 sinusoidal wave보다 ideal step function으로 인가하고, step 이후 event가 출력될 때까지의 response delay를 측정하는 방식을 권장한다.
- 50% step을 사용할 수 있다. 과거 회로는 약 25-30% 변화에서 event를 안정적으로 검출했고 최근 회로는 약 1-2% 변화까지 검출하려는 수준이라고 설명했다.
- Background illuminance가 1 lux, 10 lux, 100 lux, 1000 lux일 때 같은 변화율에서도 response가 달라질 수 있으므로 여러 조도 조건을 비교해야 한다.
- 낮은 조도에서 빠른 반응을 얻으려 하면 noise가 증가하므로 sensitivity·latency·noise 사이의 trade-off를 제시해야 한다.
- 추가로 언급한 상한 예시는 약 1 μA이다. 최대값 자체보다 현실적인 전체 동작 범위와 pixel array 전체 전류를 함께 고려하는 것이 중요하다.

### 회로의 민족 · 임채균

#### Q1. 회로가 커지더라도 참신성에 집중해도 되는가? 어느 정도까지 PPA를 고려해야 하는가?

- 별도의 절대 PPA target은 정해져 있지 않다.
- 아이디어의 참신성과 혁신성뿐 아니라 실제로 동작하는 회로인지가 중요하다.
- 동일한 function을 수행하는 baseline과 비교해 더 높은 performance, 더 낮은 power, 더 작은 area를 달성했는지 보여야 한다.
- 참신하지만 지나치게 큰 구조라면 area·power 비용을 감수할 만큼의 성능 또는 기능적 이득이 있는지 정량적으로 설명해야 한다.

#### Q2. AER bus width가 정해져 있는가?

- Bus width는 정해져 있지 않으며 팀이 선택할 수 있다.
- 16-bit로 좁게 구성하고 높은 clock 또는 여러 cycle로 전송할지, 32-bit·64-bit로 넓게 구성할지 등을 비교할 수 있다.
- Bus width는 throughput, latency, wiring·register area, switching power와 직접 연결되므로 PPA 관점에서 선택 근거를 제시해야 한다.
- 내부 event 발생량, 외부 output bandwidth, event 표현 방식과 encoder·decoder 효율을 함께 고려해야 한다.

#### Q3. Spike 수와 발생 속도에 정해진 설정값이 있는가?

- 고정된 spike 개수나 발생 속도는 없다.
- Sparse event부터 dense·burst event까지 팀이 traffic 조건을 설정하고 어느 발생률까지 처리 가능한지 시뮬레이션해야 한다.
- Random 또는 Poisson arrival 기반의 이벤트 발생 모델을 사용할 수 있고 실제 제공 예정인 이벤트 영상도 참고할 수 있다.
- 최대 입력 event rate, sustainable throughput, buffer overflow 시점, loss rate를 함께 제시하는 것이 적절하다.

### 전전긍긍 · 곽호준

#### Q1. Sensor의 raw request·readout부터 설계하는가? 이미 encoding된 event stream을 입력받는가?

- 입력 방식은 고정되지 않은 open condition이다.
- Pixel-parallel request·polarity 입력부터 설계하거나 이미 중재된 serial event stream을 입력으로 가정하는 방식 모두 가능하다.
- Raw request를 처리한다면 pixel 내부 저장 방식, readout 배선, arbitration, ACK까지 정보를 유지하는 방법을 직접 정의해야 한다.
- Serial stream을 사용한다면 valid·x·y·polarity 형식, backpressure와 handshake 동작을 직접 정의해야 한다.
- Request 발생부터 실제 readout까지 시간이 길어질 때 pixel 정보가 사라질 수 있으므로 event 보존률과 처리 latency를 검증해야 한다.

#### Q2. Polarity event만 제공되는가? ATIS처럼 intensity도 함께 제공되는가? Event format이 정해져 있는가?

- 이번 과제의 기본 범위는 polarity event만 처리하는 것이다.
- Intensity 영상은 기존 video compression codec과 hardware IP가 이미 성숙해 있으므로 이번 문제에서는 아직 표준화가 덜 된 event readout과 표현 효율에 집중한다.
- ATIS처럼 polarity와 intensity를 모두 다루는 확장 설계도 가능하지만 기존 개선형 AER보다 실제로 더 효율적이라는 근거를 제시해야 한다.
- Event의 세부 data format은 고정되지 않았으며 팀이 packet 구조를 정의할 수 있다.

#### Q3. Sensor와 world-memory 해상도, 여러 크기 지원 여부, FOV가 정해져 있는가?

- Sensor의 n×m과 더 큰 world-memory의 N×M은 고정되지 않았으며 팀이 감당 가능한 크기로 정할 수 있다.
- 초기 구현은 128×128 또는 256×256에서 시작하고 확장 가능성을 확인하면서 약 1000×1000 수준을 목표로 고려할 수 있다.
- 여러 크기를 반드시 모두 구현하라는 요구는 확인되지 않았다. Parameterized RTL이나 scalability 분석을 제시하면 확장성을 설명하기 좋다.
- 수평·수직 FOV도 팀이 정하며 인간 기준 약 70-80도를 참고할 수 있다.
- FOV와 별개로 센서 자세 변화는 yaw, pitch, roll을 모두 포함한다.

#### Q4. 평균·최대 burst throughput과 지속 시간이 정해져 있는가? 모든 event를 보존해야 하는가?

- 평균·최대 event rate와 burst 지속 시간은 고정되지 않았으며 팀이 현실적인 시나리오를 정의해야 한다.
- 설정한 output bandwidth를 초과하는 입력까지 무조건 처리할 수는 없으므로 buffer와 event-selection 전략을 함께 설계해야 한다.
- 모든 event를 반드시 보존해야 하는 것은 아니며 일부 loss를 허용할 수 있다.
- Traffic별 입력량, 출력량, loss rate, latency와 그로 인한 PPA 이득을 정량적으로 제시해야 한다.
- 외부 link 예시로 10-20 Gbps, 전용 processor interface 예시로 약 40 Gbps가 언급됐지만 공식 의무 target은 아니다.

#### Q5. Sensor 회전축, 범위·속도, trajectory와 회전 정보 제공 방식은 어떻게 되는가?

- Sensor 회전은 yaw, pitch, roll을 모두 포함한다.
- 초기 과제에서는 회전·움직임 정보를 알고 있다고 가정하고, 해당 정보가 주어졌을 때 sensor coordinate를 world coordinate로 변환하는 구조부터 설계한다.
- 교수님이 제공할 이벤트 영상에 어떤 환경에서 어떻게 움직이며 촬영한 데이터인지에 대한 정보도 함께 제공할 예정이다.
- 회전 정보를 센서 데이터만으로 추정하는 문제는 향후 확장 가능한 실제 문제이지만 초기 과제의 필수 범위에서 제외한다.
- 구체적인 회전 범위와 속도는 공통값으로 고정되지 않았으며 팀이 simulation scenario로 정의해야 한다.

#### Q6. 관측 대상은 static, quasi-static, dynamic 중 무엇인가? 한 번 또는 반복 scan인가?

- 초기 관측 대상은 static한 3D 환경으로 가정한다.
- 센서가 움직이면 정지 물체도 영상에서는 움직이는 것처럼 보이므로 우선 sensor motion에 따른 좌표 변환 문제에 집중한다.
- 물체 자체의 움직임까지 분리하는 dynamic scene은 난도가 크게 증가하므로 후속 확장 문제로 본다.
- 한 번의 scan 후 종료할지 반복 scan할지는 고정하지 않았다.
- 연속 동작을 설계한다면 시간 누적, memory 갱신, 중복 event 처리 방식을 팀이 정의해야 한다.

#### Q7. World memory에 intensity를 복원해야 하는가? Cell 표현과 bit width, memory 구현 방식은 어떻게 되는가?

- Polarity event로 원래 intensity를 복원하는 것은 별도의 큰 AI 추정 문제이므로 이번 과제에서 요구하지 않는다.
- 특정 sensor pixel에서 발생한 polarity event가 올바른 world coordinate의 cell에 mapping되는지를 확인할 수 있으면 된다.
- Cell에 polarity, event 발생 여부, 누적값, contour 정보 중 무엇을 저장할지와 bit width는 팀이 정할 수 있다.
- World memory는 외부 DRAM이 아니라 on-chip SRAM으로 구현하는 방향이다.
- 선택한 표현 방식이 mapping accuracy, memory capacity, update bandwidth, area·power에 미치는 영향을 설명해야 한다.

#### Q8. 입력 noise가 포함되는가? Noise 제거 기능이 평가 대상인가?

- 실제 입력에는 noise가 있다고 가정하며 제공 예정인 실제 sensor data에도 noise가 포함될 수 있다.
- Noise 제거 기능 자체가 일률적인 필수 항목은 아니다.
- Noise를 제거하거나, noise가 있어도 강건하게 동작하거나, 확률적 정보로 활용하는 등 팀의 전략을 정할 수 있다.
- 중요한 것은 해당 전략을 선택한 이유와 accuracy·event rate·power 등에 어떤 이득이 있는지 입증하는 것이다.
- 교수님은 noise event와 spike를 probabilistic estimator에 활용한 샌디에고 대학 연구팀의 수상 사례를 예로 언급했다.

#### Q9. 대표 사용 환경이나 application이 있는가?

- 궁극적인 application은 robot이나 drone처럼 센서 자체가 이동·회전하는 환경을 염두에 둔다.
- 대회 기간에 robot·drone 전체 시스템까지 구현하는 것은 요구되지 않는다.
- 이동 센서가 관측한 event를 안정적인 world coordinate로 변환하는 사용 시나리오를 중심으로 설계하면 출제 의도와 부합한다.

#### Q10. 공식 I/O interface와 testbench, 목표 frequency·latency·area·power 조건이 제공되는가?

- 고정된 I/O interface와 완성형 testbench는 제공되지 않는다.
- 교수님이 실제 이벤트 영상과 촬영·회전 상황을 제공할 예정이며 팀은 이를 참고해 testbench를 구성할 수 있다.
- 목표 frequency, latency, area, power의 단일 절대값도 공통 지정되지 않는다.
- 팀이 목표 application과 interface를 가정해 제약조건을 정하고 baseline과 동일 조건에서 PPA를 비교해야 한다.
- 공정은 45 nm 교육용 PDK를 사용한다.

### 도통 모르겠네 · 이상엽

#### Q1. 입력 파형과 광전류 세기를 어떻게 설정해 simulation해야 하는가?

- 입력은 pulse나 sinusoidal wave보다 ideal step function을 사용하는 것이 적절하다.
- Background illuminance에서 광입력을 일정 비율 증가 또는 감소시킨 뒤 event 발생까지의 latency와 검출 여부를 측정한다.
- 50% step을 기본 예로 사용할 수 있고, 25-30% 또는 1-2% 변화까지 검출 가능한지 확장 비교할 수 있다.
- 1 lux, 10 lux, 100 lux, 1000 lux 등 여러 조도 조건에서 sensitivity·latency·noise를 비교하는 것이 적절하다.
- 매우 낮은 photocurrent는 1 pA 수준부터 필요하면 수십 fA까지 검토하고, 상한은 약 1 μA까지 시뮬레이션해 볼 수 있다.
- 지나치게 어두운 조건을 만족시키기 위해 photodiode를 비현실적으로 크게 만들기보다 목표 사용 환경과 pixel density를 함께 고려해 현실적인 범위를 정해야 한다.

#### Q2. 단일 pixel 출력을 latch에 저장하는 것으로 충분한가? 어떤 정보를 출력해야 하는가?

- Pixel output을 latch에 저장하는 방식도 허용된다.
- Latch는 event 정보를 readout할 때까지 보존하는 per-pixel memory 역할을 한다.
- 단순히 한 번의 변화를 확인하고 끝내는 것이 아니라 readout 후 latch를 clear·reset하고 다음 event를 다시 저장할 수 있어야 한다.
- 빠르게 event가 반복되는 상황에서 capture → hold → read → clear → re-arm 동작이 정상적으로 이어지는지 simulation해야 한다.
- Latch와 capacitor 기반 storage 등의 대안을 area·power·retention·readout speed 관점에서 비교하고 선택 이유를 설명해야 한다.
- 기본 출력 정보는 event 발생 여부와 polarity이며 정확한 intensity 값의 출력은 필수 범위가 아니다.

### 제이엔유 · 박준수

#### Q1. Pixel별 좌표를 생략한 packet 형식과 대응 decoder를 설계해도 되는가? 저장부·arbiter·송수신 decoder의 범위와 손실 처리는 어떻게 되는가?

- Pixel별 x·y 좌표를 생략한 자체 packet format과 대응 decoder를 설계해도 된다.
- 결정적 scan order, header의 기준 좌표, 위치별 2-bit state 등 제안한 구조를 자유롭게 적용할 수 있다.
- 중요한 것은 기존 AER보다 어떤 이득을 얻는지 RTL 구현과 정량 비교로 입증하는 것이다.
- 좌표 overhead 감소와 함께 event가 없는 pixel까지 전송하는 비용, dense·sparse traffic별 효율, decoder area·power·latency를 모두 비교해야 한다.
- 제안한 end-to-end system을 평가하려면 pixel event storage, arbiter·scan logic, transmitter, receiver decoder를 가능한 범위까지 포함하는 것이 적절하다.
- 혼잡 시 최초 event만 유지하고 후속 변화를 버리는 loss 처리도 가능하다. Stimulus별 input event, output event와 loss rate를 정량 보고해야 한다.

#### Q2. 별도 snapshot memory 없이 현재 상태를 순차 read하는 rolling scan의 시간적 비동시성이 허용되는가?

- Rolling scan을 포함한 scan-based readout 구조를 사용할 수 있다.
- 하나의 packet이 반드시 동일 시점의 완전한 snapshot이어야 한다는 조건은 제시되지 않았다.
- Packet 내 pixel별 관측 시점이 달라지는 특성을 명시하고 최대 시간 차이 또는 scan period를 정량화해야 한다.
- Snapshot memory 방식과 비교해 추가 memory area·power를 줄인 이득과 temporal skew로 인한 정확도 손실을 함께 제시해야 한다.
- 전통적인 event-time AER, 2017년 전후 등장한 scan·rolling-scan 계열 등 readout 방식의 변화를 조사하고 baseline을 선정해야 한다.

#### 추가 Q1. Digital 설계의 event 입력은 pixel-parallel인가, serial인가? 동시에 여러 event가 발생할 수 있는가?

- Event input 방식은 open condition이다.
- Pixel-parallel request·polarity 방식과 serial valid·x·y·polarity 방식 중 원하는 구조를 선택할 수 있다.
- Pixel-parallel을 선택하면 동시 다중 event, ACK까지 request·polarity 유지 여부, arbitration과 starvation을 직접 정의해야 한다.
- Serial 입력을 선택하면 upstream arbitration과 backpressure를 어디까지 가정했는지 명시해야 한다.
- Request부터 readout까지 시간이 길어져 정보가 사라지는 경우를 포함해 event 보존률과 latency를 검증해야 한다.

#### 추가 Q2. Timestamp를 packet에 반드시 포함해야 하는가?

- Timestamp는 필수가 아니며 필요한 수준을 팀이 정할 수 있다.
- Per-event timestamp, packet-level timestamp, timestamp 미사용 중 application에 맞는 방식을 선택하면 된다.
- 예를 들어 전체 array를 10 μs마다 scan한다면 약 10 μs의 시간 해상도가 이미 정해지므로 모든 pixel에 개별 timestamp를 넣지 않아도 될 수 있다.
- Sparse event에서는 per-event timestamp가 유리할 수 있으므로 traffic에 따라 장단점이 달라진다.
- 실제로 확보할 수 없는 시간 정밀도를 표현하기 위해 불필요하게 많은 timestamp bit를 사용하는 것은 재검토해야 한다.

#### 추가 확인. Array 크기, bus width, handshake, 목표 frequency, PVT, memory macro, pre-layout 제출 범위, 생체모사 수준이 별도 규격으로 정해져 있는가?

- 세부 항목은 대부분 open condition이다. 합리적인 조건을 설정하고 제출 자료에 가정·비교 기준을 명시하는 접근이 적절하다.
- 공정은 45 nm 교육용 PDK 범위에서 아날로그와 디지털 모두 처리한다.
- PDK에서 제공되지 않는 특정 공정 IP나 vendor primitive를 전제로 하면 안 된다.
- 생체모사는 아이디어의 배경이지만 생물학적 동작을 그대로 재현하는 것보다 event를 효율적으로 추출·표현·변환하는 회로 설계가 핵심이다.

### SKK하이닉스 · 조민석

#### Q1. 1차 과제에서 비교할 ‘전통적인 AER’ baseline은 무엇인가?

- 별도로 지정한 단일 회로만을 baseline으로 두는 방식은 아니다.
- Stanford의 Kwabena Boahen 교수가 제안한 초기 전통적 AER부터 현재의 개선·변형 구조까지 조사해야 한다.
- 전통적 AER 자체에도 한계가 있고 최신 방식에도 문제가 남아 있을 수 있으므로 기존 구조를 분석한 뒤 더 효율적인 표현·readout 방식을 제안하는 것이 1차 과제의 의도이다.
- 2017년 전후의 scan·rolling-scan 계열 등 readout 방식의 변화도 참고해 팀의 문제 정의와 가장 관련 있는 baseline을 선택해야 한다.

#### Q2. 1차 과제에서 개선한 AER module을 2차 과제 입력 interface로 연동해도 되는가?

- 해당 방향이 과제 의도와 부합하며 연동하는 것이 바람직하다.
- 1차에서 효율적인 event 표현·통신 방식을 만들었다면 2차에서도 동일 방식을 사용해 sensor coordinate를 world coordinate로 변환해야 한다.
- 1차와 2차를 별개 결과물이 아니라 하나의 연속된 system pipeline으로 설계해야 한다.

#### Q3. 1차 과제의 pixel resolution이 정해져 있는가?

- 고정된 resolution은 없다.
- 최종적으로 약 1000×1000 수준을 염두에 둘 수 있지만 처음부터 큰 array를 구현하면 부담이 크므로 128×128 또는 256×256에서 시작할 것을 권장한다.
- 작은 해상도에서 기능을 검증한 뒤 parameter scaling, throughput, address width, memory size 변화를 분석하는 방식이 적절하다.

#### Q4. 1차의 spike를 2D pixel coordinate로 보고 1·2차를 연속 pipeline으로 해석해도 되는가?

- 1차의 event를 2D sensor pixel coordinate 정보로 전제해 설계해도 된다.
- 2차에서는 sensor의 x·y 위치 자체가 아니라 해당 pixel이 실제 world의 어느 위치와 대응하는지를 계산하고 memory에 mapping해야 한다.
- Sensor coordinate는 센서 내부 위치일 뿐 world를 이해하는 최종 좌표가 아니다. 효율적인 AER 입력을 world coordinate로 원활하게 변환하는 구조가 핵심이다.
- 따라서 AER communication → coordinate conversion → world-memory mapping으로 이어지는 전체 system을 완성하는 것이 출제 의도와 부합한다.

### MAC가이버 · 지영빈

#### Q1. Clock 기반 동기식으로 제출해도 되는가? 비동기 handshake가 필수인가?

- Clock 기반 동기식 설계로 제출해도 된다.
- Event가 언제 발생할지 알 수 없다는 점에서 sensor output은 비동기적으로 보이지만, 이를 처리하는 digital system은 동기식으로 효율적으로 구현할 수 있다.
- Handshake를 사용해도 내부 상태 전이와 sampling은 clock 기반일 수 있으므로 handshake 자체가 완전한 asynchronous design을 의미하지 않는다.
- 비동기식을 선택하는 것도 가능하지만 왜 더 효율적인지와 throughput·latency·power 이득을 입증해야 한다.

#### Q2. Arbiter·encoder 교체 외에 interface나 protocol까지 변경해도 되는가?

- Interface와 protocol까지 포함해 자유롭게 변경할 수 있다.
- Packet format, scan order, bus width, timestamp, handshake, loss policy 등을 설계 목적에 맞게 바꿀 수 있다.
- 기존 방식보다 좋아졌다고 판단할 수 있도록 동일 조건의 baseline과 function, PPA, event 보존률을 비교해야 한다.

#### Q3. Area·power 비교를 위한 library, 목표 frequency, switching activity의 공통 조건이 있는가?

- 모든 팀을 하나의 목표 clock과 switching activity에 맞추는 별도 공통 평가 조건은 제시되지 않았다.
- 45 nm 교육용 PDK 안에서 현실적인 목표 frequency와 activity 조건을 팀이 설정해야 한다.
- 공통 조건이 없더라도 문제 접근, 설계 이유, 구현 현실성은 결과와 비교 방법을 통해 판단할 수 있다고 설명했다.
- 특정 수치 하나를 줄이는 데만 매몰되지 말고 전체 function과 PPA 균형을 보여야 한다.

### 찌릿찌릿 · 이윤재

#### Q1. RC-extracted parasitic 외에 PVT variation과 Monte Carlo까지 수행해야 하는가?

- 수행 가능한 범위에서 PVT variation과 Monte Carlo simulation까지 검증해 볼 것을 권장한다.
- RC extraction과 layout parasitic 반영의 목적은 실제 chip으로 제작했을 때 안정적으로 동작할지를 확인하는 데 있다.
- Process variation과 mismatch까지 확인하면 회로의 robustness와 silicon 동작 가능성을 더 강하게 입증할 수 있다.
- 다만 “가능하면 검증 가능한 것을 최대한 수행해 보라”는 권고에 가까우며 모든 팀의 절대 필수 조건으로 확정한 표현은 아니다.

---

## 1차 과제 추가 설명

### 과제의 핵심 목적

- 전통적 AER에서 event마다 x·y·polarity 등을 전송하며 생기는 overhead, arbitration delay, congestion, bandwidth limitation, event loss 문제를 분석한다.
- 전통적 AER와 이후 등장한 scan·rolling-scan·packetization·compression 등의 변형을 조사한다.
- 기존 구조의 문제를 정확히 정의하고 더 효율적인 event 표현과 readout·communication 방식을 RTL로 설계한다.
- 개선안이 실제로 동작하는지 검증하고 baseline 대비 PPA와 throughput·latency·loss를 비교한다.

### 권장 system boundary

- Pixel event/request 또는 가정한 serial event input을 정의한다.
- Event storage·latch·buffer와 arbitration·scan logic을 구성한다.
- Encoder·packetizer·serializer 또는 선택한 output interface를 구성한다.
- 필요하면 receiver decoder까지 포함해 end-to-end로 복원 가능함을 검증한다.
- 시간이 부족하면 핵심 bottleneck을 해결하는 block을 먼저 완성하고 나머지를 단계적으로 확장한다.

### 2차 과제와의 연결

- 1차 출력이 2차 coordinate conversion module의 입력이 되도록 packet과 interface를 설계한다.
- Sensor x·y·polarity와 주어진 yaw·pitch·roll 정보를 사용해 world coordinate를 계산한다.
- 변환된 위치에 polarity event 또는 팀이 정의한 표현을 on-chip SRAM world memory에 mapping한다.
- 1차와 2차를 별개 module이 아니라 event camera readout부터 world-memory update까지 이어지는 pipeline으로 구성한다.

### 제출 자료에 포함하면 좋은 항목

- 해결하려는 기존 AER의 문제와 선택한 baseline
- Input event model, array resolution, traffic pattern, clock, bandwidth, PVT·load·activity 가정 표
- 제안 architecture와 data flow, packet format, handshake, buffer·loss policy
- Sparse·dense·burst traffic에서의 throughput, latency, loss rate 비교
- 동일 조건에서 baseline과 제안 구조의 area, power, maximum frequency 비교
- 장점뿐 아니라 temporal skew, loss, decoder overhead 등의 단점
- 2차 과제로 확장할 interface와 coordinate-conversion 연결 방향

> **가장 중요한 평가 메시지**
>
> - “무엇을 설계했는가”뿐 아니라 “왜 그렇게 설계했는가”를 설명해야 한다.
> - 동일한 문제와 조건에서 기존 방식보다 무엇이 얼마나 개선됐는지를 수치로 보여야 한다.
> - 자유롭게 정한 조건은 숨기지 말고 assumption으로 명시해야 한다.

---

## 교수님 추가 설명

### Sensor와 world coordinate의 관계

- 사람의 눈은 계속 움직이지만 뇌는 여러 시점의 정보를 이어 붙여 안정적인 world를 인식한다.
- Sensor pixel의 x·y는 센서 내부 좌표일 뿐이며 실제 활용에서는 해당 event가 world의 어느 위치에 대응하는지가 중요하다.
- 초기에는 yaw·pitch·roll 정보가 주어진 static scene을 대상으로 변환 시스템을 설계한다.
- 향후에는 motion 자체를 추정하거나 dynamic object를 분리하는 문제로 확장할 수 있다.

### Noise를 바라보는 관점

- 실제 sensor와 neuron system에는 noise가 존재하므로 이상적인 무잡음 입력만 가정하지 않는다.
- 단순 filtering, noise-robust processing, probabilistic computation 등 여러 접근이 가능하다.
- Noise를 제거했다는 사실보다 system accuracy·event rate·power 측면에서 어떤 이득을 얻었는지가 중요하다.

### Photocurrent와 array 전체 전류

- Pixel 단위 최대 약 1 μA는 simulation 상한 예시로 언급됐다.
- 1000×1000 array의 모든 pixel에 1 μA가 흐른다고 가정하면 전체 photocurrent가 약 1 A가 되므로 chip-level current와 cooling까지 생각해야 한다.
- 단일 pixel의 동작만 확인하지 말고 array 규모에서 power와 current가 현실적인지 검토해야 한다.

### Mixed-signal 참가 방향

- Photodiode와 analog event-generation circuit, digital readout을 함께 설계하면 기본적으로 analog 성격이 강하다.
- Digital 문제를 풀면서 analog part를 포함해 더 좋은 전체 system을 제안하는 것도 가능하다.
- 어느 분야로 평가받을지는 구현의 중심과 제출 결과를 기준으로 판단해야 한다.

---

## 제출 및 운영 안내

- 1차 과제는 PPT 형식으로 제출한다.
- 1차 제출물은 문제 이해도, 설계 방향, 2차까지 진행할 의지를 확인하는 역할을 한다.
- 1차 미제출이 곧바로 2차 참가 불가를 의미하지는 않지만 1차를 준비하지 않으면 2차 과제를 진행하기 어렵다.
- 1차 결과를 본 뒤 gating 여부를 판단하되, 경진대회의 목적이 참가자가 반도체 설계 flow를 끝까지 경험하는 데 있으므로 가급적 gating을 최소화할 예정이다.
- 과거 연도 게시판에 Cadence digital tool 사용 manual과 자료가 있으므로 참고할 수 있다.
- Q&A에서 접수된 팀별 질문은 공유 반대가 없어 게시판에 전체 공개할 예정이다.
- 추가 질문은 email로 제출하며 공통 질문이 모이면 추가 Q&A session을 공지할 수 있다.
- 아날로그 1등과 디지털 1등을 구분해 시상하는 방안을 검토 중이지만 최종 확정 사항은 아니다.
- 약 380명이 참가 의향을 보였으나 실제 과제를 진행하는 팀 수는 더 적을 것으로 예상한다.
