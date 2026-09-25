import SwiftUI

struct ContentView: View {
    @State private var text = ""
    private var notices: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "许可文件未找到" }
        return text
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("启用键盘") {
                    Text("在系统设置 → 通用 → 键盘 → 键盘 → 添加新键盘中选择 Shika。输入时使用地球图标切换到 Shika。")
                    Text("无需开启完全访问。点击 🦌 切换双拼与中日键盘；中／日／混分别提供中文拼音、日文罗马字及两种语言的候选。")
                        .foregroundStyle(.secondary)
                }
                Section("试着输入") {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .accessibilityIdentifier("typingTest")
                    Text("双拼：nihc → 你好；全拼：nihao → 你好。点选候选或按空格确认。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("隐私") {
                    Text("输入转换在设备本地完成，不上传输入内容。词频学习保存在键盘扩展的私有目录中。")
                }
                Section {
                    NavigationLink("开源许可") {
                        ScrollView {
                            Text(notices)
                                .font(.footnote)
                                .padding()
                        }.navigationTitle("开源许可")
                    }
                }
            }
            .navigationTitle("Shika")
        }
    }
}
