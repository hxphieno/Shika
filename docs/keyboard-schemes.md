# 键盘方案

当前提供「中日混合」和「双拼」两个独立键盘。点击底部 🦌 双向切换；上次方案保存在键盘扩展自己的 UserDefaults。数字页不改变方案，返回时恢复原方案。中日语言状态只在当前控制器生命周期内保留。

两套键盘现已通过共享 Rime 底层实现中文输入。双拼采用小鹤双拼；中日键盘的中、日、混合三个状态暂时统一使用中文全拼，日文转换尚未实现。候选栏支持点选、翻页、空格确认和点按拼音原样上屏。

## 职责

- `Core`：引擎协议、候选/组合模型、方案配置、输入会话和键盘状态。方案、语言模式与字母/数字页面是独立状态。
- `Engine`：Rime 适配、候选纠错编排和 Objective-C/C 桥接；不依赖具体键盘 UI。
- `Schemes/ChineseJapanese`：中文全拼配置、中日模式定义、键盘布局及语言按钮。按钮只报告点击，由控制器持有并下发当前模式。
- `Schemes/Shuangpin`：双拼配置、独立中文布局及生成的音节提示，不依赖中日键盘类。
- `UI/Components`：共享按键、气泡、注音键、候选栏和 Shift 状态逻辑；两个键盘分别持有自己的 Shift 状态。
- `UI/Layouts`：共享底部功能栏及数字标点页。
- `UI/Theme`：尺寸、间距、颜色。
- `KeyboardViewController`：页面与方案切换、偏好保存、iOS textDocumentProxy 对接。

具体 schema 和输入/拼写规则配置由各自 `Schemes` 目录定义。`SKInputSession` 接收配置并执行规则，`SKRimeEngine` 管理主会话和探测会话，`SKCorrectionCandidates` 整合纠错结果，`SKSpellingCorrector` 查询离线索引。按键组件仅发送事件；`SKInputSession` 处理组合、上屏和删除；控制器连接系统 `textDocumentProxy`。日文状态不影响双拼行为。依赖、构建和验证见 [Rime 接入说明](rime-integration.md)。

## 维护边界

- `SKInputEngine`、`SKEngineState`、`SKCandidate` 和会话可以独立编译，不需要 UIKit、Objective-C 桥接或 librime；`test-input-session.sh` 会检查这一点。当前仍在一个键盘扩展 target 内，无新增 framework。
- 当前规则配置保留已有空格选词、回车/标点先提交、单次提交输出、大小写直输和纠错保护行为。三种中日模式仍然共用中文转换，不代表实现了日文解码。
- `SKRimeRuntime` 在 Objective-C 桥接内部初始化进程级资源，`SKRimeSession` 管理各自会话。同一进程重复加载必须使用相同资源/用户目录；销毁一个会话不会终止其他会话。
- 修改双拼映射时编辑 `Vendor/RimeData/shuangpin-layout.json`，运行 `python3 scripts/generate-rime-schemas.py` 生成 UI 提示及 Rime schema。`--check` 可只读检查生成物是否过期。更新正式词库仍使用 `scripts/build-rime-data.sh`，纠错索引从生成的 schema 派生。
- 数字符号页保留独立布局和样式，不参与此次架构合并。

## 小鹤键位来源

- https://flypy.cc/
- https://github.com/rime/rime-double-pinyin/blob/master/double_pinyin_flypy.schema.yaml

普通单字母声母沿用字母；U/I/V 额外标出 sh/ch/zh。下方标韵母，多韵母分两行显示。ü 使用拼音字符显示（编码中的 v），üe 对应 ue/ve 写法。引擎实现了小鹤双拼编码及零声母规则，不含小鹤音形辅码。上游 schema 仅为键位研究参考；产品 schema 由项目自己的映射生成脚本创建。

## 验收

1. 默认中日页，点击 🦌 到双拼；再次点击返回。
2. 双拼有 26 个字母，无日文长音键、无中日语言切换。
3. 切换前后的中日语言状态保持；重新创建控制器恢复上次输入方案。
4. 双拼进入 123 页，点击返回仍是双拼。
5. 双拼 `nihc` 出现「你好」，点候选或空格上屏；全拼 `nihao` 同样可上屏。组合期间删除编码，空闲时删除已上屏文字；换行先确认组合再插入换行。
6. 双拼 Shift 单击为单次大写，双击或长按锁定，再单击回小写。
7. 检查 320、390、430 点宽度下的键位、双行韵母与气泡；真机确认触摸手感和键盘扩展生命周期。
