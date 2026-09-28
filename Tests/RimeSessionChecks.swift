// Independent checks using the production ObjC bridge and Swift input session.
// Run with bash scripts/test-input-session.sh; all user data stays in a fresh temp directory.
import Foundation

@main
struct IndependentValidation {
 @MainActor static func main() throws {
  guard CommandLine.arguments.count == 3 else { fatalError("Usage: session-checks resourcePath freshUserPath") }
  let resource = URL(fileURLWithPath: CommandLine.arguments[1])
  let user = URL(fileURLWithPath: CommandLine.arguments[2])
  var checks = 0
  let engine = try SKRimeEngine(configuration: SKInputScheme.shuangpin.configuration, resourceURL: resource, userURL: user)
  var output = ""
  var deleteCount = 0
  let session = SKInputSession(engine: engine, configuration: SKInputScheme.shuangpin.configuration, insertText: {output += $0}, deleteText: {deleteCount += 1; if !output.isEmpty {output.removeLast()}})
  func type(_ s: String) {for c in s {session.type(String(c))}}
  func expect(_ condition: Bool, _ name: String) {if !condition { print("FAIL: \(name); output=\(output), state=\(session.state)"); exit(1)}; checks += 1; print("PASS: \(name)")}
  func exact(_ schema: String, _ code: String, _ word: String) throws {
   session.cancel(); output=""; try session.switchConfiguration(to: SKInputScheme(schemaID: schema)!.configuration); type(code)
   expect(output.isEmpty, "\(code) stays preedit")
   var found: SKCandidate?
   for _ in 0..<30 {
    if let choice=session.state.candidates.first(where: {$0.text == word}) {found=choice;break}
    if session.state.isLastPage {break}; session.changePage(backward:false)
   }
   expect(found != nil, "\(code) includes \(word)")
   session.select(found!); expect(output==word && session.state.input.isEmpty,"\(code) commits \(word) once")
  }
  for t in [["shika_flypy","wouivsgorf","我是中国人"],["shika_flypy","nihkuijx","你好世界"],["shika_flypy","nvhl","女孩"],["shika_flypy","lvse","绿色"],["shika_flypy","anqr","安全"],["shika_pinyin","woshizhongguoren","我是中国人"],["shika_pinyin","nihaoshijie","你好世界"],["shika_pinyin","xi'an","西安"],["shika_pinyin","nvhai","女孩"],["shika_pinyin","lve","略"]] {try exact(t[0],t[1],t[2])}
  session.cancel();output="";try session.switchConfiguration(to: SKInputScheme.shuangpin.configuration);type("nihk");session.type(" ");expect(output=="你好", "space commits top once");session.type(" ");expect(output=="你好 ","idle space inserts space")
  output="";type("nihk");session.type("，");expect(output=="你好，", "punctuation commits Hanzi then punctuation")
  output="";type("nihk");session.type("\n");expect(output=="nihk", "return confirms raw input without newline");session.type("\n");expect(output=="nihk\n", "idle return reaches host")
  output="";type("nihk");session.type("A");expect(output=="你好A", "uppercase commits Hanzi then literal")
  output="";type("nihk");try session.switchConfiguration(to: SKInputScheme.chineseJapanese.configuration);expect(output=="你好", "switch schema commits pending");type("shijie");session.type(" ");expect(output=="你好世界", "new schema converts after switch")
  output="";type("nihao");session.deleteBackward();expect(session.state.input=="niha" && deleteCount==0,"delete edits preedit only");for _ in 0..<4 {session.deleteBackward()};expect(session.state.input.isEmpty && deleteCount==0,"preedit can delete to empty");session.type("1");session.deleteBackward();expect(output.isEmpty && deleteCount==1,"idle delete reaches document")
  output="";type("ni");let page0=session.state.candidates;session.changePage(backward:false);let page1=session.state.candidates;expect(session.state.page==1 && !page1.isEmpty && page0 != page1,"paging changes candidates");session.select(page1[1]);expect(output==page1[1].text,"page1 nonfirst index selects correct text")
  output="";type("nihao");session.cancel();expect(output.isEmpty && session.state.candidates.isEmpty && session.state.input.isEmpty,"cancel clears without leak")
  for _ in 0..<100 {type("nihao");session.type(" ")};expect(output==String(repeating:"你好",count:100),"100 consecutive compositions")
  session.cancel();output="";type("nihaoshijie")
  if let short=session.state.candidates.first(where: {$0.text == "你好"}) {
   session.select(short); print("PARTIAL selection: output=\(output) input=\(session.state.input) preedit=\(session.state.preedit)")
   session.type(" "); expect(output=="你好世界", "partial candidate then space completes sentence")
  } else {expect(false, "partial candidate is available")}
  output="";type("nihao");let before=session.state;session.changePage(backward:true);expect(session.state.page==0 && session.state.input==before.input,"previous on first page preserves composition")
  session.cancel();output="";type("zzzzzz");session.type(" ");print("INVALID input fallback=\(output), remaining=\(session.state.input)")
  session.cancel();output="";type("hello");session.commitRaw()
  expect(output=="hello" && session.state.input.isEmpty && session.state.candidates.isEmpty,"raw commit inserts letters and clears composition")
  session.commitRaw();expect(output=="hello","raw commit is one-shot")
  session.cancel();output="";type("ni");let initial=session.state
  let enumerated=engine.candidatePage(startingAt: 8, limit: 10)
  let catalog=engine.candidatePage(startingAt: 0, limit: 32)
  expect(enumerated.candidates == Array(catalog.candidates.dropFirst(8).prefix(10)) && enumerated.nextIndex == 18,"nonmutating enumeration starts at requested grouped offset, including completion IDs")
  session.loadMoreCandidates()
  expect(session.state.candidates.count > initial.candidates.count && session.state.input == initial.input && session.state.preedit == initial.preedit,"expanded candidates preserve composition")
  let later=session.state.candidates.first(where: {$0.index >= 8})!
  session.select(later);expect(output == later.text,"expanded candidate ID maps back to its native selection")
  session.cancel();output="";type("nihoa")
  let corrected=session.state.candidates.first(where: {$0.index < 0})!
  session.loadMoreCandidates();session.select(corrected)
  expect(output == corrected.text && session.state.input.isEmpty,"expanding preserves correction selection route")
  session.cancel();output="";type("ni")
  for _ in 0..<20 { if session.state.isLastPage {break};session.loadMoreCandidates() }
  expect(session.state.isLastPage,"expanded scrolling reaches last candidate")
  expect(Set(session.state.candidates.map(\.index)).count == session.state.candidates.count,"expanded candidate identifiers stay unique")
  session.cancel()
  output="";type("nihao");session.type(" ");session.changePage(backward:false)
  expect(output == "你好", "paging after a commit cannot replay committed text")
  print("COMPLETE: \(checks) assertions")
 }
}
