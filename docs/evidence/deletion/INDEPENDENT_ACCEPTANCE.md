# 删除键独立验收

最终结果：**145 项通过，0 失败**。验收者只新增测试与证据，没有修改生产实现。最终运行从当前工作区源码重新编译，使用 iOS 26.5 模拟器的真实 UIKit 测试宿主。

复现：

```sh
SHIKA_SMOKE_SOURCE=Tests/DeleteInteractionAcceptanceChecks.swift SHIKA_SMOKE_TIMEOUT=90 python3 scripts/test-keyboard-simulator.py 36E38A3E-C462-4407-AF14-33D8644AB207
```

## 实际检查内容

- 主键盘和数字页按下立即删除一次、松手不补删；真实 run-loop 定时器的起始等待、连续删除、持续按住后的按词阶段。
- 移出暂停、移回沿剩余节奏恢复而不额外立即删除；取消、松手到外部、控件禁用、祖先隐藏/透明/禁用交互、移出窗口及失活通知后停止。
- 新删除控件开始时取消旧控件；VoiceOver 激活只删除一次，没有延续定时器。
- 原生 `UITextView.deleteBackward` 作为 Unicode 对照：中英数字、标点换行、emoji、家庭 ZWJ、肤色、旗帜、组合音符、键帽以及文字连接字符；选区在按词阶段仍仅做一次原生编辑。
- 单词、尾部空格、标点、换行及长标识符的有界删除；上下文未及时更新、上下文窗口移动、文档变化、空上下文、nil 文档身份时不会继续批量删除。
- 两种主键盘及数字页通过真实生产 controller/session 处理删除；预编辑删空保留正文，并重新等待后才继续正文。其他按键、切页、切方案、外部光标变化及键盘消失会取消持续删除。
- 日文完整假名按可见字符删除，未完成罗马字按一个字母删除；包含拗音、促音、拨音、长音、残留辅音及已完成字面输出。真实 markedText 检查覆盖 `きゃ→き→空` 和 `がっk→がっ→が→空→正文`。

## 独立验收找到的实际问题

首轮 115 项中有 1 项失败：`gakk` 显示为 `がっk`，删除未完成的 `k` 后错误变成 `がk`，已完成的促音也被回退。实现修复后，增加 `kk/ss/tt/ssa/kky/sshi` 等同类情况及真实文本框检查。最终也覆盖 `www` 所含字面前缀的连续删除、删后续输、清空、替换及提交，避免重新解释已完成的字面内容。首轮失败证据保留在 `independent-first-run`，最终结果在 `independent-final`。

## 证据及方法边界

`independent-final/deletion-results.json` 保存所有断言以及长按、暂停恢复、加速和预编辑边界的实际回调时间。`source-hashes.txt` 标识最终检查的相关源码。

以下外观截图由真实生产键盘视图渲染；为了稳定呈现按下态，测试显式设置 UIKit `isHighlighted`，因此属于状态截图，并非物理手指按压照片：

- `delete-main-pressed.png` / `delete-main-released.png`
- `delete-number-pressed.png` / `delete-number-released.png`

测试通过公开 `UIControl` 事件派发驱动状态机，使用真实 run-loop 定时器和真实 `UITextView`。它验证控制逻辑及原生文本编辑结果，**不等同于物理手指长按、手指移动轨迹、真机触控容差或 VoiceOver 完整操作流程**。失活场景通过通知派发检查取消响应。本文不声称测得或复刻 Apple 未公开的精确长按时序；当前节奏是项目声明的参数。数字符号布局和其他键盘 UI 不在本次改造范围。
