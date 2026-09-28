# 自然码双拼

当前双拼采用用户于 2026-09-26 提供的自然码键位图。方案菜单、键盘提示和引导页标注「自然码双拼」，候选区输入法图标仍显示「双拼」。

`Vendor/RimeData/shuangpin-layout.json` 是键帽与后端编码的共同来源。图中的 `van/vn/ve` 在键帽中显示为 `üan/ün/üe`；`ue/ve` 合并显示 `üe`。零声母沿用 `aa/oo/ee`、`ai/ei/ao/ou/an/en/er`、`ah/eg`。例如「你好」为 `nihk`，「世界」为 `uijx`，「鹿键喵」为 `lujmmc`。

内部 schema ID 保留 `shika_flypy`，用于兼容现有引用；它加载的实际规则已经是自然码。Rime 的 `pinyin_simp` 用户词库保存拼音读音，继续共享，保留选词学习与词频。纠错辅助 schema、prism、静态纠错索引和音节表均随码表重新生成。

本地按键纠错记忆由 `double-pinyin-spelling.json` 一次性转写到 `ziranma-double-pinyin-spelling.json`，只转换每个音节的第二键，零声母特殊编码保持不变。保留旧文件；新文件存在时不重复导入。容量、文件大小限制和候选原生校验保持原样。

验证入口：

- `python3 scripts/verify-shuangpin-layout.py`：独立核对图片码表、音节覆盖、键帽、打包 schema 和纠错音节表。
- `bash scripts/test-rime-native.sh`：原生转换冒烟检查。
- `bash scripts/test-shuangpin-behavior.sh /tmp/shika-ziranma-checks`：确认、退格、切换、纠错、自造词跨进程记忆、索引边界及旧码迁移。
- `python3 scripts/derive-ziranma-cases.py`：将两组既有双拼质量样本按原词语与错误类型转写为自然码，不据引擎结果修改目标。

历史 `docs/evidence` 截图和报告保留其原始小鹤输入，不代表当前码表。

本次 macOS 原生验证：122 项行为、学习、跨进程记忆和索引检查，以及 19 项真实旧方案升级检查全部通过。两组共 1,320 条质量样本无意外上屏；命中率与耗时见 `docs/validation/ziranma/quality-summary.json`，这不表示所有错码都能命中。

iOS 键盘扩展 Swift 编译完成。完整 App 模拟器构建受本机 CoreSimulator 服务不可用影响（资源编译报告无可用模拟器运行时）；未完成完整打包与模拟器界面验收。
