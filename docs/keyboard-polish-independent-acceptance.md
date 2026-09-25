# 五项键盘调整：独立验收

2026-09-25，由未修改生产实现的验收 agent 单独编写测试并执行。生产实现前四项对应 `90964ef`、`9d549cf`、`7771f73`、`f219b42`；第五项 `a85351e` 包含扩大热区及后续发现的候选自然宽度修复。

## 结果与范围

- **1070 项 UIKit 宿主验收通过**。测试使用项目真实 `KeyboardViewController`、键盘视图、Rime 引擎；文本接口使用记录 marked text/commit 的 `UITextDocumentProxy` 替身。
- **2 项跨进程验收通过**。第一进程通过语言按钮切至日文并持久化；执行 `simctl terminate` 后重新 `simctl launch ... verify-persistence`，验证新控制器恢复日文标识及布局。第二进程结束时恢复测试宿主原来的偏好。
- 环境：iPhone 17 Pro Simulator，iOS 26.5。未操作用户手机。这里的截图是测试宿主中真实视图的渲染，透明区域合成白底以便阅读，**不是系统键盘扩展截图或真机截图**。
- 此套测试通过布局与 UIKit `hitTest` 检查触摸归属，并验证滚动视图可取消按钮触摸；程序设置 content offset 验证滚动不改写输入。主任务补充的真实扩展检查已验证双拼/全拼上屏、数字符号输出及符号区从按钮开始横拖到尾列且不误上屏。候选横拖的 CUA 操作尚未观察到明确位移，只确认没有误上屏；因此此报告**不把内容宽度/程序设置 offset 的通过冒充为真实候选拖动已经验证**。

复现完整两阶段验收：

```sh
python3 scripts/test-keyboard-acceptance.py
```

## 补充回归：候选标题压缩

主任务在随后真实键盘扩展的手动拖动中发现：展开再收起后，双字候选被压窄成上下两行。原 482 项断言只检查最小 44 pt 热区及单字候选滚动，**没有覆盖多字标题的自然宽度**，不能据此认为候选横滑已完整验收。

生产实现随后为候选设置单行文字及自然文字宽度加左右留白的固定宽。独立验收已补充真实 Rime 的“世界”候选，在展开前/展开后收起检查每一项宽度、单行文字实际高度及总内容宽；另以双字、长词混合列表覆盖 320/402/874 pt 宽度。补充版现已运行通过：主验收共 **1070 项**，并再次通过 **2 项跨进程恢复检查**。实际查看中日/双拼“世界”候选展开收起后的渲染截图，双字候选保持完整横排；自然宽度及单行高度断言全部通过。

## 逐项检查

1. **按键气泡**：中日、双拼分别检查 Q/P/W/E/R/X/D/H；覆盖 320、402 pt 竖屏，以及 874 pt compact 横屏。布局后强制键盘根视图裁切，检查气泡归属根视图、完整边界在根视图内、阴影边缘留白、文字气泡高于原按键、不抢触摸、取消时移除。已人工查看 Q/P/W 和横屏 P 图片，没有顶部或两侧裁切。
2. **模式标识**：两方案、三种宽度的空候选标识容器左边缘与 Q 按键左边缘误差小于 0.5 pt；输入 ni 后标识隐藏，候选栏回收原标识宽度；展开/收起不重新显示标识；确认候选后标识恢复。
3. **中日模式记忆**：中文、日文、中日混依次通过按钮切换，每种均验证方案切走再回来、关闭及重建控制器后保留。另有上面的真正进程重启日文恢复测试。
4. **数字与符号**：保留左侧数字、右侧横向符号区。60 个选项无重复，常用中文标点、独立开闭括号、日文引号、ASCII、货币与运算字符存在；每一个符号及 0–9 点击均检查实际提交字符与键面一致；滚动不提交文字，返回恢复字母页。人工查看首尾符号列，分组及边界正常。
5. **热区**：展开箭头边角可点击且至少 48×44 pt（实现为 52×44 pt）；每候选至少 44×44 pt；从候选/符号按钮发起拖动时滚动视图允许取消按钮触摸。三种宽度验证数字中心、数字 1/2 间隙左右半区、所有字母中心的命中归属，主键和数字页不能抢到候选区域；展开/收起保持原 marked text。

## 关键证据

主任务最终回归：54 项输入会话检查、学习跨进程及共享 Rime 运行时检查、119 项主键交互检查通过；最终候选宽度实现再次通过 30 项真实 UITextView 的待确认文本及展开候选检查。模拟器 Debug 与 iPhone Release（不签名）构建通过，最终模拟器应用的资源包检查通过。未进行实体手机安装验收。

旧 marked-text 测试将嵌套 RunLoop 等待改成主 actor 的异步逐键等待，使 UIKit 的文本选择通知在事件间完成；断言要求保持不变，另补充失败时的实际文本。独立 agent 复核确认没有放宽验收。

候选拖动的补充诊断：测试宿主实际内容宽 570 pt、视口约 343 pt，滚动与交互均启用，窗口 hitTest 命中候选按钮；同位置点击成功，CUA 拖动时未命中 UIScrollView 的 handlePan 断点。现有证据无法确定是手势实现还是自动化输入问题，保留这一实际手势验收缺口。用于隔离模拟器键盘切换的临时设置已恢复为检查前的两个键盘及其原顺序。

- [结果：1070 项](evidence/keyboard-polish/keyboard-acceptance-main-result.txt)、[结果：进程重启 2 项](evidence/keyboard-polish/keyboard-acceptance-persistence-result.txt)
- [Q 气泡](evidence/keyboard-polish/acceptance-preview-shuangpin-402-q.png)、[P 气泡](evidence/keyboard-polish/acceptance-preview-shuangpin-402-p.png)、[W 气泡](evidence/keyboard-polish/acceptance-preview-chineseJapanese-402-w.png)、[横屏 P](evidence/keyboard-polish/acceptance-preview-chineseJapanese-874-p.png)
- [空候选模式](evidence/keyboard-polish/acceptance-mode-empty-chineseJapanese.png)、[有候选隐藏模式](evidence/keyboard-polish/acceptance-candidate-filled-chineseJapanese.png)
- [符号首列](evidence/keyboard-polish/acceptance-symbols-first.png)、[符号尾列](evidence/keyboard-polish/acceptance-symbols-last.png)
- [进程重启恢复日文](evidence/keyboard-polish/acceptance-mode-after-relaunch.png)

- [全拼双字候选展开收起后](evidence/keyboard-polish/acceptance-phrase-candidates-chineseJapanese.png)、[双拼双字候选展开收起后](evidence/keyboard-polish/acceptance-phrase-candidates-shuangpin.png)
