# Independent segmentation recall experiment

Decision: do not expand the current one-missing-path native query budget on this evidence.

Frozen discovery population: 6,737 inputs: the 6,000 highest-frequency production correction-index full-pinyin codes (3–32 letters), plus unique full-pinyin inputs from the previous frozen engine cases. The native resource files were unchanged. No candidate was selected during exploration, so no target was trained.

The harness independently reproduces the current eight-path bounded DP. It reads the production native session, filters paths already represented by its first candidate page, then probes every missing path with a separate real Rime session. The source word is metadata, not a desired alternative or success label.

3,629 inputs had multiple legal paths. For 29 inputs the first missing path offered no new exact-parse candidate. Probing later paths found additional text for 24; a cap of two probes would find 16, three would find 24. These are raw recall counts, NOT accuracy improvements. Of 6,781 exploratory native queries, macOS P95 was 0.138 ms in this single discovery run; this is not a full-keyboard or controlled before/after performance result.

Manual review shows the purported additions are mostly phonetic noise: 标准/biaozhun → 比啊哦准, 技能/jineng → 及呢嗯, 疯狂/fengkuang → 风跨嗯, 电脑/diannao → 迪安娜哦. Same-syllable-count gating alone still admits 跨嗯加, 恰嗯行, 十卦嗯, 框企鹅. The apparent absence of an exact candidate often occurs because Rime further splits a token inside an apostrophe-separated path: bi'ao'zhun returns 比熬煮嗯 with bi ao zhu n. There is no validated user-intended target recovered by simply increasing the budget in this population.

A future bounded experiment would need independently sourced ambiguous phrases/targets and a native lexical or sentence score to distinguish useful alternate readings from newly generated strings, followed by top-1/top-5 regression and latency gates. Avoid hardcoding a reject list from these outputs; that would overfit this experiment.

Production was not changed. The independent harness is Tests/ContinuousSegmentationRecallChecks.swift. Full path/candidate observations are discovery.json. Frozen case metadata is cases.json; source hashes are source-hashes.txt.
