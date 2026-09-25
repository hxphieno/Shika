# 待确认文本与候选栏验收

2026-09-25，iPhone 17 Pro 模拟器，iOS 26.5。

## 行为

- 候选栏从 60pt 改为 44pt 单行，移除单独的拼音行。
- 中文全拼与双拼通过公开 `UITextDocumentProxy.setMarkedText` 把组合文字放入宿主输入框；选词、空格确认、标点及回车提交时替换自己的待确认范围。外部光标/文档变化结束当前组合，不通过回删推测范围。
- 向下箭头展开纵向候选网格，覆盖主键区并保持键盘总高度；向上箭头收起，选词后恢复键盘。滚动接近底部继续加载候选。
- Core 仍不依赖 UIKit：会话输出组合文字，`UI/Integration/SKMarkedTextConnection` 管理系统文本连接。Rime 的非破坏性候选遍历不改变当前组合、候选页或纠错候选选择映射。
- 文档连接期间，系统 Objective-C `documentIdentifier` getter 可能临时返回 nil；通过公开 selector 安全读取，避免 Swift 强制桥接 UUID 崩溃。

Apple API：[setMarkedText(_:selectedRange:)](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/setmarkedtext(_:selectedrange:))。待确认文字的具体视觉样式由宿主文本控件决定。

## 真实扩展操作

已在 Shika 应用的 SwiftUI TextEditor 中启用并操作实际键盘扩展，不仅是测试宿主：

1. 双拼输入 `nihc`，文本框出现带下划线的 `ni hc`，候选条仅显示候选。
2. 点击向下箭头，主键区变成候选网格；文本框的组合保持不变。
3. 选择「你好」，文本框变成「你好」，待确认范围消失、主键区恢复。
4. 鹿按钮切到中日键盘，输入 `nihao`，已有「你好」后出现待确认 `ni hao`；空格确认得到「你好你好」，没有残留字母或重复上屏。

截图：[待确认文字](evidence/marked-candidates/extension-marked.png)、[展开候选](evidence/marked-candidates/extension-expanded.png)、[选词确认](evidence/marked-candidates/extension-confirmed.png)。验证时临时调整过模拟器键盘列表，已恢复原来的 9 个键盘及其顺序。

## 回归

- `Tests/MarkedTextAndCandidatesChecks.swift`：30 项检查通过，连续重启复跑 3 次均通过。真实 UITextView、生产控制器与 Rime 联动，覆盖组合、删除、部分选词、候选加载、纠错选择、双拼、标点、换行、选区替换、emoji 周围文字及断开文档。UI 输入事件之间留出主线程 run-loop，让 UIKit 完成选区更新。
- `Tests/MainKeyboardInteractionChecks.swift`：主键盘 119 项交互断言通过。既有 UI 测试代理同步补齐 marked text / unmark 的提交语义；真实系统行为另由 UITextView 联动检查和实际扩展操作验证。
- `Tests/KeyboardIntegrationSmoke.swift`：实际 UIKit 按键到 Rime 再到文本代理的双方案冒烟通过，覆盖各语言模式、选词、空格、回车、删除及页面/方案切换提交。候选查找兼容新的 UIButton.Configuration。
- `scripts/test-input-session.sh`：54 项会话断言；用户词频跨进程记忆及共享 Rime runtime 检查通过。
- `scripts/test-autocorrection-interactions.sh`：32 项纠错交互断言通过。
- `Tests/AutocorrectionRuntimeChecks.swift`：300 次方案切换、1687 次引擎按键处理及生产 UI 纠错上屏通过；本轮按键 P95 5.83ms，后段内存占用无增长。旧测试统一使用测试应用沙盒的默认用户目录，以符合共享 runtime 约束，并发送完整触摸事件。
- `scripts/test-autocorrection.sh`：320 组用例，开启/关闭纠错两组候选结果与架构整理后的基线一致（忽略每次测量的耗时字段）。本次未修改纠错算法、词库或键位映射。
- 模拟器 Debug 与 iPhone Release 均构建成功；Release 使用 `CODE_SIGNING_ALLOWED=NO` 验证编译，没有验证真机安装与第三方应用兼容性。

测试宿主截图：[拼音](evidence/marked-candidates/marked-pinyin.png)、[候选网格](evidence/marked-candidates/expanded-candidates.png)、[确认文本](evidence/marked-candidates/confirmed-text.png)。
