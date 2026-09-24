| Scheme | Error | N | Top1 baseline→corrected | Top3 baseline→corrected | Top8 baseline→corrected |
|---|---|---:|---:|---:|---:|
| shika_pinyin | clean | 40 | 35→35 | 36→36 | 36→36 |
| shika_pinyin | substitution | 40 | 0→22 | 5→34 | 5→34 |
| shika_pinyin | omission | 40 | 3→11 | 4→30 | 4→32 |
| shika_pinyin | insertion | 40 | 0→25 | 4→34 | 4→34 |
| shika_pinyin | transposition | 40 | 1→26 | 3→35 | 3→35 |
| shika_flypy | clean | 40 | 35→35 | 36→36 | 36→36 |
| shika_flypy | substitution | 40 | 0→6 | 0→28 | 0→30 |
| shika_flypy | omission | 40 | 1→15 | 1→24 | 1→25 |
| shika_flypy | insertion | 40 | 0→31 | 0→35 | 0→35 |
| shika_flypy | transposition | 40 | 0→13 | 0→32 | 0→33 |
Clean first changes: 0 clean target regressions: 0
Unexpected typing commits: 0 target select failures: 0 space failures: 0
Mac latency: {'p50': 1.1249780654907227, 'p95': 13.55588436126709, 'p99': 38.39707374572754, 'max': 94.64395046234131}
