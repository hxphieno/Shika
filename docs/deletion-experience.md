# 删除体验调整与验收

2026-09-25。目标是采用熟悉的 iOS 删除交互，统一主键盘和自定义数字符号页，同时保留引擎预编辑与正文的边界。

## 用户行为

- 按下即退格一次；松手不再重复触发。数字页现在也能长按连续删除，并有按下态。
- 长按先逐字删除，持续按住后对已提交正文按词加速。预编辑始终由对应引擎退格，不进行整词批量删除。
- 删除最后一个待确认单位后，重新等待一次初始延迟，再进入正文，降低误删已经写好的内容的概率。
- 手指小幅漂移有 6pt 容差；移出暂停，移回续接剩余等待时间，不立即补删。初始命中区域不额外侵占相邻按键。
- 松手、取消触摸、退出键盘、切页、切输入模式、选择候选、点击其他文字键、焦点改变或应用失活时，取消连删。
- 已选中的文本只调用一次系统退格。普通字符、组合音标和 emoji 的实际删除单位交给 UIKit。
- 日文删除可见假名或未完成罗马字，例如 `か → 空`、`きゃ → き`、`がっk → がっ`。已完成文字无法反编码为罗马字时，保留完成部分，避免再次解码改变内容。

## 实现边界

`SKDeleteKeyInteraction` 统一两类按键的计时与触摸生命周期。`KeyboardViewController` 区分预编辑与正文，向交互层返回继续、停止或重新等待。`SKBackwardDeletion` 只计算正文当前行末尾的删除量；`SKMarkedTextConnection` 通过公开的 `UITextDocumentProxy.deleteBackward()` 完成实际编辑。

当前默认值为 450ms 初始等待、100ms 逐字间隔，第 17 次定时重复开始按词删除（正常负载下约按住 2.05 秒），按词间隔 150ms。这些是 Shika 的实现参数，不是 Apple 公开或已精确测出的内部常量。

词边界使用 Foundation 的 `.byWords` 分词；尾随空格与前词一起删除，标点及 emoji 退格按系统字符单位处理，不跨换行批量删除。单次批量上限 32 个字符；超长词退回逐字。代理没有可靠文档标识、上下文不刷新、上下文窗口移动或文档切换时，不继续使用旧上下文批量退格。

Apple 的公开接口说明见 [自定义键盘的文本交互](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards) 与 [textDocumentProxy](https://developer.apple.com/documentation/uikit/uiinputviewcontroller/textdocumentproxy)。按下开始、按住重复、释放停止的第三方实现参考为 [KeyboardKit: Keyboard typing explained](https://keyboardkit.com/blog/2022/11/24/keyboard-typing-explained)。未使用私有接口或系统键盘内部代码。

## 可复现检查

```sh
# 独立编写的 UIKit、计时器、正文与预编辑验收
SHIKA_SMOKE_SOURCE=Tests/DeleteInteractionAcceptanceChecks.swift SHIKA_SMOKE_TIMEOUT=120 \
  python3 scripts/test-keyboard-simulator.py <SIMULATOR-UUID>

# 日文所有导入规则及其中间状态的删除不变量
bash scripts/test-japanese-delete.sh

# 输入、选词、学习与日文转换回归
bash scripts/test-input-session.sh
bash scripts/test-lexicon-quality-japanese.sh /tmp/shika-delete-japanese

# 既有主键盘交互回归
SHIKA_SMOKE_SOURCE=Tests/MainKeyboardInteractionChecks.swift \
  python3 scripts/test-keyboard-simulator.py <SIMULATOR-UUID>
```

结果及独立验收记录保存在 [evidence/deletion](evidence/deletion/)。最终独立删除验收 145 项全部通过，并复核了主键盘与数字页的按下／释放状态截图。原有主键盘 119 项、输入会话 54 项、日文 5,264 项删除不变量通过；日文 40 组候选排名与 79 项功能检查没有退步。最终 iPhone Release 无签名编译与离线资源审计通过。

独立检查使用模拟器里的真实 UIKit 文本控件与真实 run-loop 计时器，按键事件由测试程序派发。它验证计时、停止、恢复、选区、Unicode、文档切换和候选/正文边界，不等同于真人手指触摸或真实宿主 App 的键盘扩展全链路测试。截图用于检查高亮和布局，不能证明长按节奏。

`Tests/NativeDeleteReference.swift` 是可人工操作的原生键盘记录页。本轮通过 UI 工具实际点击 Apple 原生删除键，观察到单次退格；工具不能执行任意时长的真实按住手势，因此没有测得 Apple 的长按阈值或词删节奏。该页面的 `PASS ... fixture ready` 仅表示记录页准备完成，不属于行为验收。最终手感仍需实机体验确认，不能据此宣称与 Apple 时序完全一致。
