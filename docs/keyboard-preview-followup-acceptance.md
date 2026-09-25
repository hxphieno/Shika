# 按键气泡与候选展开按钮：独立复核

复核者：独立验收 agent（未修改生产实现）。环境：iPhone 17 Pro / iOS 26.5 Simulator，使用真实键盘控制器、视图、RIME 引擎的独立 UIKit 验收宿主。

实现分别提交为 `67b5bff`（固定气泡头部、边缘直腰）与 `ddc9192`（展开按钮热区、反馈及按需预取）。

## 结果

- `scripts/test-keyboard-acceptance.py`：3116 项通过；另一次真正终止并重新启动宿主后的模式恢复检查 2 项通过。
- 保留原有输入、模式记忆、符号输出、候选宽度及主键命中检查，并增加下述专项覆盖。
- 主 agent 补充回归：30 项真实 UITextView 待确认文本及候选展开检查、54 项输入会话检查、跨进程学习和共享 Rime 运行时检查通过；最终模拟器 Debug 与 iPhone Release（不签名）构建和离线资源包检查通过。
- 双拼与中日布局，320 / 402 / 874pt 宽，Q/P/W/E/R/X/D/H：根视图强制裁切时气泡仍在可见区域内，取消按压后消失，不参与触摸命中。
- 独立采样实际渲染 alpha 轮廓：气泡帽在 y=15/25/35/45/50pt 处保留完整宽度，避免只比较实现内部的高度参数；Q/P 外侧贯穿帽和腰保持直线，腰部逐行收窄、没有倒折。原始 8pt 按键底部圆角不属于直线或腰部验收范围。文字字号保持 37pt。
- 已逐张查看 Q/P/W/D 与横屏 P 图：帽与字形完整，边键外侧直、内侧收窄，顶部没有压扁。图片使用宿主视图的 layer 渲染，**不是实际键盘扩展截图**。
- 展开按钮完整 60×44pt 区域四角命中；首次命中不越界抢占左侧候选和下面主键，按下/松开提供高亮反馈。
- 两布局分别重复展开/收起 20 轮，布局与 marked text 保持正确。首次展开加载超过 8 个候选，反复开合不继续追加候选页。
- 最新实现中，20 轮里最慢的同步“展开 + layout + 收起 + layout”耗时：双拼 5.32ms，中日 5.99ms。此前每次开合追加候选的实现对应约 32.27ms / 29.41ms。这是本次模拟器样本，不是实体设备帧率或延迟保证。

## 边界与复核方式

本套检查通过 UIKit hitTest 和控件 action 验证热区及状态切换，不将它等同于真实手指拖动验证。实际 Simulator 点击/拖动由主 agent 另行验收；本报告不声称验证了手指漂移状态或候选横滑，也未进行实体手机测试。

主 agent 已补充 CUA 实际坐标点击：在上述宿主输入 `ni` 后，依次点击展开按钮左上、右下、右上、左下角（距可见热区边缘约 3pt），每次均观察到候选面板正确展开或收起，未选中旁边候选、未输入下方字母。

最终应用安装到模拟器后，系统地球键虽然列出 Shika，却回到了系统英文键盘；重启此开发模拟器后仍未完成扩展切换。日志能看到扩展安装注册，没有本次 ShikaKeyBoard 进程启动日志或新的扩展崩溃记录，尚未确定原因。本轮实际扩展启动复查因此未完成；不能把上述验收宿主的通过当作最终扩展或真机验收通过。未更改系统键盘偏好列表。

第一次专项检查暴露两项 P 外侧失败；具体像素仅落在底部圆角起点后 1pt。检查原误将圆角当成 7pt，已按实际原始 8pt 圆角排除，未放宽 alpha 阈值或腰部断言。之后完整复跑通过。

## 证据

- [Q](evidence/keyboard-preview-followup/acceptance-preview-shuangpin-402-q.png)
- [P](evidence/keyboard-preview-followup/acceptance-preview-shuangpin-402-p.png)
- [W](evidence/keyboard-preview-followup/acceptance-preview-shuangpin-402-w.png)
- [D](evidence/keyboard-preview-followup/acceptance-preview-shuangpin-402-d.png)
- [横屏 P](evidence/keyboard-preview-followup/acceptance-preview-shuangpin-874-p.png)
- [3116 项结果](evidence/keyboard-preview-followup/keyboard-acceptance-main-result.txt)
- [跨进程结果](evidence/keyboard-preview-followup/keyboard-acceptance-persistence-result.txt)
- [双拼耗时](evidence/keyboard-preview-followup/disclosure-timing-shuangpin.txt)
- [中日耗时](evidence/keyboard-preview-followup/disclosure-timing-chineseJapanese.txt)
