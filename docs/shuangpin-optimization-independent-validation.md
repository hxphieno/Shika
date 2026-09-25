# 双拼底层优化独立验收

本文保留冻结、首次失败和修复后的完整历史；最终验收结论见文末“当前生产版本最终结论”。

历史阶段（2026-09-26，构造语料时）：独立语料在查看本轮新引擎输出之前冻结，当时尚未进行最终验收。

[验收协议](evidence/shuangpin-optimization/PROTOCOL.md)和 [840 条质量输入](../Tests/ShuangpinOptimizationCases.json)包含 140 个目标，开发 132 项、保留 708 项。与旧两套纠错集目标交集为 0；按 95 个目标词族绑定 split，包含同音目标、长句内部单错与两处替换。40 个词复用此前词汇质量测试，其他目标独立选定或编写，不声称全为从未见过的数据。

语料 SHA-256：`382c5b44716d406bdab889d4835741d2bd0fa0bd2d74db94381131f6374af7ed`。120 个词的固定词源行号、URL、Git blob 和读音已记录在 JSON，20 个句子明确标为独立编写。已做纯结构验收：840 条变换逐项还原、读音映射、同 target/family/correct 不跨 split、旧纠错目标无重叠。没有运行新引擎挑词或改答案。

最终需分别报告完整候选排名、隔离提交、独立行为、学习持久性、性能与失败分布。部分候选不计完整目标命中；排名进程不选词；行为与学习在隔离进程运行。预设门槛及自然用户分布限制见协议，最终结果待实施完成后补充。

独立行为文件已准备：[ShuangpinOptimizationBehaviorChecks.swift](../Tests/ShuangpinOptimizationBehaviorChecks.swift)。参数为 `resources user report.json behavior|learn|probe`；`learn` 与 `probe` 必须是两个进程共用另一份 fresh user directory，不能与质量排名共享目录。自然选词 5 次生成“鹿键喵”（lu + jm + mn），另一个进程先检查 exact 首选与 Return，再检查三个固定邻键替换 `kujmmn/lukmmn/lujmmm`；先记录三个错码排名再选择，遗漏 `lujmn` 单列诊断。测试目标和错码在最终运行之前固定。

行为代码还覆盖 clean/typo Return、空格、标点与字面输入、逐字删除、部分选词后 Return/空格/标点/切方案、删除后重输、候选展开/分页 ID、过期候选、长原码完整保留。这里观察宿主回调与 marked 字符串，不使用 UIKit，不声称验证触屏或真实扩展。

行为文件冻结 SHA-256：`76ce23e56d2b2560495d17b6e416e1800a5320da2b72b8eaa411f7f43862549a`。任何后续必要测试修正必须说明原因并保留首次结果，不得为使引擎通过而降低已有契约。

## 首轮独立执行（开发版本，非最终质量结论）

已冻结源码和整个 Rime bundle 到 `/tmp/shika-sp-independent-dev1`，记录源码与资源 hash，使用 `-O -whole-module-optimization` 链接真实 macOS librime。可复用 runner 为 `/tmp/shika-sp-independent-dev1/runner`，其默认测试仍保留首次断言以复现原始结果。本轮没有运行保留质量集排名。

- 首轮 behavior 为 68/69。唯一失败是部分选词后第一次删除的测试假设：旧冻结生产版本同样 68/69，逐字输出相同。原生诊断确认退格撤销部分确认而未删掉原码；不应额外补 p。测试已按既有语义修正，生产不改。首次和基线结果都保留在 [independent-dev1](evidence/shuangpin-optimization/independent-dev1/)。
- learn 为 11/11：通过真实候选逐段造词“鹿键喵”，自然选择 5 次，每次只提交一次，exact 用户词成为首选。
- 新进程 probe 为 6/10：exact 首选持久化、浏览取消、Return 原码通过；`lujmmm` 可以找到并完整提交“鹿键喵”。`kujmmn` 和 `lukmmn` 没有找到该用户词，各导致可见性与完整选择两项失败，共 4 项。原样保留，不改样例、不降低标准；实现者需解决或明确保留限制。

首轮失败不是所有双拼纠错均不可用的证据，也不能因 exact 学习成功就声称任意用户词错键都可恢复。最终需对修复版本重新冻结源码、编译、运行全部行为/学习/跨进程检查。

## 历史阶段：追加确认语料

实现者读取首轮保留集总指标后，独立追加 [480 条确认输入](../Tests/ShuangpinOptimizationConfirmationCases.json)，80 个目标与冻结时全部既有 Tests JSON 的 target 均不重合。普通词 56、同音目标 12、长句 12，每个目标仍有 6 类输入。SHA-256 为 `9d938a23388cce3ae3d9e8520a2eab0ec0fc1430cb2d7bb0eacf681e7b64461e`。

