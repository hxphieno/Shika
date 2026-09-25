# Independent canonical-equivalence cache regression

The static lexicon compares raw UTF-8 keys. Swift String dictionary equality treats canonically equivalent composed/decomposed strings as the same key, so the initial String-key cache violated the pre-existing byte-sensitive conversion contract.

Five pairs tested: ば/は+U+3099, ぱ/は+U+309A, が/か+U+3099, ざ/さ+U+3099, ゔ/う+U+3099. Every pair was converted in independent fresh instances and both same-instance orders. Candidate arrays were compared as arrays of UTF-8 bytes, not Swift String equality.

Baseline without cache: 15/15. Initial String-key cache: 5/15 (both cross-form warm-cache orders fail for all five pairs). Final Data-key cache: 15/15. Example: fresh composed ば yields 13 candidates including 場 and 馬; decomposed form yields only the original decomposed kana and its katakana fallback. Initial cache made results depend on the prior spelling's byte normalization.

The 312 current romaji mapping entries contain zero non-NFC output strings, verified byte by byte against canonical precomposition. This establishes an internal convert API boundary regression, not a reproduced normal keyboard-input failure. The fix preserves existing raw-byte semantics and does not normalize input or change dictionary behavior.

The standalone runner uses the production lexicon source unchanged plus a minimal declaration of its initialization error constant; it mocks neither dictionary data nor conversion. Full engine learning/cache tests are separately compiled with the actual production engine and Rime bridge.
