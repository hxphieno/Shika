# 中文全拼与双拼纠错：实现前调研

日期：2026-09-25。范围是离线 iOS 键盘中的拼写容错，不包括文本语法改写。本报告先于生产纠错代码编写；临时实验只修改 `/tmp/shika-correction-research` 中的 bundle 副本。

## 结论

不能仅打开 `translator/enable_correction` 就宣布完成自动纠错。项目固定版本 librime 1.17.0 的有效实现只支持部分邻键替换；真实引擎实验也没有修复漏按、多按、换序。建议继续以 Rime 处理中文转换、分段和用户词学习，在共享 Swift 引擎层增加受限编辑距离候选检索，全拼和双拼使用各自编码索引。优先保护正确完整词、用户词和原始拼写；纠错通过候选和空格确认上屏，不擅自修改已上屏内容。

## 调研比较

| 方案 | 已核实机制与适用性 | 本项目选择 |
| --- | --- | --- |
| librime 原生纠错 | 固定版本 `CorrectorComponent::Create` 直接返回 `NearSearchCorrector`，编辑距离实现被 `#if 0` 排除。字母邻接表主要为 QWERTY 同行左右键。作用于 scheme prism，因此全拼和双拼都能启用，但不等于全面容错。 | 可作邻键能力参考，不能单独交付；需防止改变原有简拼首选。 |
| 雾凇拼音 rime-ice | 全拼 schema 使用显式拼写派生处理一批换序与缺音；源码同时注明会与全拼简拼混输冲突。双拼 schema 没有对应的一般编辑距离纠错层。`corrector.lua` 主要为错音错字提示，不能因名称判断它会修复任意按键错误。 | 学习“限制纠错范围、公开副作用”的方法，不整体复制 schema/Lua。 |
| 万象拼音 | 多方案共用词库、语法模型和 Lua 功能；当前 schema 的 native correction 为注释掉的 false，模型与上下文调频不是错键修复的同义词。 | 更大词库与语言模型可作后续质量提升，但本次不为开启纠错整体替换输入体系。 |
| Gboard 公开研究 | 将触点空间概率、语言概率与候选搜索结合；2024 论文研究用神经模型构建解码搜索空间。论文不是可直接引入的 iOS 中文双拼 SDK，也不能据此断言 iOS 当前实现完全相同。 | 借鉴错误成本与词频共同排序、控制搜索规模；不声称达到 Gboard 模型水平。 |
| 自建受限候选层 | 从现有授权词库生成全拼及双拼码串索引，支持一次替换、遗漏、插入、相邻交换，按错误成本与词频筛选。保留 Rime 会话作为最终转换与学习来源。 | 推荐本次实施，并以独立错误集、正确输入集及真键盘验证决定是否达标。 |

一手来源：

