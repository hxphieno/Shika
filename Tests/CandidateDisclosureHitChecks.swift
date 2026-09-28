import UIKit
private func tree(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(tree) }
@main final class CandidateDisclosureHitChecks: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var panEvents = 0
    static func main() { UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(Self.self)) }
    func application(_ app: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let w = UIWindow(frame: UIScreen.main.bounds), host = UIViewController()
        w.rootViewController = host; w.makeKeyAndVisible(); window = w
        DispatchQueue.main.async {
            if CommandLine.arguments.contains("interactive") { self.runInteractive(host.view) }
            else { self.run(host.view) }
        }
        return true
    }
    func run(_ host: UIView) {
        var failures: [String] = []; var checks = 0
        func expect(_ value: Bool, _ message: String) { checks += 1; if !value { failures.append(message) } }
        let bar = CandidateBarView(); host.addSubview(bar)
        let arrow = tree(bar).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "candidates.expand" }!
        let target = tree(bar).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "candidates.disclosureTarget" }!
        let scroll = tree(bar).compactMap { $0 as? UIScrollView }.first!
        var toggles = 0, selections = 0
        bar.onToggleExpanded = { toggles += 1 }; bar.onSelect = { _ in selections += 1 }
        for width in [320.0, 402, 874] {
            bar.frame = CGRect(x: 0, y: 100, width: width, height: 44)
            for count in [1, 3, 30] {
                var state = SKEngineState()
                state.candidates = (0..<count).map { SKCandidate(index: $0, text: $0 == 0 ? "你好" : "字", comment: "") }
                bar.update(state); bar.layoutIfNeeded()
                let keys = tree(scroll).compactMap { $0 as? UIButton }.filter { $0.accessibilityIdentifier?.hasPrefix("candidate.") == true }
                for offset in [0.0, max(0, scroll.contentSize.width - scroll.bounds.width + scroll.contentInset.right)] {
                    scroll.contentOffset.x = offset
                    for x in stride(from: 0.5, to: width, by: 7) {
                        for y in [0.5, 22.0, 43.5] {
                            let point = CGPoint(x: x, y: y)
                            let candidate = point.x < arrow.frame.minX ? keys.first { $0.convert($0.bounds, to: bar).contains(point) } : nil
                            let hit = bar.hitTest(point, with: nil)
                            if let candidate {
                                expect(hit === candidate, "Candidate padding/center remains a candidate at \(point)")
                                expect(!arrow.point(inside: arrow.convert(point, from: bar), with: nil), "Disclosure tracking excludes candidate")
                            } else {
                                let disclosure = point.x >= arrow.frame.minX ? arrow : target
                                expect(hit === disclosure, "Fixed arrow owns its area; free space stays scrollable at \(point)")
                                expect(disclosure.point(inside: disclosure.convert(point, from: bar), with: nil), "Release inside disclosure area stays valid")
                                if disclosure === target {
                                    expect(!arrow.point(inside: arrow.convert(point, from: bar), with: nil), "Blank-space touches do not start on the fixed arrow")
                                }
                            }
                        }
                    }
                }
                expect(!arrow.isDescendant(of: scroll), "Fixed arrow cannot be cancelled by candidate scrolling")
                expect(target.isDescendant(of: scroll) && keys.allSatisfy { $0.isDescendant(of: scroll) }, "Blank space and words retain native scrolling")
                expect(scroll.canCancelContentTouches && !scroll.delaysContentTouches && scroll.touchesShouldCancel(in: target), "Pan can cancel blank-space tap without delaying initial feedback")
                bar.update(state, expanded: true); bar.layoutIfNeeded()
                for point in [CGPoint(x: 1, y: 1), CGPoint(x: width / 2, y: 22), CGPoint(x: width - 1, y: 43)] {
                    expect(bar.hitTest(point, with: nil) === arrow, "Expanded header blank space collapses candidates")
                }
                arrow.sendActions(for: .touchUpInside)
                bar.update(state); bar.layoutIfNeeded()
                keys.first!.sendActions(for: .touchUpInside)
                for point in [CGPoint(x: -1, y: 22), CGPoint(x: width + 1, y: 22), CGPoint(x: 20, y: -1), CGPoint(x: 20, y: 44)] {
                    expect(bar.hitTest(point, with: nil) == nil, "Never steals adjacent keyboard/language touches")
                    expect(!arrow.point(inside: arrow.convert(point, from: bar), with: nil), "Tracking stays in candidate bar")
                }
            }
        }
        expect(toggles == 9 && selections == 9, "Disclosure and candidate actions stay separate")
        bar.update(SKEngineState()); bar.layoutIfNeeded()
        expect(arrow.isHidden && bar.hitTest(CGPoint(x: 800, y: 22), with: nil) !== arrow, "Empty state has no invisible disclosure target")
        bar.showError(); bar.layoutIfNeeded()
        let retry = tree(bar).compactMap { $0 as? UIButton }.first { $0.title(for: .normal) == "重试" }!
        expect(bar.hitTest(retry.convert(CGPoint(x: retry.bounds.midX, y: retry.bounds.midY), to: bar), with: nil) === retry, "Retry button remains usable")
        // An unusually tall host header verifies that hit area and visual
        // candidate-row height are independent, including upper/lower padding.
        let row = SKCandidateInteractionRow(arrangedSubviews: [bar]); row.candidateBar = bar
        row.axis = .horizontal; row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 0, leading: 6.5, bottom: 0, trailing: 0)
        bar.heightAnchor.constraint(equalToConstant: 44).isActive = true
        host.addSubview(row); row.frame = CGRect(x: 0, y: 200, width: 402, height: 80)
        var state = SKEngineState(); state.candidates = (0..<30).map { SKCandidate(index: $0, text: "词", comment: "") }
        bar.update(state); row.layoutIfNeeded(); bar.layoutIfNeeded()
        let first = tree(scroll).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "candidate.0" }!
        for point in [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 20, y: 79.5), CGPoint(x: 20, y: 40)] {
            expect(row.hitTest(point, with: nil) === first, "Header padding routes to word at \(point); first=\(first.convert(first.bounds, to: row)); scroll=\(scroll.frame) bounds=\(scroll.bounds); hit=\(row.hitTest(point, with: nil)?.accessibilityIdentifier ?? "nil")")
            expect(first.point(inside: first.convert(point, from: row), with: nil), "Candidate touch tracking accepts header padding")
        }
        expect(row.hitTest(CGPoint(x: 390, y: 1), with: nil) === arrow, "Header padding above arrow stays independent of scrolling")
        expect(row.hitTest(CGPoint(x: 20, y: 80), with: nil) == nil, "Header never steals keyboard touches")
        expect(scroll.convert(scroll.bounds, to: row) == row.bounds, "Native pan viewport covers the complete available header")
        expect(bar.bounds.height == 44, "Visual candidate-row height remains unchanged")
        let report = (failures.isEmpty ? "PASS " : "FAIL ") + "\(checks) candidate disclosure hit assertions\n" + failures.joined(separator: "\n")
        try! report.write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }

    // Launch the same test binary with "interactive" to exercise real UIKit
    // touch tracking and pan cancellation using Simulator pointer gestures.
    func runInteractive(_ host: UIView) {
        host.backgroundColor = .systemBackground
        for (count, top) in [(30, 240.0), (1, 480.0)] {
            var state = SKEngineState()
            state.candidates = (0..<count).map { SKCandidate(index: $0, text: $0 == 0 ? "你好" : "词\($0)", comment: "") }
            let bar = CandidateBarView()
            let row = SKCandidateInteractionRow(arrangedSubviews: [bar]); row.candidateBar = bar
            row.axis = .horizontal; row.alignment = .center
            row.isLayoutMarginsRelativeArrangement = true
            row.directionalLayoutMargins = .init(top: 0, leading: 6.5, bottom: 0, trailing: 0)
            bar.heightAnchor.constraint(equalToConstant: 44).isActive = true
            row.frame = CGRect(x: 0, y: top, width: host.bounds.width, height: 44)
            row.backgroundColor = .secondarySystemBackground
            host.addSubview(row)
            let status = UILabel(frame: CGRect(x: 8, y: top - 100, width: host.bounds.width - 16, height: 96))
            status.font = .monospacedSystemFont(ofSize: 15, weight: .regular); status.numberOfLines = 4
            host.addSubview(status)
            let key = UIButton(type: .system)
            key.setTitle("Adjacent keyboard key", for: .normal)
            key.frame = CGRect(x: 0, y: top + 44, width: host.bounds.width, height: 44)
            host.addSubview(key)
            var expanded = false, toggles = 0, selections = 0, keyTaps = 0
            let scroll = tree(bar).compactMap { $0 as? UIScrollView }.first!
            scroll.panGestureRecognizer.addTarget(self, action: #selector(observePan))
            let refresh = {
                status.text = "\(count) candidates: \(expanded ? "expanded" : "collapsed")\nToggles \(toggles), selections \(selections)\nKeys \(keyTaps), pan events \(self.panEvents)\nOffset \(Int(scroll.contentOffset.x)) / \(Int(scroll.contentSize.width))"
            }
            bar.onToggleExpanded = {
                toggles += 1; expanded.toggle(); bar.update(state, expanded: expanded); refresh()
            }
            bar.onSelect = { _ in selections += 1; refresh() }
            key.addAction(UIAction { _ in keyTaps += 1; refresh() }, for: .touchUpInside)
            bar.update(state); row.layoutIfNeeded(); bar.layoutIfNeeded(); refresh()
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in refresh() }
        }
        let reference = UIScrollView(frame: CGRect(x: 0, y: 650, width: host.bounds.width, height: 44))
        reference.contentSize = CGSize(width: 1600, height: 44)
        reference.backgroundColor = .systemYellow
        for index in 0..<20 {
            let label = UILabel(frame: CGRect(x: index * 80, y: 0, width: 80, height: 44))
            label.text = "Ref \(index)"; reference.addSubview(label)
        }
        host.addSubview(reference)
        reference.panGestureRecognizer.addTarget(self, action: #selector(observePan))
    }
    @objc private func observePan() { panEvents += 1 }
}
