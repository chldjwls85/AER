# Reference Versions

- 목적: 비교에 사용한 branch/commit/dataset 기준을 고정해 결과 혼동을 방지함
- 주의: 표의 `Current`는 V3 SPARSE/ROW/BANK 평가 당시 명칭임
- V3/V4 최종 상태: `AER_V3_V4_DESIGN_EVOLUTION.md` 참조 필요함

| Item | Value |
|---|---|
| Repository | `https://github.com/chldjwls85/AER` |
| Team second design branch | `codex/aer-v1-global-readout` |
| Team second design pinned SHA | `da686477ca054faada5f66d369f1fb253b2bf562` |
| Team branch HEAD at audit | `da686477ca054faada5f66d369f1fb253b2bf562` |
| Pinned subject | `merge: integrate RAW8 baseline with balanced readout` |
| Fair RAW baseline top | `aer_v1_raw_top_128`, `ENABLE_BINNING=0` |
| Team second design top | `aer_v1_top_128`, `ENABLE_BINNING=1` |
| Current branch | `AER_hyeonho` |
| Current pre-freeze SHA | `f44416f3891f3ac6a10251cb2eb75ff91a5540dc` |
| First RTL freeze SHA | `f37ed043832424e18105d34fd81f29842d330c49` |
| Evaluated RTL basis | first freeze packetizer plus regression commit `a089f6f3291c38f880f096763137accd66e5f240` |
| Evaluation commit SHA | `34e7417c58e5a6824c7cfb12878f0da08f0dcd1a` |
| SPARSE/ROW/BANK RTL candidate SHA | `41292b5ca307f18b8d6e5730f1cd0b3335757629` |
| SPARSE full-evaluation / Cadence RTL basis SHA | `ad8fbd05b88e4645847dc438a5f3be668998882c` |
| Primary real dataset | UZH Event-Camera Dataset `shapes_rotation` |
| CIFAR10-DVS provenance | not found in any repository ref/history or local `AI-semi` files |
| Previous ROW/BANK evaluation date | 2026-08-21 (Asia/Seoul) |
| SPARSE full evaluation date | 2026-08-26 (Asia/Seoul) |
| UZH archive SHA-256 | `56aade6bf53dcf73e8fe40905ccac8385cd7606bc9a85103bf2c9f9045117551` |
| Current full-gate decision | `READY FOR CADENCE EVALUATION` |

- Team 비교 입력: pinned SHA에서 export함
- Team branch 후속 변경: 현재 비교 결과에 반영하지 않음
- V3 Cadence 입력: `ad8fbd05...` 기준임
- 문서 정리 commit: RTL 기능 변경 없음
