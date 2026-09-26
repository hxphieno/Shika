# Independent sentence-limit acceptance

Production code was not modified by this reviewer. The reviewer froze pre-change sources before implementation, built against the real Rime static library and bundled Chinese/Japanese dictionaries, and ran a targeted set of native engine tests. No full UI suite was run here.

- The screenshot is reproduced exactly by the mixed engine, not the plain pinyin/shuangpin engines.
- Mixed candidates: 69 before, 51 after. `海边` moves from rank 46 to rank 7.
- The original best six candidates retain text, IDs, comments, consumption and ordering.
- Cold-user pinyin (93 candidates) and shuangpin (92 candidates) before/after snapshots are exactly equal.
- Final independent acceptance: 68/68. Covers 14 Chinese/Japanese/mixed/explicit-boundary cases, all-page sentence cap, true single-word prefixes, duplicate identities, seven real four-character homophones retained, 中华人民共和国 retained, stable pagination and IDs, raw Return after prefix selection, space, and actual sequential choice 海边→点→起→烟火 with exact remaining input and final output 海边点起烟火.
- Initial harness assertions assumed learning could not change first-choice ranking across selections. Those failed (56/58, then 62/63); final assertions compare space with the current selection state and require prefix availability after at most six recommendations. The independent cold-user before/after comparison remains exact and was not relaxed. Initial reports are retained alongside the final report.
- Current decoder SHA-256 matches the frozen decoder used for the final run.

Reproduce: `bash scripts/test-sentence-limit.sh /tmp/shika-sentence-clean-run` (fresh directory). The script passes shell syntax validation; equivalent compile/link/run commands produced the final report.
