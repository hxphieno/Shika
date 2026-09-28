import UIKit

private func acceptanceTree(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(acceptanceTree) }
private final class AcceptanceProxy: NSObject, UITextDocumentProxy {
    var text = ""
    var marked: String?
    var documentContextBeforeInput: String? { text + (marked ?? "") }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var documentIdentifier = UUID()
    var hasText: Bool { !text.isEmpty || marked != nil }
    func insertText(_ value: String) { text += value }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ value: String, selectedRange: NSRange) { marked = value }
    func unmarkText() { text += marked ?? ""; marked = nil }
}
private final class AcceptanceController: KeyboardViewController {
    let proxy = AcceptanceProxy()
    override var textDocumentProxy: UITextDocumentProxy { proxy }
}

@MainActor
private final class KeyboardAcceptanceApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var assertions = 0
    var failures: [String] = []
    let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { failures.append(message) }
    }
    func capture(_ view: UIView, _ name: String) {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image {
            UIColor.systemBackground.setFill(); $0.fill(view.bounds)
            view.layer.render(in: $0.cgContext)
        }
        try? image.pngData()?.write(to: output.appendingPathComponent(name + ".png"))
    }
    // Read the rendered silhouette, independently of the path construction.
    func silhouette(_ view: UIView) -> [(Int, Int)?] {
        let width = Int(ceil(view.bounds.width)), height = Int(ceil(view.bounds.height))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { storage in
            let context = CGContext(data: storage.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
            // drawHierarchy would include the shadow; layer rendering preserves
            // the view's actual cap silhouette while a high alpha excludes it.
            view.layer.render(in: context)
        }
        return (0..<height).map { y in
            let occupied = (0..<width).filter { pixels[(y * width + $0) * 4 + 3] > 200 }
            guard let first = occupied.first, let last = occupied.last else { return nil }
            return (first, last)
        }
    }
    func application(_ app: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController()
        host.view.backgroundColor = .systemBackground
        window.rootViewController = host; window.makeKeyAndVisible(); self.window = window
        Task { @MainActor in self.run(host) }
        return true
    }
    func run(_ host: UIViewController) {
        if ProcessInfo.processInfo.environment["SHIKA_ACCEPTANCE_CANDIDATES_ONLY"] == "1" {
            let previousScheme = UserDefaults.standard.string(forKey: SKInputScheme.preferenceKey)
            let previousMode = UserDefaults.standard.string(forKey: SKChineseJapaneseMode.preferenceKey)
            defer {
                UserDefaults.standard.set(previousScheme, forKey: SKInputScheme.preferenceKey)
                UserDefaults.standard.set(previousMode, forKey: SKChineseJapaneseMode.preferenceKey)
            }
            UserDefaults.standard.set("mixed", forKey: SKChineseJapaneseMode.preferenceKey)
            checkModesAndCandidates(host)
            checkCandidateNaturalWidths(host)
            finish("candidates")
            return
        }
        if CommandLine.arguments.contains("verify-persistence") {
            let controller = attach(host)
            let mode = acceptanceTree(controller.view).compactMap { $0 as? SKInputSwitchButton }.first!
            expect(mode.currentState == .japanese, "Japanese language mode survives process restart")
            let main = acceptanceTree(controller.view).compactMap { $0 as? SKChineseJapaneseKeyboardView }.first!
            expect(!main.isHidden && main.currentLanguageState == .japanese, "Restored preference renders matching Japanese layout")
            capture(controller.view, "acceptance-mode-after-relaunch")
            UserDefaults.standard.set(UserDefaults.standard.string(forKey: "acceptance.previousScheme"), forKey: SKInputScheme.preferenceKey)
            UserDefaults.standard.set(UserDefaults.standard.string(forKey: "acceptance.previousMode"), forKey: SKChineseJapaneseMode.preferenceKey)
            UserDefaults.standard.removeObject(forKey: "acceptance.previousScheme")
            UserDefaults.standard.removeObject(forKey: "acceptance.previousMode")
            UserDefaults.standard.removeObject(forKey: "acceptance.pendingRestore")
            finish("persistence")
            return
        }
        if !UserDefaults.standard.bool(forKey: "acceptance.pendingRestore") {
            UserDefaults.standard.set(UserDefaults.standard.string(forKey: SKInputScheme.preferenceKey), forKey: "acceptance.previousScheme")
            UserDefaults.standard.set(UserDefaults.standard.string(forKey: SKChineseJapaneseMode.preferenceKey), forKey: "acceptance.previousMode")
            UserDefaults.standard.set(true, forKey: "acceptance.pendingRestore")
        }
        UserDefaults.standard.set("mixed", forKey: SKChineseJapaneseMode.preferenceKey)
        for scheme in ["shuangpin", "chineseJapanese"] {
            UserDefaults.standard.set(scheme, forKey: SKInputScheme.preferenceKey)
            let controller = AcceptanceController()
            host.addChild(controller); host.view.addSubview(controller.view); controller.didMove(toParent: host)
            for width in [CGFloat(320), 402, 874] {
                host.setOverrideTraitCollection(UITraitCollection(verticalSizeClass: width > 600 ? .compact : .regular), forChild: controller)
                controller.view.frame = CGRect(x: 0, y: 100, width: width, height: width > 600 ? 206 : 260)
                controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
                controller.view.clipsToBounds = true
                let surface = acceptanceTree(controller.view).compactMap { $0 as? SKMainKeyboardSurface }.first { !$0.isHidden }!
                for title in ["q", "p", "w", "e", "r", "x", "d", "h"] {
                    let key = surface.keyRows.flatMap { $0 }.first { $0.keyTitle.lowercased() == title }!
                    key.sendActions(for: .touchDown)
                    let preview = acceptanceTree(controller.view).first { $0.accessibilityIdentifier == "main-key-preview" }
                    expect(preview != nil, "\(scheme) \(width) \(title): preview belongs to extension root")
                    if let preview {
                        let frame = preview.convert(preview.bounds, to: controller.view)
                        let keyFrame = key.convert(key.bounds, to: controller.view)
                        expect(controller.view.bounds.contains(frame), "\(scheme) \(width) \(title): preview is inside clipped root")
                        expect(frame.minY >= 2 && frame.minX >= 2 && frame.maxX <= width - 2, "\(scheme) \(width) \(title): preview shadow has edge clearance")
                        expect(frame.minY < keyFrame.minY - 20, "\(scheme) \(width) \(title): preview rises visibly above key")
                        expect(!preview.isUserInteractionEnabled, "\(scheme) \(width) \(title): preview cannot steal touches")
                        let rows = silhouette(preview)
                        let fullWidth = Int(ceil(preview.bounds.width))
                        // A 51pt cap must retain full width for its straight sides;
                        // these pixels would fail on the old shortened 27pt cap.
                        for y in [15, 25, 35, 45, 50] {
                            expect(rows[y].map { $0.0 <= 1 && $0.1 >= fullWidth - 2 } == true,
                                   "\(scheme) \(width) \(title): rendered cap keeps full width at y=\(y)")
                        }
                        expect(SKMainKeyPreview.font.pointSize == 37, "\(scheme) \(width) \(title): preview letter retains 37pt size")
                        let localKey = key.convert(key.bounds, to: preview)
                        // Exclude the original 8pt bottom-key corner, not the waist.
                        let waistEnd = min(rows.count - 9, Int(localKey.maxY) - 9)
                        if title == "q" {
                            expect((12...waistEnd).allSatisfy { rows[$0].map { $0.0 <= 1 } == true },
                                   "\(scheme) \(width): Q outer side remains straight through cap and waist")
                        }
                        if title == "p" {
                            expect((12...waistEnd).allSatisfy { rows[$0].map { $0.1 >= fullWidth - 2 } == true },
                                   "\(scheme) \(width): P outer side remains straight through cap and waist; width=\(preview.bounds.width) key=\(localKey), rows=\((12...waistEnd).filter { rows[$0].map { $0.1 < fullWidth - 2 } ?? true }.map { "\($0):\(String(describing: rows[$0]))" })")
                        }
                        if waistEnd > 52 {
                            for y in 52...waistEnd {
                                if let prior = rows[y - 1], let row = rows[y] {
                                    expect(row.0 >= prior.0 - 1 && row.1 <= prior.1 + 1,
                                           "\(scheme) \(width) \(title): waist does not reverse at y=\(y)")
                                }
                            }
                        }
                        if width == 402 || (width == 320 && title == "q") || (width == 874 && title == "p") {
                            capture(controller.view, "acceptance-preview-\(scheme)-\(Int(width))-\(title)")
                        }
                    }
                    key.sendActions(for: .touchCancel)
                    expect(!acceptanceTree(controller.view).contains { $0.accessibilityIdentifier == "main-key-preview" }, "\(scheme) \(width) \(title): cancel removes preview")
                    for _ in 0..<4 { controller.didTapDelete() }
                }
            }
            controller.willMove(toParent: nil); controller.view.removeFromSuperview(); controller.removeFromParent()
        }
        checkModesAndCandidates(host)
        checkCandidateNaturalWidths(host)
        checkSymbols(host)
        checkPersistence(host)
        finish("main")
    }
    func attach(_ host: UIViewController) -> AcceptanceController {
        let controller = AcceptanceController()
        host.addChild(controller); host.view.addSubview(controller.view); controller.didMove(toParent: host)
        controller.view.frame = CGRect(x: 0, y: 100, width: 402, height: 260)
        controller.view.layoutIfNeeded()
        return controller
    }
    func detach(_ controller: UIViewController) {
        controller.willMove(toParent: nil); controller.view.removeFromSuperview(); controller.removeFromParent()
    }
    func checkModesAndCandidates(_ host: UIViewController) {
        for scheme in ["shuangpin", "chineseJapanese"] {
            UserDefaults.standard.set(scheme, forKey: SKInputScheme.preferenceKey)
            let controller = attach(host)
            let mode = acceptanceTree(controller.view).first { $0.accessibilityIdentifier == "mode.selector" }!
            let main = acceptanceTree(controller.view).compactMap { $0 as? SKMainKeyboardSurface }.first { !$0.isHidden }!
            let q = main.keyRows[0][0]
            let candidateBar = acceptanceTree(controller.view).compactMap { $0 as? CandidateBarView }.first!
            for width in [CGFloat(320), 402, 874] {
                controller.view.frame.size.width = width
                controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
                expect(!mode.isHidden, "\(scheme) \(width): empty composition shows mode")
                expect(abs(mode.convert(mode.bounds, to: controller.view).minX - q.convert(q.bounds, to: controller.view).minX) < 0.5, "\(scheme) \(width): mode leading matches Q")
            }
            controller.view.frame.size.width = 402
            controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
            capture(controller.view, "acceptance-mode-empty-" + scheme)
            controller.didTapKey("n"); controller.didTapKey("i")
            controller.view.layoutIfNeeded()
            expect(mode.isHidden, "\(scheme): nonempty candidate row hides mode")
            expect(abs(candidateBar.convert(candidateBar.bounds, to: controller.view).minX - q.convert(q.bounds, to: controller.view).minX) < 0.5, "\(scheme): hidden mode leaves no reserved width")
            let scroll = acceptanceTree(candidateBar).compactMap { $0 as? UIScrollView }.first!
            let arrow = acceptanceTree(candidateBar).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "candidates.expand" }!
            expect(arrow.bounds.width >= 48 && arrow.bounds.height >= 44, "\(scheme): expanded arrow has enlarged 48×44 target")
            expect(scroll.bounds.height >= 44 && scroll.contentSize.width + scroll.contentInset.right > scroll.bounds.width, "\(scheme): candidates retain full-height horizontal scroll area")
            let buttons = acceptanceTree(scroll).compactMap { $0 as? UIButton }.filter { $0.accessibilityIdentifier?.hasPrefix("candidate.") == true }
            expect(scroll.canCancelContentTouches && buttons.allSatisfy { scroll.touchesShouldCancel(in: $0) }, "\(scheme): dragging from a candidate can cancel its tap")
            expect(buttons.allSatisfy { $0.bounds.width >= 44 && $0.bounds.height >= 44 }, "\(scheme): every candidate has minimum 44×44 target")
            for point in [CGPoint(x: 1, y: 1), CGPoint(x: arrow.bounds.width - 1, y: 1), CGPoint(x: 1, y: 43), CGPoint(x: arrow.bounds.width - 1, y: 43)] {
                let hit = controller.view.hitTest(arrow.convert(point, to: controller.view), with: nil)
                expect(hit === arrow || hit?.isDescendant(of: arrow) == true, "\(scheme): arrow edge remains tappable")
            }
            expect(arrow.bounds.width >= 72, "\(scheme): disclosure reserves 72pt target")
            expect(!arrow.isDescendant(of: scroll), "\(scheme): fixed arrow is independent of candidate panning")
            for point in [CGPoint(x: -0.1, y: 22), CGPoint(x: arrow.bounds.width + 0.1, y: 22), CGPoint(x: 30, y: -0.1), CGPoint(x: 30, y: 44.1)] {
                expect(!arrow.point(inside: point, with: nil), "\(scheme): initial disclosure hit excludes neighboring regions")
            }
            let leftOfArrow = arrow.convert(CGPoint(x: -1, y: 22), to: controller.view)
            let belowArrow = arrow.convert(CGPoint(x: 30, y: 45), to: controller.view)
            expect(controller.view.hitTest(leftOfArrow, with: nil) !== arrow, "\(scheme): adjacent candidate region is not stolen")
            expect(controller.view.hitTest(belowArrow, with: nil) !== arrow, "\(scheme): main key region is not stolen")
            arrow.isHighlighted = true
            expect(arrow.backgroundColor != .clear, "\(scheme): disclosure press shows immediate highlight")
            arrow.isHighlighted = false
            expect(arrow.backgroundColor == .clear, "\(scheme): disclosure release clears highlight")
            let before = controller.proxy.marked
            scroll.setContentOffset(CGPoint(x: min(70, scroll.contentSize.width - scroll.bounds.width), y: 0), animated: false)
            expect(controller.proxy.marked == before && controller.proxy.text.isEmpty, "\(scheme): candidate scroll does not commit or change composition")
            arrow.sendActions(for: .touchUpInside); controller.view.layoutIfNeeded()
            let grid = acceptanceTree(controller.view).compactMap { $0 as? SKExpandedCandidatesView }.first!
            expect(!grid.isHidden && main.isHidden && mode.isHidden, "\(scheme): arrow expands grid without mode marker")
            arrow.sendActions(for: .touchUpInside); controller.view.layoutIfNeeded()
            expect(grid.isHidden && !main.isHidden && controller.proxy.marked == before, "\(scheme): collapse restores keys and composition")
            let collection = acceptanceTree(grid).compactMap { $0 as? UICollectionView }.first!
            let initialExpandedCount = collection.numberOfItems(inSection: 0)
            expect(initialExpandedCount > 8, "\(scheme): first expansion loads more than the initial strip")
            var maximumToggleMilliseconds: Double = 0
            for cycle in 0..<20 {
                let start = CACurrentMediaTime()
                arrow.sendActions(for: .touchUpInside); controller.view.layoutIfNeeded()
                expect(!grid.isHidden && main.isHidden, "\(scheme): repeated disclosure expands cycle \(cycle)")
                expect(collection.numberOfItems(inSection: 0) == initialExpandedCount,
                       "\(scheme): reopening does not append candidate pages cycle \(cycle)")
                arrow.sendActions(for: .touchUpInside); controller.view.layoutIfNeeded()
                maximumToggleMilliseconds = max(maximumToggleMilliseconds, (CACurrentMediaTime() - start) * 1000)
                expect(grid.isHidden && !main.isHidden && controller.proxy.marked == before,
                       "\(scheme): repeated disclosure collapses without changing text cycle \(cycle)")
            }
            let timing = "\(scheme): slowest synchronous expand + layout + collapse + layout across 20 cycles = \(maximumToggleMilliseconds) ms\n"
            let timingURL = output.appendingPathComponent("disclosure-timing-" + scheme + ".txt")
            try? timing.write(to: timingURL, atomically: true, encoding: .utf8)
            capture(controller.view, "acceptance-candidate-filled-" + scheme)
            controller.didTapKey(" "); controller.view.layoutIfNeeded()
            expect(!controller.proxy.text.isEmpty && controller.proxy.marked == nil && !mode.isHidden, "\(scheme): selection commits and restores mode")
            // Check routing at every key center and its nearest boundaries.
            for width in [CGFloat(320), 402, 874] {
                controller.view.frame.size.width = width
                controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
                var wrong = 0
                for row in main.keyRows {
                    for key in row {
                        let center = key.convert(CGPoint(x: key.bounds.midX, y: key.bounds.midY), to: controller.view)
                        if controller.view.hitTest(center, with: nil) !== key { wrong += 1 }
                    }
                }
                expect(wrong == 0, "\(scheme) \(width): enlarged targets preserve every letter center")
                expect(main.hitTest(CGPoint(x: 12, y: -1), with: nil) == nil, "\(scheme) \(width): letters do not steal candidate touches")
            }
            controller.view.frame.size.width = 402
            controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
            for character in (scheme == "shuangpin" ? "uijx" : "shijie") { controller.didTapKey(String(character)) }
            controller.view.layoutIfNeeded()
            checkCandidateWidths(candidateBar, label: scheme + " real phrase before expansion")
            let phraseTitles = acceptanceTree(candidateBar).compactMap { ($0 as? UIButton)?.accessibilityLabel }
            expect(phraseTitles.contains("世界"), "\(scheme): real phrase creates double-character candidates")
            arrow.sendActions(for: .touchUpInside); controller.view.layoutIfNeeded()
            arrow.sendActions(for: .touchUpInside); controller.view.layoutIfNeeded()
            checkCandidateWidths(candidateBar, label: scheme + " real phrase after expand-collapse")
            capture(controller.view, "acceptance-phrase-candidates-" + scheme)
            controller.didTapKey(" ")
            detach(controller)
        }
    }
    func checkCandidateWidths(_ bar: CandidateBarView, label: String) {
        bar.layoutIfNeeded()
        let scroll = acceptanceTree(bar).compactMap { $0 as? UIScrollView }.first!
        scroll.layoutIfNeeded()
        let buttons = acceptanceTree(scroll).compactMap { $0 as? UIButton }.filter { $0.accessibilityIdentifier?.hasPrefix("candidate.") == true }
        var requiredContentWidth: CGFloat = 0
        for button in buttons {
            button.layoutIfNeeded()
            let title = button.accessibilityLabel ?? ""
            let naturalWidth = (title as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 20)]).width
            let requiredWidth = max(44, naturalWidth + 18)
            requiredContentWidth += requiredWidth
            expect(button.bounds.width + 0.1 >= requiredWidth, "\(label): \(title) retains natural text width plus padding")
            expect(button.titleLabel?.numberOfLines == 1, "\(label): \(title) has a single-line label")
            expect((button.titleLabel?.bounds.height ?? 100) <= UIFont.systemFont(ofSize: 20).lineHeight + 1, "\(label): \(title) renders no second text line")
        }
        expect(!buttons.isEmpty, "\(label): candidate measurement has nonempty controls")
        expect(scroll.contentSize.width + 1 >= requiredContentWidth, "\(label): content width preserves all natural candidate widths")
        if requiredContentWidth > scroll.bounds.width + 1 {
            expect(scroll.contentSize.width > scroll.bounds.width + 1, "\(label): overflowing phrase candidates retain horizontal scrolling")
            scroll.setContentOffset(CGPoint(x: scroll.contentSize.width - scroll.bounds.width, y: 0), animated: false)
            expect(scroll.contentOffset.x > 1, "\(label): scrolling can reach later phrase candidates")
            scroll.setContentOffset(.zero, animated: false)
        }
    }
    func checkCandidateNaturalWidths(_ host: UIViewController) {
        // Deliberately constrain the bar while retaining a long content stack.
        // min-44 target checks alone did not catch configured-title wrapping.
        let bar = CandidateBarView()
        host.view.addSubview(bar)
        let titles = ["世界", "师姐", "时节", "十届", "视界", "直接", "中华人民共和国", "今天的天气真不错", "输入法候选项", "跨应用的中文输入体验"]
        var state = SKEngineState()
        state.candidates = titles.enumerated().map { SKCandidate(index: $0.offset, text: $0.element, comment: "") }
        for width in [CGFloat(320), 402, 874] {
            bar.frame = CGRect(x: 0, y: 100, width: width, height: 44)
            bar.update(state); bar.setNeedsLayout(); bar.layoutIfNeeded()
            checkCandidateWidths(bar, label: "\(width) synthetic long phrases")
            bar.update(state, expanded: true); bar.layoutIfNeeded()
            bar.update(state, expanded: false); bar.layoutIfNeeded()
            checkCandidateWidths(bar, label: "\(width) synthetic phrases after expand-collapse")
            if width == 402 { capture(bar, "acceptance-long-phrase-candidates") }
        }
        bar.removeFromSuperview()
    }
    func checkSymbols(_ host: UIViewController) {
        UserDefaults.standard.set("chineseJapanese", forKey: SKInputScheme.preferenceKey)
        let controller = attach(host)
        controller.didTapSwitchLayout(to: .number); controller.view.layoutIfNeeded()
        let number = acceptanceTree(controller.view).compactMap { $0 as? SKNumberInputView }.first!
        let buttons = acceptanceTree(number).compactMap { $0 as? UIButton }
        let symbols = buttons.filter { $0.accessibilityIdentifier?.hasPrefix("symbol.") == true }.sorted { $0.tag < $1.tag }
        let scroll = acceptanceTree(number).compactMap { $0 as? UIScrollView }.first!
        let titles = symbols.compactMap { $0.title(for: .normal) }
        expect(scroll.canCancelContentTouches && symbols.allSatisfy { scroll.touchesShouldCancel(in: $0) }, "Dragging from a symbol can cancel its key tap")
        expect(titles.count >= 40 && Set(titles).count == titles.count, "Symbol choices are useful in number and contain no duplicates")
        for required in ["，", "。", "？", "！", "（", "）", "「", "」", "@", "_", "/", "\\", "¥", "$", "+", "=", "%"] {
            expect(titles.contains(required), "Symbols include \(required)")
        }
        expect(!titles.contains("（）") && !titles.contains("「」"), "Brackets can surround text using separate opening/closing keys")
        let one = buttons.first { $0.title(for: .normal) == "1" }!
        let oneFrame = one.convert(one.bounds, to: number)
        expect(oneFrame.maxX < scroll.frame.minX, "Numeric keypad remains left of symbol scroll region")
        capture(controller.view, "acceptance-symbols-first")
        for width in [CGFloat(320), 402, 874] {
            controller.view.frame.size.width = width
            controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
            for digit in 0...9 {
                let key = buttons.first { $0.title(for: .normal) == String(digit) }!
                let center = key.convert(CGPoint(x: key.bounds.midX, y: key.bounds.midY), to: number)
                expect(number.hitTest(center, with: nil) === key, "\(width): numeric key \(digit) center is not stolen")
            }
            let first = buttons.first { $0.title(for: .normal) == "1" }!
            let second = buttons.first { $0.title(for: .normal) == "2" }!
            let a = first.convert(first.bounds, to: number), b = second.convert(second.bounds, to: number)
            let x = (a.maxX + b.minX) / 2
            expect(number.hitTest(CGPoint(x: x - 0.5, y: a.midY), with: nil) === first, "\(width): numeric gap left half belongs to 1")
            expect(number.hitTest(CGPoint(x: x + 0.5, y: a.midY), with: nil) === second, "\(width): numeric gap right half belongs to 2")
            expect(number.hitTest(CGPoint(x: 5, y: -1), with: nil) == nil, "\(width): number region cannot steal candidate touches")
        }
        controller.view.frame.size.width = 402
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        for button in symbols {
            let expected = button.title(for: .normal)!
            let before = controller.proxy.text
            button.sendActions(for: .touchUpInside)
            expect(controller.proxy.text == before + expected, "Symbol key emits its exact label: \(expected)")
        }
        for digit in 0...9 {
            let button = buttons.first { $0.title(for: .normal) == String(digit) }!
            let before = controller.proxy.text
            button.sendActions(for: .touchUpInside)
            expect(controller.proxy.text == before + String(digit), "Numeric key emits \(digit)")
        }
        let before = controller.proxy.text
        scroll.setContentOffset(CGPoint(x: max(0, scroll.contentSize.width - scroll.bounds.width), y: 0), animated: false)
        expect(controller.proxy.text == before, "Scrolling symbols never emits text")
        capture(controller.view, "acceptance-symbols-last")
        let back = buttons.first { $0.title(for: .normal) == "返回" }!
        back.sendActions(for: .touchUpInside); controller.view.layoutIfNeeded()
        expect(number.isHidden, "Number page return restores alphabet page")
        detach(controller)
    }
    func checkPersistence(_ host: UIViewController) {
        UserDefaults.standard.set("chineseJapanese", forKey: SKInputScheme.preferenceKey)
        UserDefaults.standard.set("mixed", forKey: SKChineseJapaneseMode.preferenceKey)
        for target in [SKChineseJapaneseMode.chinese, .japanese, .mixed] {
            let controller = attach(host)
            let button = acceptanceTree(controller.view).compactMap { $0 as? SKInputSwitchButton }.first!
            button.sendActions(for: .touchUpInside)
            expect(button.currentState == target, "Language button advances to \(target.rawValue)")
            controller.didTapSwitchScheme(); controller.didTapSwitchScheme()
            expect(button.currentState == target, "Scheme switching retains \(target.rawValue)")
            controller.viewWillDisappear(false); detach(controller)
            let reopened = attach(host)
            let restored = acceptanceTree(reopened.view).compactMap { $0 as? SKInputSwitchButton }.first!
            expect(restored.currentState == target, "Controller reconstruction retains \(target.rawValue)")
            detach(reopened)
        }
        let controller = attach(host)
        let button = acceptanceTree(controller.view).compactMap { $0 as? SKInputSwitchButton }.first!
        button.sendActions(for: .touchUpInside); button.sendActions(for: .touchUpInside)
        expect(button.currentState == .japanese, "Prepare Japanese preference for independent process restart")
        UserDefaults.standard.synchronize()
        detach(controller)
    }
    func finish(_ phase: String) {
        let report = "\(failures.isEmpty ? "PASS" : "FAIL") \(assertions) independent keyboard acceptance checks\n" + failures.joined(separator: "\n")
        try? report.write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        try? report.write(to: output.appendingPathComponent("keyboard-acceptance-" + phase + "-result.txt"), atomically: true, encoding: .utf8)
    }
}
@main
struct KeyboardAcceptanceEntry {
    @MainActor static func main() {
        UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(KeyboardAcceptanceApp.self))
    }
}
