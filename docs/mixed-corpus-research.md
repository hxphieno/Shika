# 中日混输语料与日文增量词源调研

检索：2026-09-25—26。范围是可复用资源与可核对的网络表达，不是已完成的混输质量验收。推荐先完整导入与现有 Mozc 同快照的官方增量，再独立评测。词库规模不能替代跨语言切分与排序；这些资源也不是 Google 日语输入法的闭源 Web 词库。

## 1. 可直接落地的 Mozc 官方增量

锁定 `b9c3fcbd6d76b19649ef572324fa9da2559bc18e`，以下内容通过 GitHub contents API 实际下载、base64 解码后计数及 SHA-256；数据行不计注释/空行。

| 文件与固定下载地址 | 字节 / 数据行 | SHA-256 |
|---|---:|---|
| [manual/words.tsv](https://raw.githubusercontent.com/google/mozc/b9c3fcbd6d76b19649ef572324fa9da2559bc18e/src/data/dictionary_manual/words.tsv) | 32,041 / 766 | `e21b52a0bbb983906ee3a7767565087b950e5eb3f246c9a2f5431e643fd69ece` |
| [manual/places.tsv](https://raw.githubusercontent.com/google/mozc/b9c3fcbd6d76b19649ef572324fa9da2559bc18e/src/data/dictionary_manual/places.tsv) | 5,446 / 154 | `15cb5d42beb4a530f06599bc64e3a6e6cd11da61728fd0b81e618cef929c9d0e` |
| [oss/aux_dictionary.tsv](https://raw.githubusercontent.com/google/mozc/b9c3fcbd6d76b19649ef572324fa9da2559bc18e/src/data/dictionary_oss/aux_dictionary.tsv) | 444 / 6 | `8103d07c4eb18892282983299cbb20284a0f74bc596dda63831787b69aa7ce6c` |

共 926 个源条目，实际新增数须扣重复并计算 aux 对多个 POS 的展开。words 中实际存在 `さぶすく→サブスク`、`おしごと→推し事`、`ちゃっとじーぴーてぃー→ChatGPT`，也有历史人名等；不能宣称 926 条全是现代网络词，或这已是“最全日文词库”。不按测试目标挑词加入。

[官方 manual README](https://github.com/google/mozc/blob/master/src/data/dictionary_manual/README.md)说明这是主词典更新前的人工补充。manual 把 POS 转 ID，取同 POS 词成本的中间顺序值，已有相同条目跳过；aux 继承指定 base 的 lid/rid/cost 后加 offset。应复用[同快照生成器](https://raw.githubusercontent.com/google/mozc/b9c3fcbd6d76b19649ef572324fa9da2559bc18e/src/dictionary/gen_aux_dictionary.py)，避免凭空选 POS 或给新增词统一超低成本。

生成器只依赖 Python 标准库；`--aux_tsv`、`--words_tsv words.tsv places.tsv`、`--dictionary_txts dictionary00.txt … dictionary09.txt`、`--id_def id.def`、`--output out.txt`、`--strict`。POS aliases 已写在生成器内，参考[词典 id.def](https://raw.githubusercontent.com/google/mozc/b9c3fcbd6d76b19649ef572324fa9da2559bc18e/src/data/dictionary_oss/id.def)与[用户 POS 规则](https://raw.githubusercontent.com/google/mozc/b9c3fcbd6d76b19649ef572324fa9da2559bc18e/src/data/rules/user_pos.def)。其 cost 中位定义为排序索引 `int((n-1)*0.5)`，不是偶数集合两项平均值；manual 设 lid=rid=POS ID。

许可证核对：[固定快照根 LICENSE](https://github.com/google/mozc/blob/b9c3fcbd6d76b19649ef572324fa9da2559bc18e/LICENSE)的 `Files: src/data/dictionary*` 范围包括 NAIST/IPAdic、ICOT 与 Okinawa 公有领域说明，根部另含 Google BSD 条款；**不能把 manual 或整个词典统称纯 BSD**。保留完整 LICENSE 与 [dictionary_oss README.txt](https://github.com/google/mozc/blob/master/src/data/dictionary_oss/README.txt)。后者明确开源词典没有 Google 产品所用的大型 Web 词汇集。

## 2. 后续可选词源

| 来源 | 已核对的授权与内容 | 本项目取舍 |
|---|---|---|
| [NEologd](https://github.com/neologd/mecab-ipadic-neologd) | [COPYING](https://github.com/neologd/mecab-ipadic-neologd/blob/master/COPYING)声明 Apache-2.0，另列 Hatena、邮编、站名、人名等来源说明。 | 适合补专名/新词，不是完整输入法。保存完整来源说明；MeCab 的 POS ID、cost 不能直接当 Mozc 的值。 |
| [NEologd releases](https://github.com/neologd/mecab-ipadic-neologd/releases) | 页面列出的 v0.0.7 固定 seed 为 2020-08-20；维护者说明 release seed 不更新，master 另行更新。 | 不把旧 tag 称为“最新”。真正引入前重新锁定 seed 日期、commit、解压条数、hash，评估专名噪声与体积。此次没有下载 NEologd 全量。 |
| [SudachiDict](https://github.com/WorksApplications/SudachiDict) | [LEGAL](https://github.com/WorksApplications/SudachiDict/blob/develop/LEGAL)声明 Apache-2.0，并列出 UniDic BSD、NEologd notice；small/core/full 的词汇范围不同。 | 可补现代词/专名；需单独锁定源 CSV 版本。此为形态分析词典，不能直接导入它的二进制或连接矩阵替换 Mozc。此次未认证某一个“最新发布包”。 |
| 中文维基百科中的中日表达 | 页尾明确 CC BY-SA 4.0，留固定修订链接、作者历史与协议。 | 优先用于可复现的来源摘录；百科解释体偏多，不是聊天统计模型。引用改编保留署名、修改标记及相同方式共享要求。 |

“现代”应通过实际词汇覆盖和固定版本日期说明；没有查到一个可直接宣称最新、最全、又适用于 iOS 混输的统一词库。以上开源授权不意味着自动保证 App Store 审核通过。

## 3. 已核对的中文上下文夹日文原文

以下是短摘录，不是完整原句，保持原字形及标点。每个普通网页仅取一个短片段、少于 25 个字符；不抓整篇文章。机器可读记录位于 `Tests/Fixtures/mixed-source-excerpts.json`。未显示出版日期的记为未知，不能拿搜索抓取时间当出版日期。

| 来源 ID | 短摘录 | 出处 / 日期 / 权利状态 |
|---|---|---|
| wiki-oshi | 推（日語：推し）是一個日語俚語 | [维基百科固定修订](https://zh.wikipedia.org/w/index.php?title=推_(日本)&oldid=94184542)，最后修订 2026-09-04；CC BY-SA 4.0 |
| wiki-kawaii | 「可愛い」已經成為日本文化的重要要素 | [维基百科固定修订](https://zh.wikipedia.org/w/index.php?title=卡哇伊&oldid=94317212)，出版日期未知；CC BY-SA 4.0 |
| wiki-otaku | 在日语原文“おたく”中 | [维基百科固定修订](https://zh.wikipedia.org/w/index.php?title=御宅族&oldid=94479472)，出版日期未知；CC BY-SA 4.0 |
| fun-oshi | 「我推（推し）」是指自己最支持的對象 | [FUN! JAPAN](https://www.fun-japan.jp/hk/articles/14014)，刊登 2025-03-17 / 更新 2025-04-02；未见开放转载授权 |
| hikky-sns | 或是令人煩惱的「已讀不回（既読スルー）」 | [小狸日语](https://japanese.hikky.com.tw/japanese-sns-japanese-slang-current-events/)，页面日期 2022-11-05；All rights reserved |
| culture-otsukare | 也可以直接打「お疲れ様です」，超實用。 | [星颗日本](https://www.j-culturearc.com/japanese-otsukaresama/)，2025-03-29 / 更新 2026-01-30；未见开放转载授权 |
| matcha-nostalgia | 就会充分感受到浓浓的“懐かしい”氛围。 | [MATCHA](https://matcha-jp.com/cn/3709)，出版日期未知；页面 Copyright MATCHA |
| shoshin-greeting | 不要每次都是こんにちは。 | [初声日语署名文章](https://www.sohu.com/a/575847879_798834)，2022-08-11；未见开放转载授权 |

普通网页片段只作为出处核对和研究引用，**不授权将整篇文章或摘录批量导入生产语言模型**。维基材料按 [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/deed.zh-hans)保留出处和改动说明；本报告中的百科摘录属于短节选，文字未改写。

这些页面证明中文写作中保留日文原词确实存在，但大部分是教学/文化解释，不能代表用户聊天分布。搜索曾返回 Reddit 混语评论，但正文页未能打开，故未把它们列为已核对原句。早稻田学院页面的搜索摘要看似中文正文，打开却主要是日文，故也未纳入。

## 4. 至少 200 项的可重复验收策略

明确区分三种来源：`verbatim_excerpt`（上述真实短摘）、`source_vocabulary_adaptation`（利用公开词源创作的新句）、`interaction_trace`（按键/选择/删除的行为测试）。八条摘录不应包装成 200 条自然语料。

建议冻结 **200 个不同目标表达**，另跑交互断言，不用重复标点/相同句子换前缀凑数：

- 80 条中文→日文，覆盖问候、日常、饮食、交通、科技、娱乐、购物、职场八类，每类至少 10 个不同日文核心词；所有词记录来源，句子由测试作者独立写。
- 50 条日文→中文，使用不同谓语/名词，不只倒置前组字符串。
- 50 条中文→日文→中文，覆盖中间插词、短语与完整日语从句，输出长度至少分 4–8、9–16、17–32 字三档。
- 20 条多次切换/歧义对照，重点测两套罗马编码共享前缀、`n`、促音、拗音、长音与中文合法拼音冲突；不要只优化单个展示例。

生成方式是结构化 `segments: [{lang, input, expected}]` 拼接输入与目标；按来源词源分组固定 train/dev/heldout，人工审阅读音和语义，再生成用例。中文简繁转换或日文读音转罗马字均属改编；读音不猜测多音汉字。预期显示假名/汉字允许候选集合，但集合在跑分前冻结。不能先选答案训练用户词频再跑排名，也不能把整句答案写入生产词典。

分别报告：总数与独立核心词数、逐类 Top1/5/10 与 MRR、全输入消费率、逐段目标路径召回、跨界错误切分率、按键 p50/p95、冷启动与连续输入峰值内存。纯中文/日文对照测模式污染；混句必须真实调用 mixed 模式，不拿两套单语结果并集充当混输成功。

交互检查独立计数：候选提交确实输出完整混句；删除与继续输入重新解码；用户当前约定原始罗马字预编辑/Return 保留；选段后继续输入不丢字/重复；换模式、清空和新会话无残留；展开候选与选择路由正确。长输入超预算必须可观察地降级，不能靠截断目标冒充全句命中。

此处是研究与验收设计，不声称 200 项已生成或测试通过；实施后的原始结果、失败样例和限制应另存独立报告。

## 5. 2026-09-26 后续冻结的质量集

前节描述的是研究时的计划；现已新增 `Tests/MixedEngineCases.json` 和可复现生成器 `scripts/generate-mixed-quality-fixture.py`。**仅生成及静态核对，尚未调用引擎或查看 probe 排名。**

- 250 项：249 个不同目标表达，加 1 个同目标故意错拼开发用例。输入字符串全部唯一。
- 188 条干净混输：中文→日文 44、日文→中文 80、中→日→中 36、多次切换 20、网络短摘改编 8；另外 2 条开发探针。其中 186 条干净混语结果含假名或片假名，另外 2 条以日文罗马字输入汉字词（开发探针另计）。
- 纯中文、纯日文对照各 30 条；开发 52 条、heldout 198 条，按日文核心词族分组无交叉（可愛い与かわいい按同族处理）。核心词族 83 个。57 条输入使用日文长音符号 `-`，须单独报告长音覆盖，不能将正确读音改成别的读音迁就引擎。
- 两个表达使用同一日文核心词，但中文情境、谓语和语序不同。没有把 188 条称作 188 条真实聊天：只有 8 条可回溯网络短摘，且进 fixture 时已去标点、中文简化及添加罗马编码，明确是 `source_excerpt_adaptation`。
- 作者按饮食、出行、生活、科技、社群、娱乐、职场及问候设计文本，许多是假定中日双语用户的夹词表达，尚非真实用户分布抽样。读音手工写定，常见汉字/假名变体在测前列入 `expected`，不是跑出结果之后扩充答案。
- 原始 Mozc 词表只用于核对词汇出处，不执行引擎。未在原始十个分卷找到完整 `お疲れ様です` / `よろしくお願いします` 不等于单词不存在：前者有已核网页出处，后者有官方 aux；`ガチャ` 另以[日文词汇页面](https://ja.wikipedia.org/wiki/ガチャ)核对，不能据此给生产词典单独加测试词。
- 冻结 SHA-256：`23b780fc9562d7707e11696262caa987ad05a00e1c9f236b92cadba8a1d9e6fa`。调参只用 `split=development`；最终一次性评测 heldout 并保留失败。修复 fixture 中可证实的标注错误须记录旧 hash、具体原因，再发布新版本，不能静默改答案。

静态检查已验证 JSON、ID/输入唯一、249 个不同干净目标、输入字符集、segments 拼接、全部 sourceIDs 可解析、核心词族无 split 交叉。此冻结动作不意味着任何一项已通过真实输入法测试。

### 冻结版 v2：静态转写勘误

2026-09-26，在保留集首次引擎评测之前，仅按目标文本的规范读音复核。旧 SHA-256 `23b780fc9562d7707e11696262caa987ad05a00e1c9f236b92cadba8a1d9e6fa` → 新 SHA-256 `995730125c309ac2138ec06c7222d6037b0bc8f191c69c7c232e6d60f24e3480`，fixture 增加 `fixtureRevision: 2`。

| ID | 转写修正 | 独立语音依据 |
|---|---|---|
| mix-010-2（开发） | `zheduanfan` → `zhedunfan` | “这顿饭”的顿读 dùn，原输入多了 a。 |
| mix-012-2（开发） | `wohaneng` → `wohaineng` | “我还能”的还读 hái，原输入漏了 i。 |
| mix-018-2（开发） | `dezaikan` → `deizaikan` | “得再看一遍”是“必须”的口语义，读 děi，不是结构助词 de。 |
| mix-078-2（保留） | `chaokai` → `chaikai` | “拆开”的拆读 chāi，原输入将 i 写成 o。 |
| multi-016（保留） | `ke-ki-` → `ke-ki` | ケーキ只有第一个长音，结尾キ不带长音；与同词的其余标注一致。 |

复核方法：人工阅读生成器全部中文片段；以 Foundation 文本转写列出差异进行人工复核；检查同一日文表记是否存在不同编码。Foundation 只用于发现线索，**未调用 Rime / SKJapaneseEngine / SKConversionEngine 或读取任何引擎候选**；其“重启/重置/重新/重复”“地方”“不了”“旅行”“着急”等多音字/ü 转写不符合这些句子的读音，均保留原人工正确编码，不机械接受。

机械差异核对确认：恰好 5 项只修改 `input` 及对应 `segments.input`；所有目标、可接受表记、ID、顺序和 split 均不变。总量仍 250，输入唯一及日文核心词族不跨 split 检查通过。故意的 `arigadou` 开发错拼保留。v2 可以进入最终引擎评测；修正不是据候选输出放宽目标。
