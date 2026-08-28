# 일일 자동화 실행 명세

- 제목: `Daily /tmp team research tracking`
- 일정: 매일 09:00
- 시간대: `Asia/Seoul`
- 작업 디렉터리: `/home/aiasic26230/LVMOS/eojin/team-tracking`
- 브랜치: `codex/daily-team-tracking`

## 실행 프롬프트

공유 서버 `/tmp`를 읽기 전용으로 조사해 다른 팀의 AER 연구 변화를 전날 `docs/team_tracking/YYYY-MM-DD.md`와 비교한다. `docs/team_tracking/README.md`의 운영·Git·정리 규칙을 반드시 지킨다.

1. `/tmp` 최상위 파일과 디렉터리의 소유자, 크기, 수정시각을 확인한다. Cadence/Xcelium 생성 캐시만으로 연구 방향을 단정하지 않는다.
2. 문서, RTL 모듈명, 테스트 PASS/FAIL, Genus/Innovus 결과가 있는 계정만 의미 있는 연구 변화로 기록한다. 새 파일, 수정, 삭제된 임시 증거를 구분하고, 사라진 파일을 연구 철회로 해석하지 않는다.
3. `aiasic26230` 자체 산출물은 경쟁팀 동향에서 제외한다. 권한이 없는 디렉터리는 우회하지 않는다. 개인 이름, 인증키, 민감한 경로 내용은 보고서에 싣지 않는다.
4. 각 추적 대상에 대해 새 연구 방향, 구현 변화, 실행 결과, 성숙도 변화를 기록한다. 변화가 없으면 명시적으로 `변화 없음`이라고 쓴다.
5. `/home`과 `/tmp` 사용량을 기록한다. 저장공간 자동 삭제는 `/home/aiasic26230/LVMOS/eojin` 최상위 `core.*` 중 `file`로 ELF core dump임을 확인한 파일만 허용한다. `/tmp`와 `eojin` 바깥은 절대 수정·삭제하지 않는다. 다른 대용량 후보는 경로와 크기만 보고한다.
6. 오늘 날짜의 `docs/team_tracking/YYYY-MM-DD.md`를 작성한다. 같은 날짜 파일이 이미 있으면 중복 파일을 만들지 말고 갱신한다.
7. `git status --short`로 사용자 변경과 분리됐는지 확인하고 해당 날짜 보고서 및 필요한 인덱스 파일만 stage한다. `git diff --cached --check`를 통과시킨다.
8. 변경이 있으면 `chore: update team tracking YYYY-MM-DD`로 commit한다. `GIT_SSH=/home/aiasic26230/LVMOS/eojin/runtime_tmp/aer_git_ssh`를 사용해 `origin codex/daily-team-tracking`으로 push한다. push 실패 시 원인을 보고하고 다른 브랜치나 파일을 수정하지 않는다.
9. 최종 결과에는 변화가 확인된 팀, 변화 없는 팀, 삭제한 core dump와 확보 용량, commit hash, push 성공 여부를 요약한다.