确认集尚未运行，全部作为最终 heldout，不用于调参。沿用 +5pp 门槛：320 条单错完整 Top5 净增至少 16，正确输入不退化；来源、构造、首次运行与自然分布限制见协议追加章节。

在完全相同的首轮生产源码/资源上，仅替换修正后的独立测试，重新优化编译执行得到 **behavior 70/70**；见 `independent-dev1/corrected-contract-behavior.json`。对应可复用 runner 为 `/tmp/shika-sp-independent-dev1-corrected/runner`，资源仍用 `/tmp/shika-sp-independent-dev1/RimeData.bundle`。用户词 4 项失败尚未被该行为重跑解决，最终 probe 仍须重跑。

## 全拼推广前：双拼冻结版本独立行为结果

[最终独立证据](evidence/shuangpin-optimization/independent-final1/)记录：behavior **70/70**，自然学习 **13/13**，另一个进程恢复与用户词纠错 **19/19**，metadata 边界 **15/15**，总计 **117/117**。

原先失败的 `kujmmn`、`lukmmn` 和原先已成功的 `lujmmm` 三码保持原样，最终全部显示并完整提交“鹿键喵”。新增遗漏 `lujmn`、插入 `lujjmmn`、交换 `lumjmn` 也全部成功。最终学习索引保存正确 `lujmmn`，没有把这些错码记录为正确读音；查询和原码 Return 不会写新词。

索引检查用 600 个最大允许长度的记录验证仅保留最新 512 个，实际文件为 72705 bytes，小于 128 KiB；损坏 JSON、超限文件、无效输入和重复项都按契约处理，重新初始化后能恢复最新记录。这些直接类测试与 Rime 会话使用不同测试目录。

静态与身份审查确认：新增音节辅助、同码候选和用户词纠错在 Engine 内，Core 与 Schemes 的 9 个文件相对改动前冻结版本完全一致；这些层在已部分选词时不替换原生组合，纠错选择回到真实 Rime 原生提交和学习。辅助会话独立于主输入会话，未新增 UIKit 依赖。源码/资源逐项核对与当前生产一致，见 [identity-audit.json](evidence/shuangpin-optimization/independent-final1/identity-audit.json)。这里不能替代 iOS UI 或物理设备验收。

最终可复用 runner：`/tmp/shika-sp-independent-final1/runner`，资源：`/tmp/shika-sp-independent-final1/RimeData.bundle`。参数为 `resources user report.json behavior|learn|probe|index`；learn/probe 是两个进程共享单独用户目录。未来源码或资源变化须重新校验或重编译，不能复用旧结果冒充新版本通过。

## 历史阶段：确认结果尚未提供时

必须保留首次质量未达门槛的事实：实现者报告的首轮 708 项 heldout 中，472 项单错完整 Top5 从 285 到 308，净增 23，**+4.873 个百分点，低于预设 +5pp**。本独立行为 117 项通过不能覆盖该质量结论；本报告尚未审核最终确认集准确率或性能结果。

480 条新确认语料仍按冻结协议由实现者统一同机 baseline→final 顺序运行，本独立 agent 未提前运行其排名，也没有根据它的输出调节样例。最终确认结果应追加，不能删去上述首次未达门槛记录。

## 双拼最终确认集：独立复核结果

已独立复核 `/tmp/shika-shuangpin-opt/confirm-{baseline,final,summary}.json`，逐项检查 480 个 ID、目标、输入、正确码、split 与冻结语料一致，未丢失分母。确认语料 SHA-256 未变。重新以原生候选 comment 映射双拼码核对完整消费标志，重算目标排名和每项耗时分位数，均与汇总一致；最终 4 个“文字出现但只是部分候选”的样本没有算作完整命中。排名 runner 只输入/读候选；只有显式隔离 commit-ID 分支才选词，两个排名报告均 `rankingLearnsAnswers=false`，排名用户目录没有新学习拼写 metadata。

质量编译使用的最终 23 个生产源码与 117 项行为验收冻结源码完全一致；旧版 21 个源码与原冻结基线一致。[confirmation-audit.json](evidence/shuangpin-optimization/independent-final1/confirmation-audit.json)记录独立计算、文件 hash、门槛和限制。

