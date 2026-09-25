# 回车行为对照（2026-09-25）

## 当前产品策略：日文也使用原始字母

按后续用户要求，日文预编辑及回车确认现在与中文一致：`nihon` 显示并确认 `nihon`，不自动确认成 `にほん`；退格按显示的原始字母逐个删除。日文转换词仍作为候选，原文假名固定在第三项（候选不足三项则紧随已有词），去重且不被学习频率移走。点击假名候选可以直接输入假名，空格仍选择第一候选。日文回车按钮也跟随宿主类型。

下方日文假名确认行为是 Apple 原生的观察记录，保留作为对照；当前产品采用上面的用户指定策略。

本次日文调整后的专项结果：**50 条通过**，包括原始字母显示和退格、回车原样确认、假名第三项与选择上屏、学习后位置稳定和无重复，以及原有中文／双拼回车边界。见 [日文调整验收结果](evidence/japanese-raw/return-results.json)。旧日文测试的预编辑／删除断言也已同步，未运行全量回归。

## 原生对照记录

在 iOS 26.5 模拟器中实点 Apple 原生键盘，使用 `Tests/NativeReturnReference.swift` 的真实 UITextView 记录回调：

| 输入状态 | 首次回车 | 再次回车 |
| --- | --- | --- |
| 中文拼音 `nihao`，发送型输入框 | 确认字母 `nihao`，不选“你好”，不发送 | 交给宿主发送处理 |
| 已确认 `nihao`，默认输入框 | 插入换行 | 再插入换行 |
| 中文 `nihao` 先选“你”，剩余 `hao` | 确认 `你hao`，不换行 | 按宿主类型处理 |
| 日文假名 `か`，首候选为“描いて” | 确认 `か`，不选首候选、不换行 | 按宿主类型处理 |

原生中文在预编辑时仍显示输入框对应的发送／换行键；日文预编辑时显示“確定”。候选区是否有词不能用于判断是否发送：原生在已经确认文字后仍可能显示联想词。应区分**是否还有待确认输入**以及**宿主要求的回车类型**。

实现使用公开的 [returnKeyType](https://developer.apple.com/documentation/uikit/uitextinputtraits/returnkeytype) 更新按钮。没有预编辑时，通过文本代理插入一次 `\n`，由宿主处理发送、搜索或换行，键盘不自行调用任何发送接口。中文及双拼预编辑交给现有 RIME `express_editor` 的 Return；[librime 1.17 源码](https://github.com/rime/librime/blob/1.17.0/src/rime/gear/editor.cc) 中该键绑定 `CommitRawInput`，保留已选分段、确认剩余原始编码。日文按当前产品策略确认原始输入。空格继续选首候选。

仅运行回车专项检查：

```sh
SHIKA_SMOKE_SOURCE=Tests/ReturnInteractionChecks.swift SHIKA_SMOKE_TIMEOUT=45 \
  python3 scripts/test-keyboard-simulator.py <SIMULATOR-UUID>
```

首次回车调整的结果：**34 条专项检查全部通过**，实际 UIKit 宿主编译通过，并通过模拟器界面复核了发送箭头与 `你好uijp` 的部分选词结果。测试由独立 agent 编写，覆盖四种输入模式、部分选词、发送／换行及按钮更新；使用真实 UITextView、生产 controller/session/footer，程序派发按键事件。发送型测试宿主显式消费 `\n`，没有向任何人发送消息，也不代表所有第三方 App 的回车处理都一致。未运行与本次修改无关的全量测试。

原生实际操作记录及专项结果在 [evidence/return](evidence/return/)。原生观察页的 `PASS ... ready` 仅表示页面已启动，不是验收结论。
