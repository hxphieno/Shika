import SwiftUI
import UIKit

/// This card requests a trip to Settings, not permission to enable a keyboard.
struct KeyboardSetupCard: View {
    @Binding var isDeferred: Bool
    var beforeOpeningSettings: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var settingsOpened = false
    @State private var openingSettings = false
    @State private var openingFailed = false

    private let ink = Color(red: 0.24, green: 0.20, blue: 0.17)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard")
                    .font(.system(size: 21))
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(isDeferred ? "准备好时再开启" : "开启鹿边输入法")
                        .font(.headline)
                    Text("需要你在系统设置中确认")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isDeferred {
                Text("没关系，你可以随时回来开启键盘。")
                    .font(.subheadline)
                Button("继续设置") { isDeferred = false }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("setup.resume")
            } else {
                Text(settingsOpened
                     ? "打开设置后，进入「键盘」，开启「鹿边输入法」。回到输入框，长按地球图标即可切换。"
                     : "前往本 App 的系统设置，进入「键盘」并开启「鹿边输入法」。不需要开启「完全访问」。")
                    .font(.subheadline)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                DisclosureGroup("找不到「键盘」入口？") {
                    Text("在系统设置中依次打开：通用 → 键盘 → 键盘 → 添加新键盘，选择「鹿边输入法」。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .padding(.top, 6)
                }
                .font(.caption)
                .accessibilityIdentifier("setup.manualSteps")

                if openingFailed {
                    Text("暂时无法打开设置，请按上方步骤手动开启。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("setup.error")
                }

                HStack(spacing: 10) {
                    Button("暂不") { isDeferred = true }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(.white.opacity(0.7), in: Capsule())
                        .accessibilityIdentifier("setup.cancel")
                    Button(action: openSettings) {
                        HStack(spacing: 6) {
                            Text(settingsOpened ? "再去设置" : "确认，去开启")
                            Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(.white)
                        .background(ink, in: Capsule())
                    }
                    .disabled(openingSettings)
                    .accessibilityIdentifier("setup.confirm")
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(ink)
        .tint(ink)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.955, green: 0.927, blue: 0.89), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(ink.opacity(0.07)))
    }

    private func openSettings() {
        guard !openingSettings else { return }
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            openingFailed = true
            return
        }
        beforeOpeningSettings()
        openingFailed = false
        openingSettings = true
        openURL(url) { accepted in
            openingSettings = false
            openingFailed = !accepted
            // Opening Settings does not tell us whether the keyboard was enabled.
            settingsOpened = accepted
        }
    }
}
