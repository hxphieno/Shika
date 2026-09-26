# 自动组句候选上限

## 行为与范围

只调整 `SKMixedDecoder` 的候选组织，不改 UI、词库、Rime 配置、学习或按键逻辑。混合模式此前先显示最多 24 个完整候选，随后还有整句变体；前缀区也会包含由多个词拼接出来的短句。

现在保留排名最前的六个完整推荐，随后提供从输入开头匹配的词和字。超过六个的自动组句不会在后续分页重新出现。前缀取词图起点的词典词以及原生词候选，不再取多个词拼成的路径。词库真实完整词即便排在六项之外，仍保留在后续词候选区；通过实际词典命中判定，而不是按汉字长度或 segment 数量猜测（Rime 整句可能被合并成一个 segment）。

中文全拼与双拼已有原生组句上限，截图问题精确复现在混合模式，因此未修改其他引擎。纯日文引擎也未改动。

## 真实复现与验收

输入 `haibiandianqiyanhuo`，使用隔离的空用户目录：

| 模式 | 旧候选数 | 新候选数 | “海边”旧位置 | 新位置 |
| --- | ---: | ---: | ---: | ---: |
| 中日混合 | 69 | 51 | 46 | 7 |
| 中文全拼 | 93 | 93 | 2 | 2 |
| 对应双拼 | 92 | 92 | 2 | 2 |

混合前六项文字、注释、ID 和消费长度完全一致；中文、双拼的全量冷启动候选 JSON 完全一致。数量为引擎输出，设备字体过滤仍由已有显示层执行。

未参与实现的 agent 独立验收 **68/68** 通过，覆盖 14 组中文、日文、混合和带分隔符的输入，全部分页的组句总量、真正单词前缀、长词保护、ID/分页、空格和原码回车。七个同音四字词（`fuyuanxiaoqu`）全部保留，验证六句限制不会误删第七个真实词。

实际逐次选择“海边 → 点 → 起 → 烟火”，每次保留正确余码，最终输出“海边点起烟火”。初轮验收程序错误地将学习前后的首选视为必须不变；调整为对比当次首选，另外保留隔离冷启动前后全量比较，未为迁就测试修改生产代码。

iOS 26.5 模拟器使用生产控制器、展开网格和真实 UITextView，**6/6** 检查通过：六句上限、第七项“海边”、单字可达、全部页面与引擎一致、选词余码及回车原码确认。已实际查看[模拟器截图](evidence/sentence-limit/sentence-limit-ios.png)。此次未做实体手机测试或全量回归，不宣称搜索速度提升。

[独立审阅](evidence/sentence-limit/review.md)、[前后比较](evidence/sentence-limit/comparison.json)、[独立检查结果](evidence/sentence-limit/independent.json)、[iOS 结果](evidence/sentence-limit/sentence-limit-ios.json)以及受测源码哈希均已归档。

## 复验

```sh
bash scripts/test-sentence-limit.sh /tmp/shika-sentence-check-fresh
SHIKA_SMOKE_SOURCE=Tests/SentenceLimitDisplayChecks.swift \
SHIKA_SMOKE_OPTIMIZED=1 SHIKA_SMOKE_TIMEOUT=120 \
python3 scripts/test-keyboard-simulator.py <空闲模拟器UDID>
```

本次 iOS 验收在冻结副本使用独立测试 App ID，避免覆盖其他任务的测试程序；没有改生产包标识。原生复验脚本语法检查通过，等效冻结编译及运行流程已执行。
