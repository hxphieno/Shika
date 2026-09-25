# 中文／日文出词优化（2026-09-25）

这次以实际出词质量、分词覆盖、上屏正确性和运行成本决定方案，不把词条数量当成唯一指标。`sihua → 丝滑` 是缺词的复现例；没有将验收答案写入词库或为 `shuna` 添加特例。

## 社区方案和取舍

| 来源 | 调研结果 | 本次选择 |
|---|---|---|
| [Rime Ice](https://github.com/iDvel/rime-ice) | 持续维护的通用中文方案，多层词库、常用设置较完整；仓库 GPL-3.0 | 对照调研，没有复制配置／代码 |
| [万象](https://github.com/amzxyz/rime-wanxiang) | 分层中文词库，含常用词、长词、人名地名和专门领域；CC BY 4.0 | 使用锁定版本的全部 16 个词库组件，保留权重并附署名、许可证和转换说明 |
| [RIME-LMDG](https://github.com/amzxyz/RIME-LMDG) | 提供整句语言模型；调研时 LTS 简体模型约 400.5 MiB | 本次未附带该大型模型。先使用 Rime 自带词图、多句搜索与词频，避免把数百 MB 模型未经验证地塞进扩展 |
| [rime-japanese](https://github.com/gkovacs/rime-japanese) | 可参考罗马字／日文词典组织；仓库维护和授权信息不足以直接整套引入 | 未直接复用其实现 |
| [rime-kagiroi](https://github.com/rimeinn/rime-kagiroi) | Mozc 数据、词连接和 Viterbi 思路，依赖 Lua，代码 GPL-3.0 | 参考方向，不复制其代码／配置 |
| [Mozc OSS](https://github.com/google/mozc) | 开放的日文读音、词性、词成本和词间连接数据 | 直接使用官方 OSS 数据和罗马字表，自有 Swift 有界解码器；附 BSD 及词典专门许可 |

“最新最全”无法客观保证：最新词库也会缺新词，专业词／人名的增加还可能干扰日常排序。本次固定的是 2026-09-24 的万象、2026-09-25 的 Mozc 快照；准确提交、每个原始文件的 Git blob 校验值和授权文件见 [Vendor/Lexicons](../Vendor/Lexicons/README.md)。没有使用 Google 日语输入法的私有语料。

## 引擎与数据

中文由原来约 6.5 万条扩为 **2,203,505 条词／读音记录**，其中 1,292,496 条有四个或更多音节。日文索引含 **1,281,498 条词／读音／词性记录**、744,228 个读音。不同读音、词性可能对应同一个词，不能把这些数字解释成独立词的数量。

中文全拼和双拼共用完整词库、用户词频和 Rime 句子生成，分别使用自己的拼写映射。`user_dict: pinyin_simp` 保留原有用户数据库名称；跨升级的学习持久化另有回归测试。字母键位保持原方案，419 个音节的双拼主码与原独立参考校验一致。

[Rime 1.17 的 translator 选项](https://github.com/rime/librime/blob/1.17.0/src/rime/gear/translator_commons.cc) 支持多句搜索；[script translator](https://github.com/rime/librime/blob/1.17.0/src/rime/gear/script_translator.cc) 和 [Poet](https://github.com/rime/librime/blob/1.17.0/src/rime/gear/poet.cc) 负责词图及句子组合。本次将原默认单句改为最多 5 条，句子截断阈值 0.01、同音候选上限 8。并非 UI 把几个短词拼起来，也不声称具备大型神经语言模型的语义理解。

全拼另有有界音节路径补充：完整合法拼音最多 32 个字母、每个位置保留最多 8 条路径，仅对 1 条尚未展示的切分查询 Rime。它不改输入字符，不把缩写当作完整音节，也不覆盖用户已经选好的汉字前缀。词和整句评分、选择、学习仍由 Rime 执行。双拼的双字母编码已经表达音节边界，继续使用它自己的 Rime 拼写图，不套用全拼重切分。

日文独立解码层读取映射文件，以词性连接成本作有界 Viterbi 搜索，最多处理 80 个假名，产生整段备选及平／片假名回退；选词记忆独立持久化。它并非完整 Mozc 移植，目前不包含完整 Mozc 的重写器、预测、日文纠错、复杂数字／符号处理及分节重选等全部能力。

`SKConversionEngine` 是上层输入会话的统一入口。中／日／混分别调用中文、日文及两种候选；混合模式保留中文首选优先，前几个日文候选插入候选序列，其余可继续浏览。它提供两种语言的整段转换备选，**不代表一句话中任意中文和日文片段都能自动联合解码**。语言／键盘切换先提交待确认输入，保留原有数字符号布局和预编辑上屏机制。

## 规模、性能与验收

纠错候选的搜索索引与正常输入词库分开。实测了全量、最低权重 800、最低权重 100 三档：800 档虽小，但漏掉一些四字词的纠错，故弃用；100 档将两套索引合计从约 150 MB 降为约 66.9 MB，在 400 组独立纠错测试中保留了全量档的 Top8 命中数量，选词／空格没有硬失败。正常输入不受该筛选影响。它是当前测试下的折中，不是对所有语料证明过的数学最优值。

另测补充分词查询数 0／1／3 三档。在同一新词库下，24 组真实同串歧义的双方 Top10 覆盖从 19/24 提高至 23/24；1 与 3 的覆盖及首选相同，而 3 会产生更多生硬组合，因此选择 1。实际混合模式也单独跑 172 组中文排名，并非用纯中文结果代替。

离线资源约 201 MiB（包含约 71 MiB 中文编译词库、53 MiB 日文索引、14 MiB 日文连接矩阵和两套纠错索引），比旧版明显增加。资源使用只读映射，并按模式释放不需要的解码器；文件大小、macOS RSS、iOS physical footprint 分别记录，不能混为一谈。所有运行内容都是数据，没有下载执行代码或运行时编译；仍无需完全访问权限。已附第三方授权，不能把编译通过理解为 App Store 审核保证。

固定中文语料 172 组 × 两套方案，另有 40 组日文目标、400 组独立纠错输入、分词歧义测试、跨进程学习、跨版本学习和 iOS UIKit 实际上屏检查。排名测试不选择目标候选、不训练词频；句子上屏另起进程。测试词及期待结果只在 Tests 中，不进入生产资源。

最终数字、参数比较和逐项结果见 [验收报告](evidence/lexicon-quality/INDEPENDENT_REVIEW.md)、[指标协议](evidence/lexicon-quality/PROTOCOL.md) 与相邻原始 JSON。所有测试均有边界：少量固定语料不能代表所有中文／日文，模拟器 UIKit 测试宿主不等于真机键盘扩展内存测量。

## 复现

```sh
bash scripts/build-rime-data.sh
python3 scripts/collect-rime-notices.py
bash scripts/test-lexicon-quality.sh /tmp/shika-quality
bash scripts/test-lexicon-quality-japanese.sh /tmp/shika-japanese
bash scripts/test-lexicon-segmentation.sh /tmp/shika-segmentation
bash scripts/test-autocorrection-independent.sh /tmp/shika-correction
python3 scripts/summarize-autocorrection-independent.py /tmp/shika-correction
bash scripts/test-lexicon-upgrade.sh
SHIKA_SMOKE_SOURCE=Tests/LexiconRuntimeChecks.swift SHIKA_SMOKE_OPTIMIZED=1 \
 SHIKA_SMOKE_FIXTURE=Tests/LexiconQualityCases.json SHIKA_SMOKE_TIMEOUT=120 \
 python3 scripts/test-keyboard-simulator.py SIMULATOR_UUID
```
