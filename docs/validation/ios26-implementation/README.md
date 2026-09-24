# iOS 26 主键盘改造验收

范围是中日主字母页与双拼主字母页。候选栏、SKConfig、旧按键类、数字／符号布局未修改。数字页仍使用旧组件。参考来源是 iPhone 17 Pro 模拟器 iOS 26.5 的原生简体中文全键盘及日语罗马字键盘，402 pt、3×，原始系统截图及真实按压录屏帧在相邻 `ios26-reference` 目录。

## 实现

- 独立的 `SKMainKeyboardMetrics`、`SKMainKeyButton`、`SKMainKeyboardSurface` 管理主键盘视觉与触点，两个输入方案保留各自键位、状态和双拼声韵母标注。
- 402 pt 下字母键高 43 pt，行距 54 pt，横向间隙 6 pt，圆角约 8 pt；中文第二行九键，日语／混合第二行十键及长音符。深色键帽 RGB 61/61/61；浅色白色。保留鹿按钮及方案空格标题。
- 主字母采用公开系统字体 25 pt，以 CoreText 可见字形边界校准居中。标题矩形直接计算，避免重复 layout 的位置累积；不在标题矩形回调中获取 UIKit 尚未建立的 titleLabel。
- 按下预览约 110 pt 高，中央帽宽约 57.5 pt；左右边缘帽分别按参考收窄并与键帽外边对齐。连续曲线连接帽部与按键。预览覆盖字母键、随松开／取消／移出窗口清除。
- 触点按行、相邻键边界中线分配，视觉间隙可点击；UIControl tracking 使用同一范围。Shift 首击立即生效，双击／长按锁定。删除按下立即一次，长按重复，松开不额外删除。

## 证据与复跑

`chinese/japanese/shuangpin/numbers-宽度-主题.png` 是生产 UIKit 视图的离屏渲染，覆盖 320、375、402、440、874 pt，深浅主题各一组。它们用于键帽／字形／布局核对，不用于证明系统实时材质与动画完全一致。`popup-q/t/p.png` 为生产组件实际 touchDown 后的窗口渲染；系统真实按压参照来自另一 agent 的坐标点击录屏抽帧。

```sh
SHIKA_SMOKE_SOURCE=Tests/MainKeyboardVisualChecks.swift python3 scripts/test-keyboard-simulator.py
SHIKA_SMOKE_SOURCE=Tests/MainKeyboardInteractionChecks.swift python3 scripts/test-keyboard-simulator.py
python3 scripts/compare-main-keyboard-images.py
```

比较脚本使用原生截图中 y1755…2403 的主键盘切片，与 `chinese-402-light.png` 比较 32 个可见键帽边界；结果保存在 `geometry-comparison.json`。最大边界误差 **1 个物理像素**。`native-vs-shika.png` 上方为系统、下方为 Shika；鹿图标与空格方案文字为保留设计。

独立 agent 编写的交互 harness 实测 **111 项通过**：五种尺寸的点击网格无空隙漏点，Shift 首击／双击状态、删除立即／重复／取消／移除与辅助功能激活，以及数字页五次往返后的布局一致性。结果在 `main-interaction-report.json`。

## 证据边界

1 像素是 402 pt 竖屏参考的键帽边界结果，不代表整个系统键盘逐像素完全相同。当前 q 字形边界相对系统仍有最多 2 像素差异；录屏气泡参考受压缩及按压动画阶段影响，不能宣称气泡所有曲线／阴影零误差。其他宽度完成自适应、触点与截图验证，未逐设备采集原生参照。候选区、数字符号页和应用界面都不在本次系统视觉对齐范围内。

最终 Debug 模拟器与 Release iPhone（关闭签名的编译验证）构建通过。原有 UIKit→Rime→文本代理整合回归通过两套方案、三个语言状态、选词、空格、换行、删除、数字页和切方案提交，记录在 `integration-result.txt`。
