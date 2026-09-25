# Frozen lexical quality protocol

The independent test agent wrote the corpus before production changes and ran baseline against a frozen copy of the original source and Rime bundle. Corpus answers are evaluation data only; they must not be copied into production dictionaries. `baseline/revision.txt`, `source-hashes.txt`, and `resource-hashes.txt` identify the baseline. No production files were modified by the test agent.

- `Tests/LexiconQualityCases.json`: 172 Chinese targets: 100 ordinary/technical words, 40 longer phrases, 20 sentences, and 12 ambiguity targets. The full-pinyin scheme and real `shuangpin-layout.json` mapping are evaluated (344 baseline ranking cases); final verification also evaluates the actual mixed-language configuration, for 516 final ranking cases.
- Ambiguity pairs are 西安/先, 方案/反感, 档案/胆敢, 皮袄/飘, 激昂/将, and 企鹅/切. Each pair has identical concatenated full pinyin but different syllable boundaries. Double pinyin naturally distinguishes some pairs and is reported separately, not claimed to be equally ambiguous.
- `Tests/LexiconQualityJapaneseCases.json`: 40 prepared Japanese lexical/phrase/sentence targets. These initially prepared targets subsequently ran against the production Japanese engine; results and a final source/resource identity check are in `japanese/`.

## Reproduction

`scripts/test-lexicon-quality.sh docs/evidence/lexicon-quality/after`

Optional second argument supplies the frozen baseline source/resource directory. The script copies sources, dictionary resources and test data before compiling, then uses the actual `SKRimeEngine`, correction wrapper, native Rime bridge, and vendor librime. Ranking uses a fresh user directory for each schema, clears composition between cases, and never selects a candidate or supplies an expected answer to Rime. Long-sentence coverage runs each sentence in its own fresh process and user directory, selects only the displayed first candidate and observes the committed output and remaining input. The coverage runs cannot train ranking or other coverage cases.

## Metrics

- Top1/5/10: fraction whose exact intended string appears within that many displayed candidates. MRR10 is reciprocal rank up to ten, with zero for a miss. Strings are not normalized to turn a wrong character into a pass.
- Sentence exact-match is reported separately from full-input consumption: emitting any whole sentence is not sufficient to claim the intended sentence was generated.
- Ambiguity pair coverage requires both target strings in the top ten for the same raw full-pinyin input.
- Key p50/p95 uses monotonic elapsed time around actual engine processing for every key. Cold engine startup is separate. These figures are single-run comparative diagnostics, not statistically stable UI-frame measurements.
- Process peak resident memory is macOS `getrusage` high-water RSS, in MiB. It is not iOS keyboard-extension physical footprint and must not be presented as proof that iOS memory limits are met.
- Unexpected commits during ranking must remain zero.

A larger dictionary is not assumed to be better. Report regressions as well as aggregate gains, with latency/memory cost. Common words yield a high existing baseline and cannot establish coverage of all modern words. The 172 targets provide reproducible comparative evidence, not an exhaustive language evaluation. `LexiconQualityAmbiguityCases.json` adds a separately fixed 48-target/24-pair boundary corpus for query-budget comparisons. `scripts/test-lexicon-parameters.sh` copies production sources and modifies only temporary snapshots to test query limits 0, 1, and 3. Candidate pagination beyond the initial ten is not credited toward Top10.
