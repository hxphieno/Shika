# 候选缺字过滤验收

用户要求只处理当前设备无法正常显示的候选，保留所有原可显示文字。本次不修改、裁剪词库，不按常用字表、Unicode 区段或语言过滤；不改变正常候选顺序、原始 ID、学习规则和按键功能。

## 实现

- `Platform/SKCandidateGlyphCoverage` 使用与候选 UI 对应的 20pt 系统字体，检查完整文字经过 CoreText 排版和字体回退后的实际 run。仅在 LastResort run 确有可绘制墨迹时拒绝候选。
- 不把 glyph 0、补充平面汉字、字面 □/�、零宽字符当作缺字黑名单。字体检测结果按完整 UTF-8 字节缓存，最多 512 项，只缓存不超过 512 字节的文字；不会合并 NFC/NFD 或变体序列。
- `SKInputSession` 接收可显示性检查闭包，纯会话逻辑仍无 UIKit/CoreText 依赖。控制器仅增加一行注入，布局和字体本身未改动。
- 初始与追加候选都过滤；分页沿用原始游标和 ID，保留消费长度元数据。每轮同步最多读取 4 页，仍需补齐时让出主线程后续取；输入、清空、切换会使旧任务失效。连续隐藏页后面的正常词仍能到达。
- 仅当原首选被隐藏时，空格改选当前可见首选。标点/切换需完整提交时，由引擎保留已确认前缀并处理剩余原码；不把内部未检查的后续首选偷偷提交。没有可见候选时仍保留已选前缀。原首选可见时完全走原流程，原码回车保持原行为。

## 实际 iOS 结果

iOS 26.5 模拟器，真实生产控制器、候选网格、Rime 与 UITextView 文本代理：

- 输入 `dmbodnbo`，原始 150 个候选，移除 52 个缺字候选，保留 98 个。
- 全部可显示候选的文字及顺序完全一致，包括末尾原能显示的补充平面汉字。
- 过滤后的末尾候选能以原始 ID 正确选中并显示在文本框中。
- 冻结 32 组字体边界（24 组必须保留、8 组记录设备实际能力）；加 5 项真实 UI/候选检查，共 29/29。

[原候选截图](evidence/candidate-glyphs/glyph-original-ios.png)与[过滤后截图](evidence/candidate-glyphs/glyph-filtered-ios.png)已经实际查看。前者是将原始候选送入同一个生产网格的对照渲染，后者通过真实控制器接线得到；不是图像生成或修改截图。机器可读输出在 `glyph-report.json`。

## 独立验收与失败回放

由未实现生产代码的 continuous_engine_review agent 设计、执行独立检查，覆盖字体/emoji/ZWJ/VS/NFC/NFD、缓存容量、原始 ID/消费长度、220 个连续隐藏候选后的续取、取消/改字失效、全可见时原行为、浏览不学习，以及真实 mixed/Rime 的部分选择和完整提交。

保留以下失败证据，不放宽原预期：

1. 初版 76/77 子集、82/83 完整检查：单独 FE0F 使用 LastResort，但没有可绘制墨迹，不能过滤。改为同时检查 run 墨迹后通过。
2. mixed 已选“今天也”后隐藏所有尾部，旧回退输出 `jintianyearigatouq`，应为 `今天也arigatouq`。引擎专用回退保留前缀。
3. Rime 的 `get_input` 在选中“颠簸”后仍为完整 `dmbodnbo`。旧式清空后插入整串原码会丢失已确认前缀，最终复用原生原码确认路径得到 `颠簸dnbo`。
4. 只允许“颠簸”通过的路由探针中，旧可见前缀自动提交会继续内部选择“调拨”，输出 `颠簸调拨，`。最终异常路径明确提交所选前缀与原码尾巴 `颠簸dnbo，`。这是注入策略的路由测试，不宣称“调拨”缺字。

最终独立 **89/89** 通过，源码哈希和构建结果记录于同目录验收 JSON/审阅文件。中间 88/88 结果单独归档，最终新增可见前缀自动提交检查。iOS 截图所测版本已包含最终字体与会话修复；其后仅增加 Rime 的异常自动提交覆盖，由最终独立原生专项及 iPhone 构建补验。

最初 iOS 测试程序直接调用 datasource 手动 dequeue 单元格，触发 UICollectionView 的验收程序断言。测试改为真实滚动后读取可见 cell，最终 29/29；未为此修改生产网格。一次旧源码编译因开发期间文件变化失败，随后所有最终验收均使用冻结副本。

最终源码的 iPhone 无签名构建通过，离线资源、关闭完全访问、隐私说明和静态 Rime 打包检查通过。最终六个引擎/平台文件与构建副本的 SHA-256 全部一致，见 `device-final-build-result.json` 和 `device-final-build.log.gz`。

## 复验

```sh
bash scripts/test-candidate-glyphs.sh /tmp/shika-glyph-check-fresh
SHIKA_SMOKE_SOURCE=Tests/CandidateGlyphDisplayChecks.swift \
SHIKA_SMOKE_FIXTURE=Tests/CandidateGlyphCases.json \
SHIKA_SMOKE_OPTIMIZED=1 SHIKA_SMOKE_TIMEOUT=120 \
python3 scripts/test-keyboard-simulator.py <空闲模拟器UDID>
```

没有裁剪词库，因此不宣称词库体积、Rime 搜索开销或准确率提升。此次验收是 macOS 原生引擎和 iOS 模拟器，未测实体手机速度。过滤依据运行设备的实际字体能力，不使用此次 Mac/iOS 缺字结果制作全平台黑名单。
