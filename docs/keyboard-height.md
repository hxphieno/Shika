# 候选栏与键盘高度

两张真机照片中，候选文字和按键的位置基本相同，键盘背景上沿却相差约 17pt。照片只能确认外框留白变化，不能单独证明是哪一次系统布局触发的。

代码中发现并修正了两处不稳定因素：

- 原来仅给中文/日文按键页设置 999 优先级高度，由内部约束间接推导整个输入视图的高度。现在启用 `UIInputView.allowsSelfSizing`，直接约束根输入视图：竖屏 260pt（44pt 候选栏 + 216pt 按键区），紧凑竖向尺寸 206pt（44 + 162）。所有页面共享这一尺寸。高度仍采用 999 优先级，让系统在切换或旋转的临时尺寸下避免 required 约束冲突。
- 原来每次布局都沿父视图链关闭 `clipsToBounds` / `masksToBounds`，甚至修改系统窗口。现在删除这个旧补丁，保留系统管理的圆角和裁剪。现有按键预览本来就挂在输入视图内部并限制其边界，不依赖该补丁。

选择保留候选栏及系统外框，不额外加入顶部 padding，不使用负偏移或私有 API 移动系统外框。260pt 是扩展内容高度，不包含系统地球键、听写区域或系统可能添加的外部装饰；这些仍由 iOS 管理。

依据：[Apple 的自定义键盘布局说明](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface)、[allowsSelfSizing](https://developer.apple.com/documentation/uikit/uiinputview/allowsselfsizing)。

## 回归验证

```sh
python3 scripts/test-keyboard-height.py <booted-simulator-UUID>
```

测试使用真实控制器、候选栏、按键及输入会话，搭配固定候选引擎，独立于词库下载。检查三次输入框聚焦/收起、候选展开、数字/字母页、方案切换、气泡边界、横竖屏尺寸，以及父容器裁剪属性不被修改。原生表情键盘由系统管理，不属于扩展内部页面。它不替代真机上的跨进程键盘扩展验证。

2026-09-26：iOS Release 构建及独立的符号/模式/系统键盘切换回归已通过。高度测试脚本已补入数字页依赖的 `SKSymbolKeyButton.swift`，可以编译；但当前 iOS 26.5 模拟器测试宿主在生成截图时 `image.pngData()` 返回 nil，随后中断，尚未取得完整高度回归结果。重新显示模拟器软件键盘后重试仍未完成。需继续验证该测试宿主，并在真机反复切换系统键盘、收起/唤起、横竖屏及不同输入 App，确认系统外框留白稳定。
