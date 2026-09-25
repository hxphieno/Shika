# Independent lexical-quality review

The independent reviewer wrote the frozen corpus and native harnesses and did not modify production code. Ranking uses production engines, fresh user directories, and no answer selection/training. Every sentence commit case has its own fresh process/userdir. Expected answers remain exclusively in tests.

Final configuration: auxiliary correction-index minimum weight **100**, generic alternative-segmentation query budget **1**. The `after` evidence represents these final settings, not the rejected weight-800 experiment. Its segmentation-source hash matches final production. No single-word exception was added by the reviewer.

## Frozen Chinese quality

| Metric | Full pinyin before → final | Double pinyin before → final | Actual final mixed mode |
|---|---:|---:|---:|
| Targets | 172 | 172 | 172 |
| Exact Top1 | 87.79% → 93.60% | 90.12% → 96.51% | 93.60% |
| Exact Top5 | 94.19% → 98.84% | 94.77% → 100% | 98.84% |
| Exact Top10 | 94.19% → 100% | 94.77% → 100% | 100% |
| MRR10 | .9062 → .9601 | .9244 → .9826 | .9598 |
| Whole intended sentence committed | 18/20 → 19/20 | 18/20 → 19/20 | 19/20 |
| Entire input consumed on first selection | 20/20 → 20/20 | 20/20 → 20/20 | 20/20 |

Mixed results come from `SKConversionEngine` with `.mixed`, not from relabeling the pure Chinese engine. `丝滑` is now first for full `sihua` and double `sihx`; it was absent from the first ten before. Gains include 词频、双拼、通勤、候选词、充电宝 and sentence quality. Actual regressions remain: 接口 and 老师 fall from first to second, behind 借口 and 老是. These were not patched with heldout-specific frequencies.

The original engine already generated long sentences; this is a measurable improvement rather than a new claim of sentence support. Double-pinyin encodings already disambiguate many boundary pairs, so they cannot be credited as equivalent ambiguous raw-input cases.

## Generic segmentation parameter experiment

The user clarified that `shuna` was only an illustrative, imperfect example. Acceptance therefore uses the original six genuine pairs plus eighteen additional real pairs, including 饥饿/接、余额/月、图案/团、心安/西南、阴暗/疑难 and actual place names: **24 pairs / 48 targets**. The extra corpus was fixed before running query limits 0, 1, and 3. Each setting used identical frozen weight-100 resources; edits happened only inside temporary source snapshots.

| Alternative-query budget | 48-target Top10 | Both targets in Top10 | 172 full/mixed Top1 | 172 full/mixed Top10 |
|---|---:|---:|---:|---:|
| 0 | 43/48 | 19/24 pairs | 161/172 | 171/172 |
| 1 | 47/48 | 23/24 pairs | 161/172 | 172/172 |
| 3 | 47/48 | 23/24 pairs | 161/172 | 172/172 |

**Recommend 1, as adopted.** Three has no measured coverage gain, moves 激昂 from #9 to #10 and 西澳 from #8 to #9 in the expanded corpus, and can add unnatural combinations such as 皮啊哦. One preserves correct first choices and limits work. The remaining extended-corpus miss is 吉安 for unseparated `jian`; we do not claim exhaustive ambiguity coverage. Query 0 suppresses supplemental probes but still constructs the bounded DAG, so it is a candidate-quality control, not a precise measurement of a completely removed layer's overhead.

The diagnostic before/after probe distinguishes native candidates from supplemental displayed candidates. Before supplementation, `piao` had 飘 #2 and 皮袄 #21 among all 348 native candidates, demonstrating low rank rather than a missing dictionary entry. The generic layer promotes an alternate full parse into the visible candidates. The former `shuna` diagnostic also demonstrates that a `shun` prefix can exist without a full `shun a` candidate; this is explanatory evidence, not a special-case product standard. Seven independent route checks passed: whole alternate selection/clear, repeat commit, stale UI tap, mixed expanded selection, and switching back to unchanged double-pinyin routing.

## Japanese

Actual Japanese-engine ranking on the prepared 40 targets: exact Top1 **37/40 (92.5%)**, Top5/10 **40/40**, MRR10 **.9583**. All 40 target selections commit exactly and clear composition in a separate run. Another 37 functional checks plus two separate-process learning write/read checks pass: **79 total checks**. Coverage includes romaji, small kana, double consonants, explicit syllabic-n boundaries, long vowels, pending text, deletion, clear, space, invalid candidate indices, pagination, mixed Japanese-selection routing, and a mixed→Japanese switch.

The Japanese decoder/lexicon/mixed-dispatch files and three Japanese resources were hash-verified unchanged after final Chinese tuning (`japanese/final-code-resource-verification.json`), so that run is reused rather than needlessly repeated. Final mixed Chinese ranking was independently rerun above. One initially incorrect test used `kinyoubi` for きんようび; the correct explicit input is `kin'youbi`. The test was corrected, with no production exception.

The implementation combines Mozc vocabulary/connection data with the project's decoder. This does not establish parity with the full Mozc converter or broad Japanese correction/proper-name quality from only forty ordinary targets.

## Memory, latency, and scope

All native figures below are macOS high-water RSS, not iOS physical footprint:

- Original small dictionary: 15.12 MiB full / 15.00 MiB double.
- Intermediate full correction index: 122.66 / 107.02 MiB (`full-correction-index`).
- Rejected weight-800 index: 55.83 / 43.44 MiB (`restricted-index`). That setting kept this 172-target ranking but lost some independent correction behavior, so it was not selected.
- **Final weight-100, query-1**: 84.61 MiB full / 70.33 MiB double / 111.91 MiB actual mixed on this corpus. Final macOS per-key p95 was 1.833 / .583 / 4.928 ms respectively. Compared with the small baseline's .608 / .306 ms, additional resources have real costs.

Single-run latency varies with shared-machine builds, cache state and scheduling; it is a diagnostic, not a statistical performance guarantee. The implementation owner separately measured iOS physical footprint, UI behavior, and correction regression; those results are distinct from this review's direct native-engine evidence. In particular, macOS RSS and an iOS host app's footprint must not be equated to a real-device keyboard-extension stress test.

The fixed corpus establishes a reproducible improvement with reported regressions and parameter tradeoffs, not exhaustive vocabulary or sentence correctness. Rankings are exact text matches; programmatic first-ten retrieval is not a visual keyboard usability test. No commit was made by the reviewer.
