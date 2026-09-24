# Rime 接入

两套键盘共用 Rime 1.17.0。界面中的「双拼」使用小鹤编码规则及 `shika_flypy`；中日键盘的中、日、混合状态目前全部使用中文全拼 `shika_pinyin`。日文转换、跨语言词库与排序尚未实现。

## 层次与输入行为

```text
独立键盘 UI / 独立方案 schema 身份
               ↓ 按键事件
KeyboardViewController → SKInputSession
                              ↓ SKInputEngine
                         SKRimeEngine (Swift)
                              ↓
                         SKRimeSession (Objective-C)
                              ↓ C API
                         librime + 离线词库
```

`SKInputSession` 管理编辑策略，返回文字通过控制器的 `textDocumentProxy` 插入宿主应用。引擎快照包括组合、原始编码、候选、页码和一次性上屏结果。按键组件不直接访问 Rime。之后接入日文可独立增加 schema/方案策略，不需要复制底层桥接。

- 字母形成组合；点候选或空格确认，候选可横向滚动及翻页。部分选词可保留剩余组合。
- 点候选栏顶部拼音可原样上屏字母。
- 组合内退格删除编码，组合外退格删除宿主文字。
- 换行、标点、数字、大写字母以及切换方案/数字页会先确认当前组合。
- 离开键盘或宿主改变文本位置时取消未确认组合，避免在新位置误上屏。
- 词频学习留在扩展私有 `Application Support/RimeUser`，随会话销毁释放 Rime session。Rime 进程级运行时只初始化一次，调用由锁串行保护。

## 依赖与可复现构建

本次使用固定版本的预编译静态 XCFramework，在本机编译 Objective-C 桥接、Swift 键盘并静态链接；没有声称在本机从源码重编全部 librime 依赖。来源是 [librime-xcframework 1.17.0-pack.9.0.3](https://github.com/ghostflyby/librime-xcframework/releases/tag/1.17.0-pack.9.0.3)，上游为 [rime/librime](https://github.com/rime/librime)。源码和打包提交在 `Vendor/Rime/build-metadata.json` 中。

XCFramework 含 iOS arm64、iOS Simulator arm64/x86_64 和 macOS arm64/x86_64 静态库。体积较大，未纳入 Git；当前工作区已恢复。新检出首先运行：

```sh
bash scripts/prepare-rime.sh
open Shika.xcodeproj
```

下载脚本校验固定 SHA-256：`abdd6240e740043933b9241bd6e1d1be1ce0c06d457c6c65931e06c0ccaec37e`。下载仅发生于开发准备阶段；安装后的键盘无需网络、首次启动无需下载词库。

中文词库采用 [rime-pinyin-simp](https://github.com/rime/rime-pinyin-simp) 的 AOSP 衍生词库，固定提交及 SHA-256 在 `Vendor/RimeData/provenance.json`，并已对固定提交内容复核。项目自行根据拼音音节和小鹤键位生成 schema，没有打包上游 GPL 双拼 schema。双拼含 413 个音节映射，使用独立 prism，与全拼共用字典及中文学习数据。

离线资源已预编译并纳入 Git，位于 `ShikaKeyBoard/Resources/RimeData.bundle`。修改字典或方案后运行：

```sh
bash scripts/build-rime-data.sh
python3 scripts/collect-rime-notices.py
```

构建脚本在 macOS 上调用真实 Rime 部署器生成二进制字典。运行时只读取包内预编译资源，不在扩展内做部署，也不修改签名包。更新 librime 版本时必须重新生成并测试这些二进制资源。

## iOS 与审核相关实现

按 [Apple 自定义键盘文档](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard) 使用 `UIInputViewController` 和 `textDocumentProxy`。扩展开启 `APPLICATION_EXTENSION_API_ONLY`；库静态链接到扩展，运行时仅链接系统框架，没有额外动态 Rime 框架。仅初始化 Rime default 模块，不提供运行时下载代码或用户脚本入口。

顶部工具栏不再自行绘制地球按钮，系统提供的底部键盘切换入口不受此改动影响。`RequestsOpenAccess=false`，本地转换与学习不要求完全访问。主应用提供启用说明、试打区、隐私说明和可阅读的许可文本。发布前仍需按 [App Review Guidelines 4.4.1](https://developer.apple.com/app-store/review/guidelines/#extensions) 核验支持机型的系统键盘切换行为。

`PrivacyInfo.xcprivacy` 声明 UserDefaults 的 `CA92.1` 与扩展容器文件时间戳的 `C617.1`，不跟踪、不收集上传数据。Release arm64 的符号检查确认使用 `NSUserDefaults`、`stat/fstat`、文件时间接口，未发现磁盘空间、系统启动时间或活动键盘查询符号；声明依据见 [Apple required reason API 文档](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)。后续更新依赖仍需重新核对实际调用。

librime 使用 BSD-3-Clause；字典使用 Apache-2.0。完整第三方通知保留于 `Vendor/Rime/third-party-notices`，并合并到主应用及扩展的 `ThirdPartyNotices.txt`。本次使用的打包版本记录插件及其具体许可版本；升级时不能只沿用当前许可结论。

这些是工程侧的审核准备，不等于 App Store 已批准。正式发布仍需分发签名、Archive/App Store Connect 验证、商店隐私信息与隐私政策地址，以及真机性能和生命周期回归。当前未上传或提交审核。

## 验证方式

```sh
# 新的临时用户词库，真实原生 Rime 转换、翻页、选词、删除和一次性上屏
bash scripts/test-rime-native.sh

# 独立生产 Swift 会话验证与跨进程词频学习
bash scripts/test-input-session.sh

# 已启动的 iOS 模拟器；生产 UIKit 按键 + 生产引擎 + 测试文字代理
python3 scripts/test-keyboard-simulator.py

# iOS 模拟器工程构建
xcodebuild -project Shika.xcodeproj -scheme Shika -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/shika-build build

# 真机架构 Release 编译链接，不涉及签名/安装
xcodebuild -project Shika.xcodeproj -scheme Shika -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/shika-release CODE_SIGNING_ALLOWED=NO build

python3 scripts/check-rime-bundle.py /tmp/shika-release/Build/Products/Release-iphoneos/Shika.app
```

UIKit 测试会输出 `Documents/result.txt` 及 320/390/430 点宽度的截图，使用可检查文字的测试代理。它不能替代系统扩展验收。系统验证应在设置中启用 Shika 后，通过真实输入框分别使用 `nihc` / `nihao` 选出「你好」，并检查删除、切换、重启后的词频学习与无需完全访问。

实际测试结果与独立复核记录见 [验证记录](rime-validation.md)。
