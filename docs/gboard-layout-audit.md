# iOS Gboard 双拼键位核对

核对日期：2026-09-25。执行者：独立验证 agent。范围：主字母键盘的双拼编码；不包含数字／符号页，也不涉及候选区域的视觉调整。

## 结论与证据边界

当前 Shika 的双拼主编码是小鹤方案。独立运行官方 Rime 小鹤方案的拼写运算，逐一对照 Shika 生成的 **413 个音节主编码，413/413 一致，0 个差异**。键帽的 26 个韵母标注、`sh/ch/zh` 声母位置，与这些主编码一致。

**尚不能证明这就是当前 iOS Gboard 的“默认双拼”方案。** Google 当前公开的 iOS 帮助没有声明默认双拼是哪一种。历史 iOS Gboard 设置截图显示的是六种不同双拼方案；“Gboard”是输入法产品，并不唯一确定声韵母映射。在没有实际 iOS Gboard 版本号、方案选中状态和键位截图前，不应把小鹤、自然码或微软任一套擅自标成 Gboard 默认，也不应据此改动用户已经能用的键位。

因此，本次审计没有修改生产键位。完成了当前布局的全量一致性验证，但 **“与指定 Gboard 默认方案一致”的验收仍需要实际参考证据**。不能将这个审计记为已完成 Gboard 像素或默认键位的实机对齐。

## 来源与可支持的结论

