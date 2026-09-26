# Independent candidate glyph acceptance

Final macOS result after the final Rime flush fix: 89/89. The preceding revision passed 88/88. Test: Tests/CandidateGlyphIndependentChecks.swift. Frozen production sources and SHA256 comparison are recorded alongside the report; the six affected core/engine/platform files match the final working tree.

The 32 frozen font probes retain their original expectations. The initial LastResort-only implementation failed one valid invisible sequence: standalone U+FE0F. It produced LastResort glyph 65535, zero advance, and zero CTLine/CTRun ink bounds. By contrast U+0378 produces a nonzero approximately 18×18 LastResort placeholder. This was a production false positive, not a changed test expectation. Final detection excludes only nonempty LastResort ink; all 32 font probes pass. Regular CJK/Japanese, NFC/NFD, 𠮷, emoji skin tones/flags/keycaps/ZWJ, visible square/replacement characters, and valid IVS remain preserved. Device-dependent unsupported extension code points are observed against actual local fallback, not rejected by range.

Old font/session subset result: 76/77. Old full result: 82/83. Separate real mixed reproduction found a second defect: after selecting 今天也, a completely hidden tail followed by punctuation returned jintianyearigatouq， instead of 今天也arigatouq，. Both failures are retained in subset/independent.json, first-full/independent.json and prefix-old.json. Final helper/session changes correct them.

Final session checks cover entirely visible native dispatch, exact candidate ID and consumedInputCount preservation, hidden stale-selection rejection, bounded synchronous work, access to visible candidates after 220 hidden rows, continuation after initial budget, end-of-page correctness, cancellation/edit invalidation, and equal text with distinct consumption. Real mixed checks cover partial-space behavior, hidden-tail fallback, punctuation flush, and no learning writes merely for browsing/partial or raw-tail choices. Real Rime checks select 颠簸 from dmbodnbo, then hide all tail candidates and verify space, punctuation and Return preserve 颠簸dnbo.

A test setup attempt initially used two Rime user directories within one process and hit the existing native singleton initialization guard before producing a report. The test was corrected to share one user root, matching production. No production workaround was made for that test setup error.

This is macOS font availability plus state/real-engine acceptance, not an iOS font-availability or screenshot claim. The main agent runs target-platform coverage separately. No production or UI code was written by this reviewer.

## Final partial-flush guard

A focused real-Rime replay with injected visibility allowing only 颠簸 from dmbodnbo reproduced a third unsafe route: default commitCandidate selected the visible partial prefix then internally committed an unchecked tail, outputting 颠簸调拨，. Expected conservative flush is 颠簸dnbo，. The injected visibility isolates control flow; it does not assert that 调拨 actually lacks glyphs. The final Rime override confirms the visible prefix and then uses native Return for remaining raw spelling. Normal native commit is unchanged.

Old focused failure is visible-prefix-before.json. The equivalent assertion now passes in the final 89-check run, final-revision-results/independent.json. All six production files match final-revision-sources and final-revision-source-comparison.json. The prior 88-check source snapshot remains archived and is not relabeled as this final revision.
