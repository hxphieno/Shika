# 第二轮底层优化：独立实验与验收

## 长句参数实验：放弃该改动

2026-09-26，源码固定为 `c885466`；只在 `/tmp/shika-backend-r2-sentences/` 的复制资源中，把两套主方案的 `translator/sentence_cutoff_threshold` 从 0.01 调到 0.05。未改生产源码、词典、UI、按键或辅助纠错 schema。结果没有提升新句子命中，且降低已有开发集 Top5，因此不应合入。没有根据结果换目标或继续挑参数。

### 参数是否依赖 Octagram

librime 1.17.0 中，`max_sentences`、`sentence_cutoff_threshold`、`max_homophones` 在没有加载 Octagram 模型时也参与运行：

- `ScriptTranslation` 在适用的组句路径按 `max_sentences` 选择单句或多句生成；不是以 grammar 是否存在为前提。[官方 ScriptTranslator](https://github.com/rime/librime/blob/1.17.0/src/rime/gear/script_translator.cc)
- 多句路径 `Poet::MakeSentences` 使用 `max_sentences * 3` 的 beam；相邻句权重差受 cutoff 约束。单句路径才按 grammar 是否存在选择 beam 或动态规划。[官方 Poet](https://github.com/rime/librime/blob/1.17.0/src/rime/gear/poet.cc)
- `Grammar::Evaluate` 明确支持空 grammar，此时使用固定惩罚和词条权重；所以调用 grammar 的评估函数不等于必须装语言模型。[官方 Grammar](https://github.com/rime/librime/blob/1.17.0/src/rime/gear/grammar.h)
- `max_homophones` 限制组句图中每条词边的同音词数；并非全局候选页上限。配置项读入位于 [TranslatorOptions](https://github.com/rime/librime/blob/1.17.0/src/rime/gear/translator_commons.cc) 和上述 ScriptTranslator。

独立 `Tests/BackendRound2ConfigurationProbe.m` 从实际 Rime API 读取运行配置，确认版本 1.17.0、两主方案 cutoff 为 0.01 / 0.05，且 `max_sentences=5`、`max_homophones=8` 未变；辅助方案仍为 0.01。资源逐文件 SHA 比对仅两份 compiled schema YAML 不同。这里仅改运行时标量，未重建词典或 prism。

### 预先冻结的方法

`Tests/BackendRound2SentenceCases.json` SHA256：`44a3f0e80cdd7e1ce8ad756771b317c8477210a1e5ca677123a28a5365182a79`。

共 336 条：原双拼开发集 132 条、对应全拼开发集 132 条，以及运行前独立撰写的 36 个新句子 × 两方案。新句目标与已有 Tests JSON 目标去重；每句有人工指定拼音，并附两个来自固定 Wanxiang jichu 词典版本的词汇锚点（URL、Git blob、行号、频率）。这是有来源词汇组合成的人工语料，不是自然用户分布，也没有向字典添加目标。新句只测试正确编码；含错码的覆盖来自原开发集。

`Tests/BackendRound2SentenceChecks.swift` 使用真实 ObjC 桥接、Swift 引擎与静态 librime；按 c885466 导出源码后 `-O -whole-module-optimization` 编译。两轮顺序执行、各用新用户目录。排名过程中只输入、浏览及取消，不选择答案、不训练目标。完整候选要求匹配原生 comment 编码覆盖（或完整纠错路由）；不能仅按候选文字把部分词当整句命中。计时使用单调时钟。并另起每个 case 独立进程检验提交，提交学习不污染排名。

### 结果

| 集合 / 方案 | 数量 | Top1 前→后 | Top5 前→后 | Top10 前→后 | 可见完整目标前→后 |
|---|---:|---:|---:|---:|---:|
| 原开发 / 双拼 | 132 | 50→50 | 84→78 | 90→89 | 92→92 |
| 原开发 / 全拼 | 132 | 55→55 | 84→77 | 89→89 | 90→90 |
| 新句 / 双拼 | 36 | 22→22 | 30→30 | 30→30 | 30→30 |
| 新句 / 全拼 | 36 | 22→22 | 30→30 | 30→30 | 30→30 |

336 条首选均不变；134 条候选列表改变，17 条目标排名下降、无目标排名改善。例：双拼“牛奶”替换错码由第 2 到第 6，全拼“词频”多键错码由第 3 到第 6。较宽的组句保留阈值让更多整句占据靠前位置，后排纠错目标因此后移；这说明“更多句子”不能直接视为更好输入体验。

新句两方案中所有 60 个完整命中，在 baseline 和 variant 分别以新进程选择，均 **60/60** 正确提交，输入/preedit/候选清空，再次 commit 不重复上屏。两轮共 672 条排名输入没有意外提交。

| 原生 macOS 单轮成本 | baseline | cutoff 0.05 |
|---|---:|---:|
| 逐键 P50 | 0.589 ms | 0.543 ms |
| 逐键 P95 | 3.501 ms | 3.371 ms |
| 逐键 P99 | 6.505 ms | 6.482 ms |
| 冷初始化 | 50.819 ms | 44.060 ms |
| 峰值 RSS | 93,847,552 B | 93,716,480 B |
| 新句选择提交 P50 | 5.067 ms | 5.229 ms |
| 新句选择提交 P95 | 6.275 ms | 6.351 ms |

排名成本在协调的无其他 agent 基准负载窗口执行；提交回放不属于该静稳窗口。单轮测量不足以声称性能提升，且这是 macOS 原生进程，不是 iOS 扩展或真机。质量回退已足以否决参数改动。

完整可复核产物：`/tmp/shika-backend-r2-sentences/{baseline,variant,summary,commit-summary,config-baseline,config-variant,resource-diff}.json`、`source-hashes.txt`、冻结 sources、两个资源副本与 runner。此临时目录不保证长期保留；关键结论、fixture 和可重编译的测试源码已保存在仓库。

## 全拼已学新词纠错：通过，保留新增能力

这部分独立冻结 `Tests/BackendRound2LearnedPhrases.json`，SHA256 `d8182748a9187cebfc53e5d24b254befba0a9f47f63a40566f923bbb67445393`。八个人工组合为“猫云灯、鹿茶钟、鱼书门、山杯月、雨鞋星、竹糖鸟、花桌云、风猫桥”，逐行确认目标不在现有 Vendor 中文源词典中。每个目标人工指定完整拼音，再固定替换、漏末键、首键重复、首两键交换四种变换；没有观察输出后改词或错码。它们只用于学习机制验收，不代表自然词频或纠错准确率。

使用 `Tests/BackendRound2LearningChecks.swift`，所有学习都通过真实候选选择（首次通常逐字选，已存在整句时直接选），每词五次；没有直接修改 userdb。学习与重启探测是不同进程，探测阶段先把所有 32 个错码的状态收集完，再开始选词，避免用已选过的错码训练后续排名。

同一组目标和错码对比 c885466：

| 验收项 | c885466 | 最终实现 |
|---|---:|---:|
| 五次选择后，重启精确输入为首选 | 8/8 | 8/8 |
| 32 个错码出现同字面候选 | 1/32 | 32/32 |
| 32 个错码可正确完整上屏并清空 | 0/32 | 32/32 |
| 替换 / 漏键 / 多键 / 交换完整恢复 | 0 / 0 / 0 / 0 | 8 / 8 / 8 / 8 |

基线唯一同字面候选是 `luchazhon` 的“鹿茶钟”：原生 comment 为 `lu cha zhong`，preedit 为 `lu cha z h o n`；选择后输出仍为空、原输入仍在。它是部分候选，不应被计作一次完整错拼恢复。新路径完整消费错码，并保留真实正确 code 的 metadata；所有 32 次选择后再次 commit 都不重复输出。

最终独立测试 **238/238**：学习/行为 99、跨进程恢复及完整提交 115、关闭纠错 16、metadata 边界 8。覆盖：

- 输入、翻页、取消、原码 Return、显式原码提交、部分选择不写学习 metadata；`nh→你好` 和长度已达门槛的 `zgrm→中国人民` 简拼仍能用，但不作为完整拼音记录。
- 部分选择后第一次删除恢复全部原码；Return 保留每个原始字母；已学词 Return 仍然输出原字母。
- 全拼与双拼独立文件、切换不污染；`correctionEnabled=false` 不创建任何纠错 metadata，Rime 原生精确学习仍可用。
- 损坏和超大 JSON 安全忽略，正确记录可修复损坏文件；写入只包含 code/text，没有第二套频率。
- 最终源与工作区生产文件逐字节一致。另跑原有 **117/117** 双拼测试（70 行为、13 学习、19 重启、15 索引）全部通过，原来三种替换错码断言保持。

### 独立发现并修复的容量问题

首次索引测试 **6/8**，并非全通过：全拼原校验接受 48 字母 code 和 48 个四字节扩展区汉字，512 条 JSON 达 **134,145 bytes**，超过自身 **131,072 bytes** 的加载上限，重启丢弃整份索引。独立报告后，生产实现增加写入前按字节淘汰最旧条目，仍保持最多 512 条。修复后同一极端构造保留最新 **500 条 / 131,001 bytes**，重启能恢复最新记录，最终 **8/8**。

数量断言按原本“至多 512”的资源约束修正为：保留连续的最新后缀、数量不超过 512、文件不超过 128 KiB、重启保留最新值。没有删除失败样例。原失败日志在 `/tmp/shika-backend-r2-learning/index.{json,log}`；最终在 `/tmp/shika-backend-r2-learning-final/`。这属于类的有效输入边界测试，不声称自然使用会形成这些人工词。

### 成本与实际边界

主 agent 的固定词选择成本实验（我只读核对 JSON 和计算，未在独立进程重测其计时）每版本 120 次双拼 + 120 次全拼均无失败。全拼 commit P95 **0.024166→1.288042 ms**，增加 **1.263876 ms**；双拼 **1.208959→1.255375 ms**。全拼增加来自完整提交后的原生 code/text 校验与 metadata 写入，符合主 agent 预先声明的增量不超过 2 ms、总 P95 不超过 10 ms 门槛。RSS **42,303,488→43,089,920 bytes**。这是 macOS 原生固定小词集、优化构建、重复选择，不能外推为 iOS 扩展或大规模真实词汇的成本。该计时发生在字节预算修复前，摘要已明确标注；六个短词不触及字节上限。最终 238/117 功能验收包含修复，但这里不把早期计时宣称为最终源码哈希的重新测量。

功能边界仍为单次编辑、最多 512 条且 128 KiB、每次有限候选、必须经 Rime 完整 code/text 再确认。它补足的是已实际选过的全拼词的错拼恢复，不是新增语言模型，也不保证任意陌生句子的正确首选。

## 双拼拼写搜索剪枝：等价证据通过

只读审查 `SKSpellingCorrector`：双拼词典编码由完整两键音节组成，旧 `add` 本来就拒绝奇数长度。新逻辑在创建数组前跳过不可能改变此结论的编辑分支：偶数输入只做替换/交换，奇数输入只做增删；全拼两类分支都保留。没有改变成本、键邻接距离、候选评分、排序、缓存或学习状态。工作区相对 c885466 的键盘生产改动仅三个 Engine 文件；键盘 Core、Schemes 和 UI 无差异。

独立读取并逐项比较 `docs/evidence/backend-round2/search/equivalence-{before,after}.json.gz`，**2,629 个唯一 schema/input、46,358 条有序 code/text/cost/frequency 签名完全相同**；前缀与立即重输都比较了。summary 的两版 timing 聚合和三份源码 SHA 与原报告/文件完全相符。性能 runner 使用 `DispatchTime.uptimeNanoseconds`，每词创建新 corrector、遍历前缀再立即重输，跑三轮；所以衡量的是静态拼写查询，不包含 Rime、构造索引、候选展示或用户操作。

该三轮双拼冷查询累计 **2,566.769→1,980.999 ms（-22.82%）**，P95 **0.188417→0.174875 ms**。全拼路径没有改变，累计时间约 -1.26% 应视作测量波动。两字母/一字母前缀范围实验的无稳定收益记录仍保留，未被混作保留成果。

最终生产源关键 SHA256：

- `SKRimeEngine.swift`：`e9550fb6b2909dfbe44ea98d13fd3764a891e02968d806b018f593c243cd2162`
- `SKLearnedSpellingIndex.swift`：`bc0528e3f81b5a0f05e9e204b44485441eeaac89a5756cb4b47d8d0e3212bd90`
- `SKSpellingCorrector.swift`：`aa6f201f53f7920cf0b1d0743f94c6d66bb9bb8332e2474ff7a4af140769ff2f`

全拼最终冻结、源码清单与四模式报告位于 `/tmp/shika-backend-r2-learning-final/`；同 fixture 基线位于 `/tmp/shika-backend-r2-learning-baseline/`；双拼最终四模式报告与源码清单位于 `/tmp/shika-backend-r2-double-final/`。主 agent 的 iOS 控制器/UITextView 测试和真机构建属于另一路验证，不在上述原生检查数字之内。

反向顺序补充：主 agent 随后以新→旧顺序在同一冻结集合的 1,542 条双拼输入上重跑，我逐项核对 **22,886 条签名仍完全相同**；summary 与原两份结果一致。冷查询累计新 **2,078.042 ms**、旧 **2,503.473 ms**（新少约 17.0%），P95 新 **0.173792 ms**、旧 **0.190458 ms**。两个顺序都支持此处静态查询成本下降，仍不能写作“整个键盘快 17%–23%”。证据：[反向摘要](evidence/backend-round2/search/reverse-summary.json)、[新结果](evidence/backend-round2/search/reverse-after.json.gz)、[旧结果](evidence/backend-round2/search/reverse-before.json.gz)。

## 仓库证据索引

关键原始结果已归档，不依赖 `/tmp` 长期存在：

- [全部独立产物 SHA256](evidence/backend-round2/independent/artifact-hashes.json)。压缩文件为标准 gzip JSON；可用 `gzip -dc 文件.json.gz` 查看。
- 长句：[baseline](evidence/backend-round2/independent/sentences/baseline.json.gz)、[variant](evidence/backend-round2/independent/sentences/variant.json.gz)、[比较摘要](evidence/backend-round2/independent/sentences/summary.json)、[原生配置前](evidence/backend-round2/independent/sentences/config-baseline.json)/[后](evidence/backend-round2/independent/sentences/config-variant.json)、[资源 SHA](evidence/backend-round2/independent/sentences/resource-hashes.json)、[源码 SHA](evidence/backend-round2/independent/sentences/source-hashes.txt)。
- 长句完整命中的各自独立进程提交：[baseline 60 次](evidence/backend-round2/independent/sentences/commits-baseline.json.gz)、[variant 60 次](evidence/backend-round2/independent/sentences/commits-variant.json.gz)、[成本摘要](evidence/backend-round2/independent/sentences/commit-summary.json)。
- 全拼基线：[学习](evidence/backend-round2/independent/learning-baseline/learn.json.gz)、[重启探测和提交](evidence/backend-round2/independent/learning-baseline/probe.json.gz)、[源码 SHA](evidence/backend-round2/independent/learning-baseline/source-hashes.txt)。基线用来量化缺失功能，故针对新功能的断言预期失败，不能误称为最终生产失败。
- 全拼最终：[学习 99](evidence/backend-round2/independent/learning-final/learn.json.gz)、[重启及提交 115](evidence/backend-round2/independent/learning-final/probe.json.gz)、[disabled 16](evidence/backend-round2/independent/learning-final/disabled.json.gz)、[边界 8](evidence/backend-round2/independent/learning-final/index.json.gz)、[源码 SHA](evidence/backend-round2/independent/learning-final/source-hashes.txt)。
- 首次容量失败：[原 6/8 报告](evidence/backend-round2/independent/first-capacity-failure/index.json)、[原实现快照](evidence/backend-round2/independent/first-capacity-failure/SKLearnedSpellingIndex.swift.txt)、[原断言快照](evidence/backend-round2/independent/first-capacity-failure/BackendRound2LearningChecks.swift.txt)、[源码 SHA](evidence/backend-round2/independent/first-capacity-failure/source-hashes.txt)。
- 双拼最终：[行为 70](evidence/backend-round2/independent/shuangpin-final/behavior.json.gz)、[学习 13](evidence/backend-round2/independent/shuangpin-final/learn.json.gz)、[重启 19](evidence/backend-round2/independent/shuangpin-final/probe.json.gz)、[索引 15](evidence/backend-round2/independent/shuangpin-final/index.json.gz)、[源码 SHA](evidence/backend-round2/independent/shuangpin-final/source-hashes.txt)。
- 主 agent 选择成本：[before](evidence/backend-round2/commit-cost/before.json)、[after](evidence/backend-round2/commit-cost/after.json)、[摘要](evidence/backend-round2/commit-cost/summary.json)；静态搜索：[主顺序摘要](evidence/backend-round2/search/summary.json)。
