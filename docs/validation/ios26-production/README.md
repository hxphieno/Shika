# Independent production-extension acceptance

2026-09-25, iPhone 17 Pro simulator / iOS 26.5 / 402 pt / 3×. An independent agent operated the installed `funno.Shika` app and its actual `funno.Shika.ShikaKeyBoard` keyboard extension through coordinate clicks in the normal TextEditor. This was not the standalone UIKit smoke host or a synthetic text proxy. Open Access was not enabled; the extension declares `RequestsOpenAccess=false`.

## Real input and commit results

Every code below was entered by clicking the visible keyboard keys, without pasting the desired text. Before selection, the composed letters remained in the candidate area rather than being incorrectly inserted into the host.

| Scheme | Actual wrong code | Observed target | Commit action | Cumulative host text |
|---|---|---|---|---|
| Full pinyin | `nohao` | 你好, second candidate | Tap second candidate | 你好 |
| Full pinyin | `zhnogguo` | 中国, first candidate | Space | 你好中国 |
| Double pinyin | `niihc` | 你好, first candidate | Tap first candidate | 你好中国你好 |
| Double pinyin | `nhc` | 你好, first candidate | Space | 你好中国你好你好 |

Candidate evidence: `full-nohao-candidates.png`, `full-zhnogguo-candidates.png`, `double-niihc-candidates.png`, and `double-nhc-candidates.png`. Each selection cleared the remaining composition. This verifies candidate routing and actual host insertion as well as candidate presence. `nohao` did not automatically become the correct first candidate; its second-place success must not be reported as first-choice accuracy.

## Main keyboard and navigation

- A single Shift tap immediately changed all letter labels to uppercase; tapping Q inserted `Q`.
- A double click on Shift engaged caps lock; subsequent Q and W inserted `QW` and the keyboard remained uppercase.
- After unlocking, three actual delete touches removed exactly `QQW`, with no extra deletion on release.
- The 123 key opened the user's original number/symbol design (`numbers-preserved.png`). Clicking 1 inserted one digit; Return-to-keyboard restored double pinyin, including its annotations.
- Final TextEditor value, also reported by its accessibility state, was exactly **你好中国你好你好1** (`final-output-and-double-return.png`).
- In that original 1206×2622 screenshot, main-key top edges are y1767, 1929, 2091, 2253; visible key height is 129 px (43 pt), row pitch 162 px (54 pt). The four rows fit the 216 pt main surface without clipping or Auto Layout compression. Absolute Y differs from the system reference because the candidate region has its own retained height; it is not part of this redesign comparison.
- The existing candidate UI, deer control, full-pinyin long-vowel key, double-pinyin hints and custom number page remain visible and usable.

## Scope and limitations

These are genuine Simulator extension interactions, not physical-iPhone measurements. This independent touch pass covered normal deletion, Shift, caps lock and number-page return. The CUA API does not expose a sustained touch-down duration, so it did not independently exercise held-delete repetition; that behavior is covered by the separate timed production-button interaction harness. It must not be claimed as a manually held physical-device test.

Resting native references and actual native pressed-key recordings are under `../ios26-reference/`. The implementation comparison reports resting keycap bounds within 1 px and representative glyph bounds within 2 px at the reference size, rather than asserting that every native blur pixel or animation frame is identical. Customized labels and phonetic annotations intentionally differ.

## Environment restored

All nine originally enabled keyboards and their original order were restored after the temporary test isolation: Chinese full QWERTY, emoji, English US, Chinese nine-key, Chinese handwriting, Japanese Kana, Japanese Romaji, English Japan, Shika. Appearance remained light. The Simulator’s temporary “Send Keyboard Input to Device” capture mode was also disabled through I/O → Input → Send Keyboard Input to Device. The window title returned to “iPhone 17 Pro — iOS 26.5”, confirming that the capture hint had cleared.
