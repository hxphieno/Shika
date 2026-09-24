# Simulator 运行时证据

- `first-run/`：120 次方案切换。20→120 增长超出 8 MiB，原始 FAIL 保留。
- `memory-isolation/`：Mac 七组 500 轮分离实验，排查原生 Rime、重建会话、只读索引与纠错检索/提交；仅作定位，不能代替 iOS 测量。
- `final-run/`：300 次交替方案，1,687 次逐键事件；120→300 净变化 −49,152 bytes、跨度 49,152 bytes，沿用原门槛 PASS。全曲线显示第 120–260 次一致，第 280–300 次下降，功能错误为零。

报告由 `Tests/AutocorrectionRuntimeChecks.swift` 读取当前进程 `TASK_VM_INFO.phys_footprint` 生成；不是估算资源文件大小。每次运行使用新 userdb。重复小词集用于压力/保持检查，不纳入纠错准确率。

环境为 iOS 26.5 Simulator UIKit host，运行生产 Rime、Swift 引擎、键盘视图和测试文本代理，Swift 未开启优化；不是键盘扩展进程或物理 iPhone。PNG 为 CALayer 渲染的功能截图；系统材质的像素验收使用主任务屏幕截图。

完整结论、初次失败原因的审慎解释、资源/进程内存区别见 `../../autocorrection-validation.md`。
