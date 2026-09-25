# iOS runtime evidence

Optimized iOS 26.5 Simulator **UIKit test host**, using the production keyboard
controller, real views, actual Rime/Swift decoders and a real UITextView. This is
not a signed keyboard-extension process on a physical phone.

`lexicon-runtime.json`: 120 language/scheme switches, plus the frozen 172-case
corpus entered independently through full pinyin, double pinyin and mixed mode.
The diverse-input section measures runtime safety/performance, not accuracy; it
does not select or train corpus target answers. 5,286 key operations and 5,410
assertions passed. Every key is checked for premature commit. Separate UI checks
replace marked text with Chinese/Japanese selections and verify exact output.

Physical footprint is measured with TASK_VM_INFO:
- Before engine: 19.83 MiB.
- Warm switching and diverse-word input: approximately 35–36 MiB.
- After all diverse input: 35.19 MiB; no sustained rise across corpus sections.
- UIKit/editor plus screenshots: transient 77.21 MiB.
- After screenshot autorelease drain: 52.41 MiB, including the editor, test host,
  UIKit/font caches and keyboard. Do not describe 35 MiB as the complete UI or
  claim an iPhone extension's memory limit has been certified.
- Single-run optimized per-key p95: 3.31 ms. Shared machine scheduling and input
  mix affect this figure; no claim of a universal worst-case bound.

PNG evidence shows the production candidate bars and marked/committed editor
text. Main alphabet geometry and the custom number/symbol layout are unchanged.
The Chinese UI example needs a settled UIKit run-loop after inserting the test
controller, just like a visible keyboard; an initial harness attempt typed during
presentation and was corrected with an initial run-loop wait. A Japanese test
initially used `wa` for the particle は; it was replaced by a conventionally
encoded sentence, not by a production romanization exception.

Additional regressions:
- `marked-text-result.txt`: 30 real UITextView/expanded-candidate checks.
- `main-interaction-result.txt`: 119 main-keyboard/control/layout checks, updated
  to expect real Japanese conversion and composition commit at language change.
- `input-session.txt`: 54 native input-session checks plus learning/runtime checks.
- `learning-upgrade.txt`: learn with the old checked-in bundle, then read the same
  user database using the new bundle in a separate process. Learned ranking survives.

Both the full app/extension Debug simulator build and unsigned Release iphoneos
build passed; `check-rime-bundle.py` verified exact resource hashes, static Rime,
privacy manifests, notices and RequestsOpenAccess=false for the Release app.
Signing, App Store review and physical-device extension footprint are not covered
by an unsigned Release build.
