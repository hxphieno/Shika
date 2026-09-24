#import <Foundation/Foundation.h>
#import "SKRimeSession.h"
#include <assert.h>

static NSDictionary *Type(SKRimeSession *session, NSString *code) {
    NSDictionary *state = nil;
    for (NSUInteger i=0; i<code.length; i++) state=[session processKey:[code characterAtIndex:i]];
    return state;
}
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 3) return 2;
        NSError *error=nil;
        SKRimeSession *session=[[SKRimeSession alloc] initWithSharedPath:@(argv[1]) userPath:@(argv[2]) schema:@"shika_flypy" error:&error];
        if(!session) { NSLog(@"%@",error); return 1; }
        NSArray *cases=@[@[@"shika_flypy",@"nihc",@"你好"],@[@"shika_flypy",@"vsgo",@"中国"],@[@"shika_flypy",@"uijp",@"世界"],@[@"shika_flypy",@"aa",@"啊"],@[@"shika_pinyin",@"nihao",@"你好"],@[@"shika_pinyin",@"zhongguo",@"中国"],@[@"shika_pinyin",@"shijie",@"世界"]];
        for (NSArray *test in cases) {
            [session selectSchema:test[0]];
            NSDictionary *state=Type(session,test[1]);
            assert([state[@"commit"] length]==0);
            NSUInteger index=NSNotFound;
            for (NSDictionary *candidate in state[@"candidates"]) if ([candidate[@"text"] isEqual:test[2]]) index=[candidate[@"index"] unsignedIntegerValue];
            if(index==NSNotFound) { NSLog(@"FAIL %@ %@",test,state); return 1; }
            NSDictionary *result=[session selectCandidate:index];
            assert([result[@"commit"] isEqual:test[2]]);
            assert([result[@"input"] length]==0);
            assert([[session snapshot][@"commit"] length]==0);
            NSLog(@"PASS %@ %@ -> %@",test[0],test[1],result[@"commit"]);
        }
        [session selectSchema:@"shika_pinyin"];
        Type(session,@"nihao");
        NSDictionary *state=[session processKey:0xff08];
        assert([state[@"input"] isEqual:@"niha"]);
        [session clearComposition];
        Type(session,@"ni");
        state=[session changePage:NO];
        assert([state[@"page"] intValue]==1);
        assert([state[@"candidates"] count]>0);
        NSDictionary *choice=state[@"candidates"][1];
        state=[session selectCandidate:[choice[@"index"] unsignedIntegerValue]];
        assert([state[@"commit"] isEqual:choice[@"text"]]);
        [session clearComposition];
        Type(session,@"nihao");
        state=[session processKey:32];
        assert([state[@"commit"] isEqual:@"你好"]);
        NSLog(@"PASS editing, pagination, non-first selection, space commit, one-shot commit");
    }
    return 0;
}