| 确认集分组 | 分母 | 完整 Top5：旧 → 新 |
| --- | ---: | ---: |
| 邻键替换 | 80 | 30 → 38 |
| 漏键 | 80 | 29 → 35 |
| 多键 | 80 | 54 → 64 |
| 相邻交换 | 80 | 41 → 47 |
| 单错合计 | 320 | 154 → 184 |
| 两处替换 | 80 | 0 → 10 |
| 正确输入 | 80 | 75 → 75 |

单错完整 Top5 从 **48.125% 到 57.5%，+9.375pp**，达到确认集 +5pp 的冻结门槛；四类均未退化。correct clean Top1 保持 62/80，全部 clean 首选文字不变；全 480 项没有任何原本 Top5 命中的样本跌出 Top5。双方打码时意外上屏均为 0。

**单错 Top1 仍为 85/320（26.5625%），没有提高。** 此轮改善主要是可选择的后排候选覆盖，不能表述为自动首选纠错提高 9.375pp。长句仍明显较弱：48 条长句单错的 Top5 仅从 0 到 3，Top10 从 0 到 5；12 条长句 clean 只有 8 条全文命中。任意长句和多错均不能承诺可靠恢复。

同机 macOS 单次顺序运行各记录 3348 次按键：P95 1.0079 → 1.1730 ms（1.164 倍，低于 1.25 倍门槛），P99 2.4570 → 3.0071 ms，均低于绝对门槛。冷启动 48.71 → 75.30 ms；最大单键 84.68 → 42.66 ms；峰值 RSS **76.52 → 98.20 MiB，增加 21.69 MiB**。这些数字如实体现成本，不能把缓存后的短语重复测试当作所有自然输入或真机键盘的性能保证。

只读生产复核未发现新的阻断正确性问题：同码额外候选只用于双拼；helper 与学习索引均按双拼配置启用、保护已确认片段；负候选 ID 范围彼此分离；主会话负责最终上屏与原生学习。静态剪枝/缓存只作用于不可变词典建议，用户候选仍重新通过 Rime 校验。内存上升需以 iOS 扩展测量进一步确认，不能由此 macOS RSS 推算通过。

本轮确认集的质量及所定义的 macOS 耗时门槛通过，**首次 708 项测试 +4.873pp 未达门槛的历史仍然成立并保留**。全命中目标的逐例隔离进程上屏回放由实现者继续执行；在该结果提供前，这里不声称已经逐例证明每个排名命中都实际提交成功。语料是独立设计和词源改编数据，不代表自然用户分布。

## 完整上屏回放与模拟器证据复核

现已取得并独立逐项审核确认集中全部 **305 个完整候选命中**（包含第 10 名以后的已显示候选）的隔离回放。每项一个结果、一个独立用户目录；目标全文、原输入与排名记录一致，输出恰好为目标，剩余 input/preedit 为空、候选数为 0，再次 commit 没有输出。没有漏掉排名命中，也没有拿未命中项算通过。证据：[confirmation-commit-audit.json](evidence/shuangpin-optimization/independent-final1/confirmation-commit-audit.json)。这补齐了上一阶段待验证的真实提交部分。

另审阅实现者的 [模拟器运行报告](evidence/shuangpin-optimization/simulator/runtime-report.json)及 [构建说明](evidence/shuangpin-optimization/simulator/build-context.json)：iOS 26.5 iPhone 17 Pro 模拟器中的 UIKit 宿主与 proxy，300 次方案切换、1687 次输入无失败，120–300 切换窗口增长/波动均为 65536 bytes，20–120 的初始增长为 737280 bytes。逐键 P95 1.272 ms、P99 1.820 ms。构建说明已纠正继承报告中错误的“without -O”字样，本次实际为 `-O`。这些是双拼推广阶段的模拟器宿主测量，**不是键盘扩展进程或物理 iPhone 的测量**，不得据此承诺真机内存上限。

## 中文全拼推广的独立行为对比

唯一生产差异是在 `SKCorrectionCandidates` 中去掉“仅双拼”条件，让既有 3 个修正编码查询得到的同音候选也用于全拼；没有增加另一套中文词频或修改按键规则。[独立全拼测试](../Tests/FullPinyinGeneralizationChecks.swift)对相同来源、相同资源的冻结 before/after 使用同一份测试和不同 fresh user 进程。

结果为 before **60/60**、after **66/66**。24 组全拼输入（含同音、分隔、别名、长句和错码）的首选文字与原生完整候选序列逐项完全相同。新增的 6 项针对三条额外纠错路径：`nohao/nihoa → 拟好`、`zhongguoo → 种过`，都通过真实 Rime 完整选择、清空与不重复上屏。部分选词、原码 Return、退格、文字/标点上屏、候选展开与取消行为均保持；全拼操作没有创建双拼学习索引。