- [固定 librime corrector.cc](https://github.com/rime/librime/blob/33e78140250125871856cdc5b42ddc6a5fcd3cd4/src/rime/dict/corrector.cc)：实际启用的纠错器、键盘邻接表。
- [固定 librime syllabifier.cc](https://github.com/rime/librime/blob/33e78140250125871856cdc5b42ddc6a5fcd3cd4/src/rime/algo/syllabifier.cc)：纠错边的惩罚权重；[script_translator.cc](https://github.com/rime/librime/blob/33e78140250125871856cdc5b42ddc6a5fcd3cd4/src/rime/gear/script_translator.cc)：纠错候选数量限制以及用户词比较逻辑。
- [雾凇全拼 schema](https://github.com/iDvel/rime-ice/blob/main/rime_ice.schema.yaml#L336)、[双拼 schema](https://github.com/iDvel/rime-ice/blob/main/double_pinyin_flypy.schema.yaml)、[提示 Lua](https://github.com/iDvel/rime-ice/blob/main/lua/corrector.lua)。
- [万象 schema](https://github.com/amzxyz/rime-wanxiang/blob/wanxiang/wanxiang.schema.yaml#L114)、[方案转写](https://github.com/amzxyz/rime-wanxiang/blob/wanxiang/wanxiang_algebra.yaml)。
- [Google：The Machine Intelligence Behind Gboard](https://research.google/blog/the-machine-intelligence-behind-gboard/)、[Spatial model personalization in Gboard](https://research.google/pubs/spatial-model-personalization-in-gboard/)、[Neural Search Space in Gboard Decoder，EMNLP 2024](https://aclanthology.org/2024.emnlp-industry.93/)。

## 原生纠错开关的真实对照实验

使用项目 XCFramework 的 macOS slice，编译生产 `SKRimeSession.m`，两组全新 userdb，分别载入当前 bundle 与只增加 `enable_correction: true` 的 bundle 副本。每组 21 个码串；没有更换词库、学习测试答案或手写目标候选。

| 码串 | 基线首选 | 开启 native 后首选 | 解释 |
| --- | --- | --- | --- |
| 全拼 `nihao` | 你好 | 你好 | 正确码保留 |
| 全拼 `nohao` | 嗯哦好 | 你好 | 邻键替换有效 |
| 全拼 `zhonghuo` | 中或 | 中或 | 中国进入后续候选，合法拼写不能假设必错 |
| 全拼 `nihaoo` | 你好哦 | 你好哦 | 不自动消除多按 |
| 全拼 `zhnogguo` | 最后你哦各国 | 在乎你各国 | 换序没有修复为中国 |
| 全拼 `zhonguo` | 最后哦难过 | 中一 | 漏键没有修复为中国 |
| 全拼 `nhiao` | 你好 | 你叫 | 原有简拼/补全首选发生退化 |
| 双拼 `nihc` | 你好 | 你好 | 正确码保留 |
| 双拼 `nijc` | 嗯产从 | 你好 | 邻键替换有效 |
| 双拼 `niihc` | 嗯吃好 | 嗯吃好 | 多按没有恢复 |
| 双拼 `nhc` | 嗯好 | 嗯好 | 漏键没有恢复 |
| 双拼 `svgo` | 岁过 | 岁过 | 换序没有恢复 |

完整候选及单次耗时保存在 [关闭原生纠错](evidence/autocorrection-research/native-disabled.json) 和 [开启原生纠错](evidence/autocorrection-research/native-enabled.json)，实验源程序为 [probe.m](evidence/autocorrection-research/probe.m)。热查询整串约 0.2–2 ms 是这台 Mac 的小样本观察，不能作为 iPhone 延迟结论。

## 建议实现边界

1. 由现有词库和各方案真实映射生成码串索引。不要在 UI 层根据显示提示猜编码；所有双拼索引应随键位方案一起生成。
2. 检索一次编辑，四类错误分别报告结果。双拼码较短、有效码密度更高，不能把每个合法双拼码都强制改为更高频的邻近码。缺失尾字母也可能只是正在输入；短码要保守。
3. 保留完整精确词及用户词首选，再提供少量去重的纠错候选；没有可靠完整匹配时，可提升高置信度的纠错候选。词频只是先验，不能保证理解人名与上下文。使用按键相邻成本要包含上下行距离，不能照搬 native 的同行表。
4. 选中纠错候选后，以纠正后的码串送入 Rime 并选中对应文字，让学习落在正确拼音上。不要直接 `insertText` 丢掉学习，也不要把错误码写成词典规范拼音。部分选词、空格、翻页、删除、原码上屏需要保持一致。
5. 搜索要有码长、候选数量与计算量上限，按需初始化/缓存；每次按键扫描所有词条不是合适的最终实现。iOS 真扩展测延迟与内存，Mac 测试不能替代。
6. 本次支持拼写容错，不应宣称具备通用语法纠错、多处错键的任意长句恢复或 Gboard 等效语言模型。

## 验收建议

- 最少 320 组：全拼、双拼各 160，至少 100 错误、40 正确、20 边界；开发和保留验收集按原始词分开，防止同词不同错字泄漏。
- 错误组均衡覆盖邻键替换、漏按、多按、交换。包含日常词、名字、技术词、长短词；报告词库外目标与合法歧义码，不把这些困难样本删掉以抬高成绩。
- 分方案/错误类型报告首选、前三、首屏命中率及对照基线；“出现候选”与“空格自动上屏正确”分别计分。正确输入首选保留率、用户词保留与误干预率是独立门槛。
- 验证点击候选、空格确认、原码提交、连续输入、部分选词、删除、撤销/取消、方案切换、分页；每组核实最终汉字而不仅是引擎返回非空。
- 验证纠错选词能学习，重启保留；不输入测试答案来预热验收集。
- 建议质量目标：正确词首选零回退；四类错误均有明显改善；延迟 P95 在一帧至两帧量级内。若某类型或方案显著弱，应公开失败分布并继续调整，不能以平均数隐藏。

## 许可与依赖判断

现有 librime BSD 与 pinyin_simp Apache-2.0 保持不变。雾凇仓库是 [GPL-3.0](https://github.com/iDvel/rime-ice/blob/main/LICENSE)，本次只研究机制，不复制其脚本或成套配置。万象当前仓库 [CC-BY-4.0](https://github.com/amzxyz/rime-wanxiang/blob/wanxiang/LICENSE)；若未来引入，仍需逐项核对词库、模型和依赖的各自来源与声明。Gboard 论文只提供设计参考，不提供可复用的产品模型许可。本报告不构成 App Store 已批准的结论。
