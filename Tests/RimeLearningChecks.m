#import <Foundation/Foundation.h>
#import "SKRimeSession.h"

static NSDictionary *TypeNi(SKRimeSession *session) {
    [session processKey:'n'];
    return [session processKey:'i'];
}

// Invoke once with "learn", then in a separate process with "probe".
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 4) return 2;
        NSError *error = nil;
        SKRimeSession *session = [[SKRimeSession alloc]
            initWithSharedPath:@(argv[1]) userPath:@(argv[2])
            schema:@"shika_pinyin" error:&error];
        if (!session) { NSLog(@"FAIL: %@", error); return 1; }
        NSDictionary *state = TypeNi(session);
        if ([@(argv[3]) isEqual:@"probe"]) {
            BOOL persisted = [state[@"candidates"][0][@"text"] isEqual:@"腻"];
            NSLog(@"%@: learned 腻 ranks first in a new process", persisted ? @"PASS" : @"FAIL");
            return persisted ? 0 : 1;
        }
        if (![@(argv[3]) isEqual:@"learn"]) return 2;
        if ([state[@"candidates"][0][@"text"] isEqual:@"腻"]) {
            NSLog(@"FAIL: expected a fresh user directory"); return 1;
        }
        for (int repetition = 0; repetition < 5; repetition++) {
            [session clearComposition];
            state = TypeNi(session);
            BOOL selected = NO;
            for (int page = 0; page < 30; page++) {
                for (NSDictionary *candidate in state[@"candidates"]) {
                    if ([candidate[@"text"] isEqual:@"腻"]) {
                        state = [session selectCandidate:[candidate[@"index"] unsignedIntegerValue]];
                        if (![state[@"commit"] isEqual:@"腻"]) return 1;
                        selected = YES;
                        break;
                    }
                }
                if (selected || [state[@"lastPage"] boolValue]) break;
                state = [session changePage:NO];
            }
            if (!selected) { NSLog(@"FAIL: target candidate missing"); return 1; }
        }
        [session clearComposition];
        state = TypeNi(session);
        if (![state[@"candidates"][0][@"text"] isEqual:@"腻"]) return 1;
        NSLog(@"PASS: repeated selection promotes 腻 to first candidate");
    }
    return 0;
}
