import SwiftUI

struct ContentView: View {
    @State private var setupDeferred = false
    @State private var draft = ""
    @State private var messages: [LocalMessage] = []
    @State private var presentedPage: InformationPage?
    @State private var keyboardPreferences = SKKeyboardPreferences.load()
    @State private var settingsSaveFailed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var headerHeight = 104.0
    @FocusState private var isTyping: Bool

    private let ink = Color(red: 0.15, green: 0.15, blue: 0.16)
    private let bubble = Color(red: 0.955, green: 0.927, blue: 0.89)
    private let sentBubble = Color(red: 0.89, green: 0.82, blue: 0.73)
    private let canvas = Color.white
    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ScrollViewReader { reader in
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("开始使用")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 18)
                        introduction
                        ForEach(messages) { message in
                            HStack {
                                Spacer(minLength: 40)
                                Text(message.text)
                                    .font(.body)
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 14)
                                    .background(sentBubble, in: RoundedRectangle(cornerRadius: 24))
                                    .accessibilityLabel("我：\(message.text)")
                            }
                            .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, headerHeight + 26)
                    .padding(.bottom, 14)
                    .id("welcome")
                }
                .scrollDismissesKeyboard(.interactively)
                .mask {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: headerHeight - 20)
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: 40)
                        Rectangle().fill(.black)
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 12)
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
                .onChange(of: messages.count) {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { reader.scrollTo("latest", anchor: .bottom) }
                }
                .onChange(of: isTyping) {
                    if isTyping, !messages.isEmpty {
                        withAnimation { reader.scrollTo("latest", anchor: .bottom) }
                    }
                }
                header {
                    setupDeferred = false
                    isTyping = false
                    withAnimation(reduceMotion ? nil : .smooth) {
                        reader.scrollTo("welcome", anchor: .top)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .background(canvas.ignoresSafeArea())
            .foregroundStyle(ink)
            .sheet(item: $presentedPage) { page in
                if page == .settings { keyboardSettings } else { informationPage(page) }
            }
            // The reference uses a consistently white canvas, including in dark appearance.
            .preferredColorScheme(.light)
        }
    }

    private func header(showGuide: @escaping () -> Void) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 5) {
                // A temporary brand avatar until the portrait/video is supplied.
                Image("ShikaAvatar")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
                    .accessibilityHidden(true)
                Text("鹿边输入法")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("键盘使用指南")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Menu {
                Button("启用键盘", systemImage: "keyboard", action: showGuide)
                Button("试着输入", systemImage: "bubble.left") { isTyping = true }
                Divider()
                Button("键盘设置", systemImage: "gearshape") {
                    isTyping = false
                    presentedPage = .settings
                }
                Button("隐私保护", systemImage: "hand.raised") { presentedPage = .privacy }
                Button("声明与开源许可", systemImage: "doc.text") { presentedPage = .licenses }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.85), in: Circle())
                    .overlay(Circle().strokeBorder(.black.opacity(0.035)))
                    .shadow(color: .black.opacity(0.035), radius: 10, y: 4)
            }
            .accessibilityLabel("菜单")
            .accessibilityIdentifier("home.menu")
            .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .frame(height: headerHeight, alignment: .top)
        .background(alignment: .top) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(.white.opacity(0.65))
                .frame(height: headerHeight + 32)
                .mask(LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.55),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            messageBubble {
                Text("你好，我是鹿边输入法。\n从这里开始，试试新的输入方式。")
            }

            KeyboardSetupCard(isDeferred: $setupDeferred) {
                isTyping = false
            }
            .padding(.trailing, 24)

            messageBubble {
                Text("点击键盘左上角的输入法标识，选择「自然码双拼」「中文」「日文」或「中日混合」。有候选词时，先确认或清空当前输入，切换入口就会重新显示。")
            }

            VStack(alignment: .leading, spacing: 5) {
                messageBubble {
                    Text("在下面打个招呼吧。")
                }
                messageBubble {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 12) {
                            Text("nihao").font(.system(.body, design: .monospaced))
                            Image(systemName: "arrow.right").font(.caption)
                            Text("你好").fontWeight(.medium)
                        }
                        Text("全拼 nihao · 自然码双拼 nihk\n点选候选或按空格确认，再按 ↑ 发送。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                messageBubble {
                    Text("输入转换在本机完成。这里的消息只用于试输入，不上传，也不会收到自动回复。")
                }
                Button { presentedPage = .privacy } label: {
                    Label("隐私与开源许可", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
                .accessibilityIdentifier("home.privacy")
                .padding(.leading, 14)
            }
        }
    }

    private func messageBubble<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            content()
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(bubble, in: UnevenRoundedRectangle(
                    topLeadingRadius: 21, bottomLeadingRadius: 6,
                    bottomTrailingRadius: 21, topTrailingRadius: 21))
            Spacer(minLength: 34)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                isTyping.toggle()
            } label: {
                Image(systemName: isTyping ? "keyboard.chevron.compact.down" : "keyboard")
                    .font(.system(size: 21, weight: .regular))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(isTyping ? "收起键盘" : "开始输入")

            TextField("Message", text: $draft, axis: .vertical)
                .font(.body)
                .lineLimit(1...4)
                .padding(.vertical, 12)
                .focused($isTyping)
                .submitLabel(.send)
                .onSubmit(sendMessage)
                .accessibilityLabel("试着输入消息")
                .accessibilityIdentifier("typingTest")

            Button(action: sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(canSend ? .white : Color(white: 0.65))
                    .frame(width: 36, height: 36)
                    .background(canSend ? ink : Color(white: 0.94), in: Circle())
                    .frame(width: 44, height: 44)
            }
            .disabled(!canSend)
            .accessibilityLabel("发送消息")
            .accessibilityIdentifier("home.send")
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(.black.opacity(0.07)))
        .shadow(color: .black.opacity(0.035), radius: 12, y: 3)
        .frame(maxWidth: 560)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [.white.opacity(0), .white, .white], startPoint: .top, endPoint: .bottom)
                .padding(.top, -20)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    private func sendMessage() {
        guard canSend else { return }
        messages.append(LocalMessage(text: draft.trimmingCharacters(in: .whitespacesAndNewlines)))
        draft = ""
    }

    private var keyboardSettings: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("学习版双拼", isOn: Binding(
                        get: { keyboardPreferences.shuangpinLearningMode },
                        set: { enabled in
                            var updated = keyboardPreferences
                            updated.shuangpinLearningMode = enabled
                            do {
                                try updated.save()
                                keyboardPreferences = updated
                            } catch { settingsSaveFailed = true }
                        }))
                        .accessibilityIdentifier("settings.shuangpinLearningMode")
                } header: {
                    Text("自然码双拼")
                } footer: {
                    Text("开启时，在按键上显示声母和韵母提示；关闭后只显示 26 个字母。下次打开键盘时生效，不影响双拼输入、纠错和词频学习。")
                }
            }
            .navigationTitle("键盘设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { presentedPage = nil }
                }
            }
            .onAppear { keyboardPreferences = SKKeyboardPreferences.load() }
            .alert("设置未保存", isPresented: $settingsSaveFailed) {
                Button("好", role: .cancel) { }
            } message: {
                Text("暂时无法保存键盘设置，请稍后重试。")
            }
        }
        .tint(ink)
    }

    private func informationPage(_ page: InformationPage) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if page == .privacy {
                        privacySection("本地输入", text: "输入转换在设备本地完成，不上传输入内容。无需开启键盘的「完全访问」。")
                        privacySection("词频学习", text: "词频学习数据保存在键盘扩展的私有目录中，用于本机输入。")
                        privacySection("试输入消息", text: "主页面用于体验键盘。发送的消息仅在当前页面会话中展示，不上传、不提供自动回复，也不会保存为聊天记录。")
                        Button("查看声明与开源许可") { presentedPage = .licenses }
                            .font(.body.weight(.medium))
                            .accessibilityIdentifier("privacy.licenses")
                    } else {
                        Text(notices)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(canvas)
            .navigationTitle(page.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { presentedPage = nil }
                }
            }
        }
        .tint(ink)
    }

    private func privacySection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text).font(.body).foregroundStyle(.secondary).lineSpacing(5)
        }
    }

    private var notices: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "许可文件未找到" }
        return text
    }
}

private struct LocalMessage: Identifiable {
    let id = UUID()
    let text: String
}

private enum InformationPage: String, Identifiable {
    case settings = "键盘设置"
    case privacy = "隐私保护"
    case licenses = "声明与开源许可"
    var id: String { rawValue }
}