证据与源码 hash 分开存于 [full-generalization/independent](evidence/shuangpin-optimization/full-generalization/independent/)，生产源码逐项确认只有上述一个文件的一处条件变化。新增候选改善可选性，不意味着这些词应替代当前首选。

## 中文全拼派生质量数据复核

独立重建并核对 840 条全拼输入：正确码严格由初集的 syllables 连接，再应用同一冻结位置、邻键、交换和双错规则，全部与派生文件吻合。140 个目标、132/708 的开发/保留分组均沿用原双拼集，**不是 140 个新词汇的盲测**。运行时冻结文件 SHA-256 为 `4dfec1e0bee2f211907a7c351f0f946b02e4844b3b9d6ea96b6c76e541f340d4`；归档语料见 [FullPinyinOptimizationCases.json](../Tests/FullPinyinOptimizationCases.json)。

重新核对全部完整消费标志、排名与不学习分支：560 条单错完整 Top5 **374 → 404（+5.357pp）**；其中保留部分 472 条为 **318 → 342（+5.085pp）**，开发部分 88 条为 56 → 62。正确输入 Top1 118/140、Top5 135/140 不变，全 840 项没有 Top5 回退或意外上屏。单错 Top1 255/560 不变，140 条双错 Top5 仍为 0，不能推广为全拼任意错码可恢复。

macOS P95 4.8621 → 6.0461 ms（观察值约 1.244 倍），P99 8.6709 → 12.9930 ms。两轮按 baseline→final 的次序启动，但 final 期间与提交回放任务有短暂并发，因此这是有负载干扰的单轮观察，不能称为严格静稳顺序对比或独立证明全拼 1.25 倍性能门槛，更不提供真机时延保证。审计见 [quality-audit.json](evidence/shuangpin-optimization/full-generalization/independent/quality-audit.json)。

## 当前生产版本最终结论

全拼推广合入当前生产后，已重新冻结、优化编译并重跑全部双拼/学习/metadata 独立验收，仍为 **117/117**；最终 **24 份源码（含测试）和 19 份资源**与当前生产逐字节一致。当前可复用 runner 为 `/tmp/shika-sp-independent-final2/runner`，资源为 `/tmp/shika-sp-independent-final2/RimeData.bundle`，最新证据为 [independent-final2](evidence/shuangpin-optimization/independent-final2/)。旧 final1 记录保留用于追溯，不能与当前源码 hash 混用。

本次范围内未发现阻断性的输入丢失、重复上屏、候选路由或学习持久化问题；独立行为与已审核质量门槛通过。首次双拼 708 项测试 **+4.873pp 未达 +5pp** 的失败记录仍保留。实际收益主要体现在后排候选覆盖和已学用户词恢复，长句/多错仍受限，候选覆盖提升不能宣传为自动首选提升。没有修改生产 UI，也没有把 Mac/模拟器宿主结果冒充物理设备键盘扩展验证。

最终补充核对：归档的 [提交摘要](evidence/shuangpin-optimization/commits/)分别为确认集 **305/305**、初始双拼保留集 **494/494**、全拼派生集 **571/571**。独立比较其 ID 集与所有完整排名命中完全相等，各项输出都等于目标且无剩余输入；见 [commit-summary-audit.json](evidence/shuangpin-optimization/independent-final2/commit-summary-audit.json)。确认集还已逐份检查原始回放的空 preedit/候选和二次 commit。

全拼派生文件最初继承了双拼 edits 元数据，实现者在排名后修正了描述字段。[勘误记录](evidence/shuangpin-optimization/full-generalization/metadata-erratum.json)保留原运行 hash。独立复核当前归档 840 条的所有排名字段（ID、input、target、correct、kind、schema、split）与原运行文件完全不变，修正后的 edits 可逐条还原实际输入；当前文件 SHA-256 为 `110de696b50606ec91a690d484c8786a5772df7d9db826cd6e59bdc2689a03d9`。这是元数据纠错，没有改测试答案或重算输入来改善成绩。

最终生产还补跑了 [simulator-release](evidence/shuangpin-optimization/simulator-release/runtime-report.json)：300 次切换、1687 次输入无失败，P95 1.531 ms、P99 2.101 ms；120–300 切换窗口 footprint 增长/波动均为 49152 bytes，末次切换约 36.72 MB，UI 绘制及自动释放池排空后约 51.46 MB。这仍是模拟器 UIKit 宿主，不能作为物理设备键盘扩展内存证明。前一轮模拟器数字保留为历史，最终生产读者应引用本轮。
