# Offline lexicon sources

Pinned community data; no network request or deployment occurs in the keyboard.
`sources.lock.json` records repository revisions, original file sizes and Git blob
hashes. Archives are gzip-compressed, otherwise unmodified upstream files.

- **Chinese:** [Wanxiang](https://github.com/amzxyz/rime-wanxiang), by amzxyz and
  contributors, CC BY 4.0. Revision `516b1bb66bdce1fd5785f5481c415f13ff736548`.
  All 16 listed dictionary components are included, including base vocabulary,
  longer phrases, names, locations, science and other specialist terms. Shika
  removes tone marks (preserving ü as `v`), merges identical word/reading pairs by
  maximum frequency, and retains missing legacy AOSP entries at fallback weight 1.
  These transformations and compiled outputs are adaptations of the source data.
- **Japanese:** [Mozc OSS](https://github.com/google/mozc), revision
  `b9c3fcbd6d76b19649ef572324fa9da2559bc18e`. All ten OSS dictionary shards,
  connection costs and romaji rules are archived. Shika converts kana readings,
  word/POS/cost records and the connection matrix to mapped binary resources.
  Mixed-symbol/non-kana readings are excluded from the kana lookup index.
  This is the public OSS dataset, not Google's proprietary Japanese Input corpus.

See `LICENSE-Wanxiang.txt`, `LICENSE-Mozc.txt`, and
`LICENSE-Mozc-Dictionary.txt` for the applicable notices, including the Japanese
dictionary's IPADIC/NAIST/ICOT notices. These notices are also shipped in the app
and keyboard extension by `scripts/collect-rime-notices.py`.

## Rebuild / update

Run `bash scripts/build-rime-data.sh` from a normal macOS checkout with Xcode and
the pinned librime archive prepared. It rebuilds resources from the checked-in
compressed sources, without network access. `python3 scripts/prepare-lexicons.py
--fetch` restores missing archives from pinned official URLs and rejects hash
mismatches. Updating upstream requires updating the lock file and source archives,
rebuilding, and rerunning quality, spelling, learning-upgrade and runtime checks.
The generated Chinese YAML is ignored; the immutable archives and compiled
resources are tracked. The host build uses more memory than the runtime and must
never run inside the keyboard extension.

`lexicon-metadata.json` in RimeData.bundle records actual counts and output hashes.
Counts are distinct word/reading/POS records, not a claim of that many unique words
or exhaustive language coverage. The frequency threshold for typo proposals is
separate from normal conversion coverage; every compiled Chinese dictionary entry
remains available for correctly typed input.

## Mixed decoding and Japanese manual supplements (2026-09-26)

The Japanese build now also runs Mozc's pinned `gen_aux_dictionary.py` on the
complete official `dictionary_manual/words.tsv`, `places.tsv` and
`dictionary_oss/aux_dictionary.tsv`. The generator and its `id.def` are archived
and verified by Git blob hash in the same lock file. It uses upstream POS IDs,
median costs and auxiliary inheritance, skips existing entries, and adds **226**
new kana-keyed word/POS records (926 source rows are not 926 new words). Examples
include modern vocabulary such as サブスク and 推し事. All existing Mozc notices,
including the dictionary-specific terms in the full root LICENSE, still apply.

`python3 scripts/prepare-mixed-lexicon.py` builds `mixed-chinese.bin` from the same
normalized Wanxiang source. This separately mapped index exposes boundaries and
frequencies to the joint decoder; it does not replace Rime's complete dictionary
or alter pure-mode conversion. It bounds each reading to 12 homophones and codes
to 64 letters. Metadata records the actual output count, size and SHA-256. Runtime
search bounds and candidate ranking are separate from vocabulary coverage.

Network excerpts used for evaluation live only under Tests/Fixtures and docs.
They are not production lexicon entries or training data. No mixed test sentence
is imported into either production dictionary.

The separately maintained `japanese-modern-{words,aux}.tsv` adds ten source-backed
headwords from the publishers' 2025/2026 trend reports (for example メロい,
エッホエッホ, ぬい活). `japanese-modern-sources.json` records each source and date.
This small factual reading/headword compilation contains no article prose,
survey responses, mixed sentences or evaluation answers. Official POS median
costs are reused; the adjective inherits かわいい's POS with a +1500 cost offset.
After deduplication and POS expansion, official + modern supplements add **235**
records in total, rather than claiming comprehensive coverage of current slang.
