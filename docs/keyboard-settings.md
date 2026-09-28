# 键盘显示设置

入口：主应用左上角三条杠菜单 → 键盘设置 → 自然码双拼 → 学习版双拼。

默认开启，保留声母、韵母小字。关闭时双拼键盘使用普通 26 个字母键；声母韵母映射、输入事件、大小写、纠错、词频学习均保持原有逻辑。再次开启时恢复提示。设置在键盘下一次显示时读取。

主应用写入 App Group 的 `keyboard-preferences.json`，键盘扩展只读取该显示设置；输入和词频记忆继续保存在扩展私有目录。共享代码位于 `ShikaKeyBoard/Core/SKKeyboardPreferences.swift`，同时加入主应用编译目标。Debug 使用 `group.funno.Shika`，Release 使用 `group.cc.kinyo.shika`。两目标使用同一个 `Shika.entitlements`；真机和发布签名的 App IDs / provisioning profiles 必须包含对应 App Group，现有手动发布描述文件需要同步更新。

无需改变键盘的 `RequestsOpenAccess`：Apple 允许未开启完全访问的键盘只读访问主应用共享容器，见 [Apple 的键盘访问说明](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)。

`Tests/KeyboardPreferencesChecks.swift` 验证默认开启、跨进程关闭状态、再次开启、损坏文件回退，以及存储不可用时报错。可将它与共享设置源文件一同用 `swiftc` 编译，然后对同一个临时目录依次运行 `write` 与 `read` 模式。

本次设置读写检查与工程配置检查通过。完整 iOS 编译及界面验收受本机 CoreSimulator 初始化等待和部分 iCloud 文件未下载影响，尚未完成。
