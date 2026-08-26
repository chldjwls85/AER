# Reference Versions

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
| Primary real dataset | UZH Event-Camera Dataset `shapes_rotation` |
| CIFAR10-DVS provenance | not found in any repository ref/history or local `AI-semi` files |
| Previous ROW/BANK evaluation date | 2026-08-21 (Asia/Seoul) |
| SPARSE full evaluation date | 2026-08-26 (Asia/Seoul) |
| UZH archive SHA-256 | `56aade6bf53dcf73e8fe40905ccac8385cd7606bc9a85103bf2c9f9045117551` |
| Current full-gate decision | `READY FOR CADENCE EVALUATION` |

Pinned SHA를 primary comparison source로 사용한다. 팀 branch가 이후 변경되더라도
평가 입력 RTL은 이 SHA에서 export해 재현성을 유지한다.
