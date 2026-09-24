import Foundation
import Darwin
func memory() -> UInt64 {var v=task_vm_info_data_t();var n=mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size/MemoryLayout<integer_t>.size);let _=withUnsafeMutablePointer(to:&v){p in p.withMemoryRebound(to:integer_t.self,capacity:Int(n)){task_info(mach_task_self_,task_flavor_t(TASK_VM_INFO),$0,&n)}};return v.phys_footprint}
@main struct Main {
 @MainActor static func main() throws {
  setbuf(stdout,nil);let resource=URL(fileURLWithPath:CommandLine.arguments[1]);let mode=CommandLine.arguments[2]
  print("before",memory())
  var corrector:SKSpellingCorrector?;var engine:SKRimeEngine?
  if mode=="engine" || mode=="commit" {engine=try SKRimeEngine(schema:"shika_flypy",resourceURL:resource,userURL:URL(fileURLWithPath:CommandLine.arguments[3]))}
  print("init",memory())
  for i in 1...500 {try autoreleasepool {
   let schema=i%2==1 ? "shika_pinyin" : "shika_flypy"
   if mode=="index" || mode=="search" {corrector=SKSpellingCorrector(resources:resource,schema:schema)}
   if mode=="search" {_=corrector!.suggestions(for:i%2==1 ? "zhnogguo" : "niihc")}
   if let engine {
     _=try engine.selectSchema(schema)
     let full=[("nohao","你好"),("zhnogguo","中国"),("zhongguoo","中国"),("zhonguo","中国")]
     let double=[("nijc","你好"),("niihc","你好"),("nhc","你好"),("svgo","中国")]
     let pair=(i%2==1 ? full:double)[((i-1)/2)%4];var st=SKEngineState()
     for key in pair.0.utf8 {st=engine.process(key:Int32(key))}
     if mode=="commit",let c=st.candidates.first(where:{$0.text==pair.1}){_=engine.selectCandidate(at:c.index)}
     _=engine.clear()
   }
  }; if i==1||i%20==0{print(i,memory())}}
  corrector=nil;engine=nil;print("release",memory())
 }
}