| 来源 | 类型 | 支持的结论 | 不能推出的结论 |
| --- | --- | --- | --- |
| [Google：Set up Gboard — iPhone & iPad](https://support.google.com/gboard/answer/6380730?co=GENIE.Platform%3DiOS&hl=en) | 官方 iOS 帮助 | iOS Gboard 支持中文、可添加语言 | 未公布默认双拼方案或完整键位表 |
| [Google 发布的 iOS App Store 页面](https://apps.apple.com/us/app/gboard-the-google-keyboard/id1091700242) | 官方商店产品说明 | 查询时展示 2.3.19、2022-05-02，支持简体中文 | 版本说明和产品描述未公开双拼默认值 |
| [小鹤官方](https://flypy.cc/) | 方案作者 | 小鹤是可单独选择的双拼方案 | 不是 Google 默认方案的声明 |
| [Rime 官方小鹤配置，固定提交](https://github.com/rime/rime-double-pinyin/blob/6e2e2262200a98496fd85327c9d3863a56897780/double_pinyin_flypy.schema.yaml) | 开源实现的一手源代码 | 可独立计算小鹤声母、韵母、零声母及别码 | 不说明闭源 iOS Gboard 的出厂选择 |
| [Google：谷歌拼音支持的双拼方案](https://support.google.com/pinyin/answer/93317?hl=zh-Hans) | 官方旧产品帮助 | 桌面谷歌拼音曾支持多套双拼 | 产品与平台不符，不能用作 iOS Gboard 默认依据 |
| [2017 年 iOS Gboard 设置的历史报道和截图](https://www.appinn.com/gboard-shuangpin-for-ios/) | 第三方历史观察 | 提供复查 iOS 六套方案界面的线索 | 非当前版本、非恢复默认实验，不能证明当前默认方案 |

没有以 Android Gboard、桌面谷歌拼音、iOS 原生双拼的默认值代替 iOS Gboard。网上存在把这些产品混为一谈的教程，未采用其中未经一手资料验证的技术结论。

## 当前 Shika 完整键位

物理字母排列：`QWERTYUIOP / ASDFGHJKL / ZXCVBNM`。普通单字母声母保留在本字母键；`sh` 在 U，`ch` 在 I，`zh` 在 V。下表中“韵母”列为键帽事实与实际编码的对照，不代表已经验证的 Gboard 默认键位。

| 键 | 特殊声母 | 韵母 |
| --- | --- | --- |
| Q | — | iu |
| W | — | ei |
| E | — | e |
| R | — | uan |
| T | — | üe（拼音编码 ue/ve） |
| Y | — | un |
| U | sh | u |
| I | ch | i |
| O | — | o / uo |
| P | — | ie |
| A | — | a |
| S | — | ong / iong |
| D | — | ai |
| F | — | en |
| G | — | eng |
| H | — | ang |
| J | — | an |
| K | — | ing / uai |
| L | — | iang / uang |
| Z | — | ou |
| X | — | ia / ua |
| C | — | ao |
| V | zh | ui / ü（编码 v） |
| B | — | in |
| N | — | iao |
| M | — | ian |

零声母主编码：`a→aa, o→oo, e→ee, ai→ai, ei→ei, ao→ao, ou→ou, an→an, en→en, ang→ah, eng→eg, er→er`。

## 独立验证方法与结果

读取 `ShikaKeyBoard/Schemes/Shuangpin/SKShuangpinLayout.swift`、`scripts/generate-rime-schemas.py` 和实际生成的 `Vendor/RimeData/shika_flypy.schema.yaml`，不调用项目的编码生成函数来生成期望值。

在临时目录读取上述固定提交的 Rime 官方配置，独立解释其 `derive`、`xform`、`xlit`、`erase` 操作。对实际 schema 中每个 `xform/^音节$/编码/` 规则，验证该编码是否在官方运算结果集合内。上游文件 SHA-256：`6b522a7e9cb743474287a14678597460bd124369f32573dd63e8f04e7c41d4b9`。

可复跑：`python3 scripts/verify-shuangpin-layout.py`（从固定提交读取参考），或 `python3 scripts/verify-shuangpin-layout.py --reference /path/to/double_pinyin_flypy.schema.yaml`（校验相同 SHA-256 后离线核对）。测试脚本只在验证时读取官方方案，不把其内容复制到应用资源。

结果：413 个主编码和 32 个韵母标注全部通过；音节覆盖来源是项目当前拼音字典。该验证不声称覆盖字典之外的全部汉语音节，也不代替真实引擎的组词测试。

发现官方 Rime 还接受 10 个兼容别码，当前 Shika 没有生成：

| 音节 | Shika 已支持主编码 | 官方附加别码 |
| --- | --- | --- |
| ai | ai | ad |
| an | an | aj |
| ao | ao | ac |
| ei | ei | ew |
| en | en | ef |
| ou | ou | oz |
| ju | ju | jv |
| qu | qu | qv |
| xu | xu | xv |
| yu | yu | yv |

这些是兼容性扩展，不是主键位错误；是否引入应独立决定，不能冠以“Gboard 默认要求”。

## Gboard 参考的可复现验收条件

1. 在装有 Gboard 的 iPhone 上记录 iOS 版本、Gboard 版本、中文语言类别和完整拼音方案列表。
2. 观察新添加中文语言／选择双拼后的实际选中方案，区分历史偏好和真正初始选择。不要删除用户现有词库或设置来制造“默认”。
3. 保存主字母键盘和方案设置截图。若键帽不展示韵母，则输入区分方案的探针：`nihc`（小鹤你好）、`nihk`（自然码你好），并检查 `ing`、`ian`、`iang`、`ong`、`ao`、`an`、`ai` 的落键。
4. 用 12 个零声母、`nv/lv/nue/lue`、`zhi/chi/shi`、每个共用韵母各一词验证实际出字；单看 QWERTY 字母排列不算编码一致。
5. 若最终参考确实是小鹤，保留 413 个现有主编码；若是另一套，键帽和引擎必须同时调整，并为旧词频数据保留可迁移的拼音字典层。

本审计没有操作用户设备、安装 Gboard、获取账户数据或修改输入方案。

## 当前环境中的实机参考限制

主 agent 使用设备管理工具只读检查已连接 iPhone 的应用清单，未发现 Gboard 应用。因此当前没有可以直接实测的 iOS Gboard 实例；没有为验证而改动手机设置、安装第三方键盘或清除任何偏好。独立 agent 尝试创建隐藏浏览器查看历史原始截图，但当前 `iab` 不可用，浏览器清单为空；没有亲眼核实历史截图中的勾选位置，不将图片搜索的文字描述当成已完成的截图观察。以上限制不影响对 Shika 413 个主编码与 32 个韵母标注的独立验证，但 Gboard 默认方案对齐仍未得到实机证据。
