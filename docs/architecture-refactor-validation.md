# 输入架构整理验收

日期：2026-09-25。行为基线：`23bf20340459b51cca3b35f4df6377440af25700`。本次是技术重构，未新增输入功能、调整纠错算法、替换词库或迁移用户数据。

## 结构调整

- 引擎协议与候选/组合模型移入 `Core/SKInputEngine.swift`；`SKInputSession` 和配置可以在不链接 UIKit、Objective-C 或 Rime 的情况下编译。
- 两套方案分别提供 `SKInputConfiguration`。公共会话根据输入策略路由按键，Rime 与纠错器不再硬编码具体的拼音/双拼 schema 名称。
- `SKCorrectionCandidates` 负责纠错候选合并、去重、排序及选中映射；`SKRimeEngine` 保留实际会话调用和纠错输入提交。排序、精确候选保护、部分选词保护沿用原实现。
- `SKKeyboardState` 由控制器持有。语言按钮只发点击意图；两套键盘共享 `SKShiftState` 的逻辑，各自保有独立大小写状态。
- `Vendor/RimeData/shuangpin-layout.json` 为双拼映射的唯一维护源，生成 schema 和 Swift 键帽提示；纠错资源继续由生成的 schema 派生。
- Objective-C 桥接内部显式区分进程级 Rime 运行时与会话。相同目录可复用运行时，不同目录请求会明确失败，不再静默使用首次初始化的目录。

## 实际检查

| 检查 | 结果 |
| --- | --- |
| Core 协议、配置和会话单独编译 | 通过，无 UIKit/Rime 依赖 |
| 原有输入会话检查 | 48 项通过 |
| 原有纠错交互检查 | 32 项通过 |
| 用户词学习与跨进程排序记忆 | 通过 |
| 多会话共存、规范化路径、目录冲突拒绝、销毁其他会话后继续输入 | 通过 |
| 320 组语料，分别关闭/开启纠错，与重构前本地运行结果比较 | 候选文字、顺序、注释、编号及目标排名完全一致 |
| 400 组独立固定语料，与仓库已提交 final-run 比较 | 原生排序、纠错排序、选择/空格上屏及剩余组合完全一致；仅忽略耗时字段 |
| UIKit 键盘交互 | 119 项通过，包含新增的模式切换期间保留组合、状态往返和中文转换检查 |
| 真实 UIKit 按键 → Rime → UITextDocumentProxy 测试替身 | 候选、空格、换行、删除、数字页、方案切换及三个语言状态通过 |
| 主键盘快照 | 5 种宽度 × 2 个主题 × 3 种布局，共 30 张，以及 3 张按下弹出态，与重构前 PNG 字节完全一致；键位几何 JSON 一致 |
| 双拼生成物 | 413 个音节编码不变；`--check` 通过；重新生成纠错索引后资源无 git 差异 |
| Xcode 构建 | 完整 App + 扩展的 Simulator Debug、iPhone arm64 Release 均通过，使用 `CODE_SIGNING_ALLOWED=NO` |
| 成品资源检查 | 离线资源、静态 Rime、权限及声明检查通过 |

数字符号页没有修改源码。其 10 张快照中的符号区域出现宽度分配差异；在临时目录从同一基线提交重新提取、编译原始源码后，10 张数字页快照同样出现差异，而复用同一个旧二进制重复运行则一致。这说明现有数字页的截图依赖编译结果/布局求解，不能把这些快照当作稳定的逐像素基线。此次没有扩展到该页的布局修复；数字输入及页面往返功能检查通过。

本轮没有做物理 iPhone 安装或触摸验收。模拟器集成使用生产视图、控制器、Rime 和测试 proxy，不能等同于真实宿主应用内的键盘扩展测试。

机器可读比较摘要与日志摘录见 [evidence/architecture-refactor](evidence/architecture-refactor/summary.json)。

## 复跑命令

```sh
bash scripts/test-input-session.sh
bash scripts/test-autocorrection-interactions.sh
bash scripts/test-autocorrection.sh
bash scripts/test-autocorrection-independent.sh
python3 scripts/generate-rime-schemas.py --check
SHIKA_SMOKE_SOURCE=Tests/MainKeyboardInteractionChecks.swift python3 scripts/test-keyboard-simulator.py
SHIKA_SMOKE_SOURCE=Tests/MainKeyboardVisualChecks.swift python3 scripts/test-keyboard-simulator.py
python3 scripts/test-keyboard-simulator.py
```

所有学习验证使用独立临时用户目录；没有清理或重写用户的正式词库。
