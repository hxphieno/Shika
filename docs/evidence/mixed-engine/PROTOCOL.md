# Mixed decoder evaluation protocol

Before opening the heldout results, freeze the independent 250-case fixture and
choose search parameters on its development partition only. Source-family split
is defined by the fixture generator; the runtime must never read test fixtures.
The author independently checked source vocabulary and readings; excerpt-derived
sentences are adaptations, not 200 organic chat messages.

Primary comparison: old candidate concatenation vs joint decoder, **identical
updated vocabulary**, fresh process/user directory, no selections or learning
during ranking. Report source excerpt adaptations, language direction, pure
controls, development and heldout separately; don't claim the old system cannot
commit foreign words merely because it cannot form whole mixed sentences.

Targets before heldout inspection:
- Clean heldout mixed Top5 >= 70%, Top10 >= 80%, with a substantial improvement
  over old whole-buffer concatenation. Accept predefined orthographic variants.
- Pure heldout controls Top5 >= 95%; inspect introduced foreign-script first
  candidates rather than interpreting every Chinese/Japanese homograph as a switch.
- Zero input loss/duplicate commits in focused interaction checks, including
  partial selection, multi-switch locking, deletion, Return, punctuation, paging,
  explicit separators, mode change, long input and cross-process learning.
- Compare beam 16/32/64 on development only; prefer the smaller beam if quality
  is unchanged. Record P50/P95/P99 per-key latency and memory independently of
  dictionary file size. iOS optimized controller/UITextView runtime evidence is
  required; label simulator host measurements separately from physical extension.

No silently removed failures or targets changed to match engine output. A
verified transcription defect may be corrected with an errata record; errors
in the algorithm remain in the reports. If heldout failures prompt subsequent
changes, label it validation data rather than pretending it is still untouched.

## Frozen release

Fixture v2 SHA-256: `995730125c309ac2138ec06c7222d6037b0bc8f191c69c7c232e6d60f24e3480`.
Five independently verified transcription corrections are logged in
`docs/mixed-corpus-research.md`; expected outputs and splits were unchanged.
No production algorithm or word entries were adjusted after heldout inspection.
All preregistered gates passed; failure rows remain in `final/failures.json`.
Host benchmarks and simulator checks overlapped in wall time, so use the
sequential development sweep for beam tradeoffs; release timings are observed
latencies, not isolated-device guarantees.
