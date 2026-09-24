# Rime 验证记录

验证日期：2026-09-25。环境：Apple Silicon Mac、Xcode 26.6、iOS 26.5 iPhone 17 Pro 模拟器；librime 1.17.0。真机架构检查为 unsigned arm64 Release 构建，不代表完成了物理 iPhone 的运行验收。

## 原生引擎

`bash scripts/test-rime-native.sh` 使用生产 Objective-C 桥接、真实静态库及打包词库，创建全新临时用户目录，全部通过：

| 方案 | 输入 | 选词上屏 |
| --- | --- | --- |
| 小鹤双拼 | nihc | 你好 |
| 小鹤双拼 | vsgo | 中国 |
| 小鹤双拼 | uijp | 世界 |
| 小鹤双拼 | aa | 啊 |
| 全拼 | nihao | 你好 |
| 全拼 | zhongguo | 中国 |
| 全拼 | shijie | 世界 |

额外验证组合删除、候选翻页、非首选项选择、空格确认和一次性消费上屏结果。没有用固定字符串替代引擎输出。

## UIKit 按键集成

`python3 scripts/test-keyboard-simulator.py` 编译生产键盘视图、控制器、输入会话、Rime 桥接到临时测试宿主。测试触发实际 UIButton actions，以可检查的 `UITextDocumentProxy` 测试实现接收文字。

通过候选点选、空格确认、组合退格、已上屏退格、换行、数字页返回、🦌 切换时提交旧组合，以及中日键盘三个状态的全拼输入。实际输出为 `你好中你好\n你好1中国你好你好你好`。两次测试宿主冷加载约 0.31–0.39 秒，此数字仅供开发参考，不能当作真机扩展性能指标。脚本会删除旧报告，等待本次 PASS；若应用断言失败或超时则退出非零。

检查 320、390、430 点宽度截图：键位/注音、候选栏、翻页按钮和系统 Globe 均可见。该宿主测试不冒充系统键盘扩展测试。

## 构建和资源

- 完整 Debug iOS Simulator 工程构建通过。
- Release iPhoneOS arm64 工程编译、静态链接通过。
- `scripts/check-rime-bundle.py` 对 Release 成品逐文件比较词库内容，全部一致。
- 安装包中扩展 `RequestsOpenAccess=false`，存在隐私清单及第三方许可；主应用也包含可阅读的许可。
- `otool -L` 显示扩展只依赖系统库/框架，没有独立 Rime 动态库。
- Release 符号检查与隐私清单对应。原有按键 inset 弃用警告不影响本次构建，尚未做整个 UI 的 API 升级。

## 独立验证

独立验证 agent 使用生产桥接和 Swift 会话复核，而非只检查编译。可重跑脚本和系统扩展结果随本记录一并保存。

### 生产引擎与会话策略的独立测试

`bash scripts/test-input-session.sh` 已实际重跑通过 **48 项断言**，使用生产 `SKRimeSession`、`SKRimeEngine`、`SKInputSession` 和同一份离线词库，每轮生成独立的临时用户目录。

- 小鹤长句：`wouivsgorf → 我是中国人`、`nihcuijp → 你好世界`；另验证 `nvhd → 女孩`、`lvse → 绿色`、`anqr → 安全`。
- 全拼长句、`xi'an → 西安`、`nvhai → 女孩`、`lve → 略`。
- 未选词不上屏，空格/标点/换行/大写的提交顺序，切换方案提交旧组合，组合内退格和宿主退格分离，第二页非首候选选择，部分候选分段确认，取消与原样字母上屏不重复提交，以及连续 100 次组合。
- 独立的两进程学习验证：新用户 `ni` 的“腻”起初不是首选；选择 5 次后成为首选，进程退出并重新启动后仍为首选。测试使用真实用户词库文件，不以同一进程内缓存代替持久化验证。

测试源码：`Tests/RimeSessionChecks.swift`、`Tests/RimeLearningChecks.m`。这些原生测试运行在 macOS；它们验证同版本 Rime 与生产输入策略，不单独证明 iOS 系统扩展行为。

### 真正的 iOS 系统键盘扩展

独立验证 agent 在 iPhone 17 Pro / iOS 26.5 模拟器安装正式 `Shika.app`，通过系统 Settings 添加 Shika 键盘，使用主应用的实际 SwiftUI TextEditor 接收文字。没有开启完全访问。该轮使用真正的 keyboard `.appex` 和系统 `UITextDocumentProxy`，不是上文的 `TestProxy` 宿主。

实际屏幕点击结果：

1. 🦌 切入小鹤，点击 `n/i/h/c`，候选“你好”出现；点击候选后，宿主文本框实际值为“你好”。
2. 按退格后宿主实际值为“你”。
3. 🦌 切回中日键盘，混合状态 `nihao` 点击“你好”上屏；中文状态 `nihao` 按空格上屏。
4. 日文状态本阶段使用中文全拼：输入 `nihaoshijie`，点击非首候选“你好”后保留 `你好shi jie` 组合和“世界”等候选；再点“世界”，最终一次提交“你好世界”，没有被宿主文本变化回调清空或重复提交。

最终宿主可访问性树中 `typingTest` 的真实值为 `你你好你好你好世界`。截图见 [实际扩展上屏](validation/rime-real-extension.png)。

为了稳定选择被测扩展，临时精简了模拟器系统键盘列表；验收结束后，原有 8 项键盘及顺序均已恢复，并将新增 Shika 保留在末尾。此次未在物理 iPhone 上重复运行，也未执行 App Store 提交；不将这些开发验证描述为审核通过。
