import UIKit

private final class HeightTextField: UITextField {
    let keyboard = KeyboardViewController()
    override var inputViewController: UIInputViewController? { keyboard }
}

final class KeyboardHeightChecksApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let field = HeightTextField()
    private var failures: [String] = []
    private var measurements: [String] = []

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController()
        host.view.backgroundColor = .systemBackground
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        field.frame = CGRect(x: 20, y: 140, width: 350, height: 44)
        field.borderStyle = .roundedRect
        host.view.addSubview(field)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.present(cycle: 0) }
        return true
    }

    private func expect(_ condition: Bool, _ message: String) {
        if !condition { failures.append(message) }
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func check(_ label: String, height: CGFloat = 260) {
        let controller = field.keyboard
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        let view = controller.view!
        let bar = descendants(view).first { $0 is CandidateBarView }!
        let fitting = view.systemLayoutSizeFitting(CGSize(width: view.bounds.width, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        expect(abs(fitting.height - height) < 0.5, "\(label): fitting height \(fitting.height)")
        expect(abs(view.bounds.height - height) < 0.5, "\(label): actual height \(view.bounds.height)")
        expect(abs(bar.convert(bar.bounds, to: view).minY) < 0.5 && bar.bounds.height == 44,
               "\(label): candidate row moved or resized")
        for page in view.subviews where !page.isHidden && (page is SKMainKeyboardSurface || page is SKNumberInputView || page is SKExpandedCandidatesView) {
            expect(abs(page.frame.minY - 44) < 0.5 && abs(page.frame.maxY - height) < 0.5,
                   "\(label): page overlaps header or changes total height")
        }
        measurements.append("\(label): actual=\(view.bounds.height), fitting=\(fitting.height), candidate=\(bar.bounds.height)")
    }

    private func present(cycle: Int) {
        field.becomeFirstResponder()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let controller = self.field.keyboard
            controller.selectInputMode(scheme: .shuangpin, languageMode: .chinese)
            self.check("show \(cycle)")
            for key in "nihk" { controller.didTapKey(String(key)) }
            self.check("candidates \(cycle)")
            let expand = self.descendants(controller.view).first { $0.accessibilityIdentifier == "candidates.expand" } as! UIButton
            expand.sendActions(for: .touchUpInside)
            self.expect(!self.descendants(controller.view).first { $0 is SKExpandedCandidatesView }!.isHidden, "expanded candidates missing")
            self.check("expanded \(cycle)")
            expand.sendActions(for: .touchUpInside)
            for layout: SKKeyboardLayoutType in [.number, .alphabet] {
                controller.didTapSwitchLayout(to: layout)
                self.check("\(layout) \(cycle)")
            }
            controller.selectInputMode(scheme: .chineseJapanese, languageMode: .mixed)
            self.check("mixed \(cycle)")
            let key = self.descendants(controller.view).compactMap { $0 as? SKMainKeyButton }.first { !$0.isHidden && $0.keyTitle == "q" }!
            key.sendActions(for: .touchDown)
            if let preview = self.descendants(controller.view).first(where: { $0.accessibilityIdentifier == "main-key-preview" }) {
                self.expect(controller.view.bounds.contains(preview.frame), "preview escapes input view")
            } else { self.failures.append("preview missing") }
            key.sendActions(for: .touchCancel)
            let format = UIGraphicsImageRendererFormat(); format.scale = 2
            let image = UIGraphicsImageRenderer(bounds: controller.view.bounds, format: format).image {
                controller.view.layer.render(in: $0.cgContext)
            }
            let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try! image.pngData()!.write(to: output.appendingPathComponent("keyboard-height-\(cycle).png"))
            self.field.resignFirstResponder()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if cycle < 2 { self.present(cycle: cycle + 1) }
                else { self.checkContainerOwnership() }
            }
        }
    }

    private func checkContainerOwnership() {
        let controller = field.keyboard
        controller.view.removeFromSuperview()
        let container = UIView(frame: CGRect(x: 0, y: 300, width: 402, height: 260))
        container.clipsToBounds = true
        container.layer.cornerRadius = 24
        window!.rootViewController!.view.addSubview(container)
        container.addSubview(controller.view)
        controller.view.frame = container.bounds
        window!.clipsToBounds = true
        for (sizeClass, width, height): (UIUserInterfaceSizeClass, CGFloat, CGFloat) in [(.regular, 402, 260), (.compact, 874, 206), (.regular, 402, 260)] {
            controller.traitOverrides.verticalSizeClass = sizeClass
            controller.view.frame.size = CGSize(width: width, height: height)
            self.check("size class \(sizeClass.rawValue)", height: height)
            expect(container.clipsToBounds && container.layer.masksToBounds && window!.clipsToBounds,
                   "keyboard mutated system/ancestor clipping")
            expect(container.layer.cornerRadius == 24, "keyboard mutated ancestor corners")
        }
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let report = (failures.isEmpty ? "PASS keyboard height, presentation cycles, layouts, candidates, previews, rotation and ancestor clipping" : "FAIL " + failures.joined(separator: "\n"))
            + "\n" + measurements.joined(separator: "\n")
        try! report.write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }
}

@main struct Main {
    static func main() {
        UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(KeyboardHeightChecksApp.self))
    }
}
