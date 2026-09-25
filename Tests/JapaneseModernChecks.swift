import Foundation
@main struct JapaneseModernChecks {
    @MainActor static func main() throws {
        let resources=URL(fileURLWithPath:CommandLine.arguments[1]), user=URL(fileURLWithPath:CommandLine.arguments[2])
        let engine=try SKJapaneseEngine(resources:resources,userDirectory:user)
        let words:[(String,String)] = [
            ("sabusuku","サブスク"),("oshigoto","推し事"),("chattoji-pi-thi-","ChatGPT"),
            ("meroi","メロい"),("ehhoehho","エッホエッホ"),("guri-kuyo-guruto","グリークヨーグルト"),
            ("chokomashumaro","チョコマシュマロ"),("mimitsubojueri-","耳ツボジュエリー"),
            ("kuro-ba-koa","クローバーコア"),("retorofyu-cha-koa","レトロフューチャーコア"),
            ("wisshukoa","ウィッシュコア"),("bareekoa","バレエコア"),("nuikatsu","ぬい活")]
        var rows:[[String:Any]]=[]
        for (input,target) in words {
            _=engine.replaceInput(input)
            let texts=engine.candidatePage(startingAt:0,limit:64).candidates.map(\.text)
            let rank=texts.firstIndex(of:target).map {$0+1} ?? 0
            rows.append(["input":input,"target":target,"rank":rank,"top5":Array(texts.prefix(5))])
        }
        let data=try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:URL(fileURLWithPath:CommandLine.arguments[3]))
        let failed=rows.filter {($0["rank"] as! Int)==0 || ($0["rank"] as! Int)>10}
        print("Modern Japanese: \(rows.count-failed.count)/\(rows.count) Top10; \(failed)")
        if !failed.isEmpty {exit(1)}
    }
}
