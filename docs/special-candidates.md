# 符号与 Emoji 候选

中文全拼和小鹤双拼在候选词完整匹配时，增加一个符号或 Emoji 候选：

| 词语 | 全拼 | 双拼 | 第三个候选 |
| --- | --- | --- | --- |
| 逗号 | douhao | dzhc | ， |
| 烟花 | yanhua | yjhx | 🎆 |
| 生日 | shengri | ugri | 🎂 |
| 爱心 | aixin | aixb | ❤️ |

词库位于 `ShikaKeyBoard/Core/SKSpecialCandidates.swift`，由项目自行维护，无网络请求或额外依赖。映射按解码后的词语查询，拼音注释及现有 `correction-syllables.json` 用于确认完整拼写。只检查前五个可见候选；缩写、补全、长句的部分词、已有确认前缀、日文和混合模式均不触发。

`SKInputSession` 在字形过滤和候选补齐后插入特殊候选。普通候选不足两个时追加到末尾；加载更多后重新定位第三位。相同输出只保留一次，原引擎 ID 和分页游标不变。点击特殊候选清空组合输入后直接插入完整 Unicode 字符串，不选择或学习原词。空格、回车、标点及普通候选保持原有提交路径。

新增 Swift 文件由 Xcode 同步文件组自动纳入，无 UI 或工程配置变更。

验证：

```sh
bash scripts/test-special-candidates.sh          # 40 项候选与状态检查
bash scripts/test-special-candidates.sh --native # 另加 82 项真实 Rime 检查
bash scripts/test-input-session.sh
bash scripts/test-autocorrection-interactions.sh
```

专项测试使用独立临时用户词库，不修改应用用户数据。添加词条时应补充真实引擎用例，确认词语在前五个候选中且拼写注释完整。
