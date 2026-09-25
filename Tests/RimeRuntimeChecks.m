#import <Foundation/Foundation.h>
#import "SKRimeSession.h"

// Rime is process-global: sessions may share one runtime, never silently replace it.
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 3) return 2;
        NSString *shared = @(argv[1]), *user = @(argv[2]);
        NSError *error = nil;
        SKRimeSession *first = [[SKRimeSession alloc] initWithSharedPath:shared userPath:user schema:@"shika_pinyin" error:&error];
        SKRimeSession *second = [[SKRimeSession alloc] initWithSharedPath:shared userPath:[user stringByAppendingString:@"/."] schema:@"shika_flypy" error:&error];
        if (!first || !second) { NSLog(@"FAIL shared runtime: %@", error); return 1; }
        SKRimeSession *wrongUser = [[SKRimeSession alloc] initWithSharedPath:shared userPath:[user stringByAppendingString:@"-other"] schema:@"shika_pinyin" error:&error];
        if (wrongUser || error.code != 2) return 1;
        error = nil;
        SKRimeSession *wrongResources = [[SKRimeSession alloc] initWithSharedPath:[shared stringByAppendingString:@"-other"] userPath:user schema:@"shika_pinyin" error:&error];
        if (wrongResources || error.code != 2) return 1;
        first = nil;
        NSDictionary *state;
        for (NSNumber *key in @[@'n', @'i', @'h', @'c']) state = [second processKey:key.intValue];
        if (![state[@"candidates"][0][@"text"] isEqual:@"你好"]) return 1;
        state = [second processKey:' '];
        if (![state[@"commit"] isEqual:@"你好"]) return 1;
        NSLog(@"PASS shared runtime, normalized paths, conflicting directory rejection and surviving session input");
    }
    return 0;
}
