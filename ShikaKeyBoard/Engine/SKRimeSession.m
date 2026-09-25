#import "SKRimeSession.h"
#include <rime_api.h>

static NSRecursiveLock *RimeLock(void) {
    static NSRecursiveLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSRecursiveLock new]; });
    return lock;
}
static NSString *Text(const char *text) { return text ? [NSString stringWithUTF8String:text] ?: @"" : @""; }

// Process lifetime is separate from session lifetime. Call under RimeLock().
// All sessions in one extension process share the same immutable directories.
@interface SKRimeRuntime : NSObject
+ (RimeApi *)prepareSharedPath:(NSString *)sharedPath userPath:(NSString *)userPath error:(NSError **)error;
@end

@implementation SKRimeRuntime
+ (RimeApi *)prepareSharedPath:(NSString *)sharedPath userPath:(NSString *)userPath error:(NSError **)error {
    RimeApi *api = rime_get_api();
    static NSString *sharedDirectory;
    static NSString *userDirectory;
    sharedPath = sharedPath.stringByStandardizingPath;
    userPath = userPath.stringByStandardizingPath;
    if (sharedDirectory && (![sharedDirectory isEqualToString:sharedPath] || ![userDirectory isEqualToString:userPath])) {
        if (error) *error = [NSError errorWithDomain:@"Shika.Rime" code:2
            userInfo:@{NSLocalizedDescriptionKey: @"Rime 运行时已使用另一组资源目录初始化"}];
        return NULL;
    }
    if (!sharedDirectory) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:userPath withIntermediateDirectories:YES attributes:nil error:error]) {
            return NULL;
        }
        // Production uses precompiled bundle data. Never deploy or write into the bundle.
        RIME_STRUCT(RimeTraits, traits);
        traits.shared_data_dir = sharedPath.UTF8String;
        traits.prebuilt_data_dir = [sharedPath stringByAppendingPathComponent:@"build"].UTF8String;
        traits.user_data_dir = userPath.UTF8String;
        traits.app_name = "rime.shika";
        traits.min_log_level = 3;
        traits.log_dir = "";
        static const char *modules[] = {"default", NULL};
        traits.modules = modules;
        api->setup(&traits);
        api->initialize(&traits);
        sharedDirectory = [sharedPath copy];
        userDirectory = [userPath copy];
    }
    return api;
}
@end

@implementation SKRimeSession {
    RimeSessionId _session;
    RimeApi *_api;
}
- (instancetype)initWithSharedPath:(NSString *)sharedPath userPath:(NSString *)userPath schema:(NSString *)schema error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    [RimeLock() lock];
    _api = [SKRimeRuntime prepareSharedPath:sharedPath userPath:userPath error:error];
    if (!_api) { [RimeLock() unlock]; return nil; }
    _session = _api->create_session();
    BOOL ok = _session && _api->select_schema(_session, schema.UTF8String);
    if (ok) _api->set_option(_session, "ascii_mode", False);
    if (!ok && error) *error = [NSError errorWithDomain:@"Shika.Rime" code:1 userInfo:@{NSLocalizedDescriptionKey: @"无法加载离线输入方案"}];
    [RimeLock() unlock];
    return ok ? self : nil;
}
- (void)dealloc {
    [RimeLock() lock];
    if (_session) _api->destroy_session(_session);
    // Rime is process-global; another keyboard session may still be alive.
    [RimeLock() unlock];
}
- (NSDictionary *)snapshot {
    [RimeLock() lock];
    RIME_STRUCT(RimeContext, context);
    NSMutableArray *candidates = [NSMutableArray new];
    NSString *preedit = @"";
    NSInteger page = 0;
    BOOL lastPage = YES;
    if (_api->get_context(_session, &context)) {
        preedit = Text(context.composition.preedit);
        page = context.menu.page_no;
        lastPage = context.menu.is_last_page;
        for (int i = 0; i < context.menu.num_candidates; ++i) {
            RimeCandidate candidate = context.menu.candidates[i];
            [candidates addObject:@{@"text": Text(candidate.text), @"comment": Text(candidate.comment),
                @"index": @(page * context.menu.page_size + i)}];
        }
        _api->free_context(&context);
    }
    NSString *commit = @"";
    RIME_STRUCT(RimeCommit, committed);
    if (_api->get_commit(_session, &committed)) {
        commit = Text(committed.text);
        _api->free_commit(&committed);
    }
    NSDictionary *result = @{@"preedit": preedit, @"input": Text(_api->get_input(_session)),
        @"commit": commit, @"candidates": candidates, @"page": @(page), @"lastPage": @(lastPage)};
    [RimeLock() unlock];
    return result;
}
- (NSDictionary *)replaceInput:(NSString *)input {
    [RimeLock() lock];
    _api->clear_composition(_session);
    _api->set_input(_session, input.UTF8String);
    NSDictionary *result = [self snapshot];
    [RimeLock() unlock]; return result;
}
- (NSDictionary *)selectText:(NSString *)text {
    [RimeLock() lock];
    RimeCandidateListIterator iterator = {0};
    NSInteger found = -1;
    if (_api->candidate_list_begin(_session, &iterator)) {
        while (_api->candidate_list_next(&iterator)) {
            if ([Text(iterator.candidate.text) isEqualToString:text]) { found = iterator.index; break; }
            if (iterator.index >= 127) break;
        }
        _api->candidate_list_end(&iterator);
    }
    if (found >= 0) _api->select_candidate(_session, (size_t)found);
    NSMutableDictionary *result = [[self snapshot] mutableCopy];
    result[@"matched"] = @(found >= 0);
    [RimeLock() unlock]; return result;
}
- (NSDictionary *)processKey:(int)key {
    [RimeLock() lock];
    BOOL handled = _api->process_key(_session, key, 0);
    NSMutableDictionary *result = [[self snapshot] mutableCopy];
    result[@"handled"] = @(handled);
    [RimeLock() unlock]; return result;
}
- (NSDictionary *)selectCandidate:(NSUInteger)index {
    [RimeLock() lock]; _api->select_candidate(_session, index);
    NSDictionary *result = [self snapshot]; [RimeLock() unlock]; return result;
}
// Enumerate without changing the selected page, composition or correction routes.
- (NSDictionary *)candidatePageFromIndex:(NSUInteger)index limit:(NSUInteger)limit {
    [RimeLock() lock];
    NSMutableArray *candidates = [NSMutableArray new];
    RimeCandidateListIterator iterator = {0};
    NSUInteger nextIndex = index;
    BOOL more = NO;
    if (limit && _api->candidate_list_from_index(_session, &iterator, (int)index)) {
        while (_api->candidate_list_next(&iterator)) {
            if (candidates.count == limit) { more = YES; break; }
            [candidates addObject:@{@"index": @(iterator.index), @"text": Text(iterator.candidate.text),
                @"comment": Text(iterator.candidate.comment)}];
            nextIndex = iterator.index + 1;
        }
        _api->candidate_list_end(&iterator);
    }
    [RimeLock() unlock];
    return @{@"candidates": candidates, @"nextIndex": @(nextIndex), @"hasMore": @(more)};
}
- (NSDictionary *)changePage:(BOOL)backward {
    [RimeLock() lock]; _api->change_page(_session, backward);
    NSDictionary *result = [self snapshot]; [RimeLock() unlock]; return result;
}
- (NSDictionary *)commitComposition {
    [RimeLock() lock]; _api->commit_composition(_session);
    NSDictionary *result = [self snapshot]; [RimeLock() unlock]; return result;
}
- (NSDictionary *)clearComposition {
    [RimeLock() lock]; _api->clear_composition(_session);
    NSDictionary *result = [self snapshot]; [RimeLock() unlock]; return result;
}
- (NSDictionary *)selectSchema:(NSString *)schema {
    [RimeLock() lock];
    _api->clear_composition(_session);
    BOOL ok = _api->select_schema(_session, schema.UTF8String);
    _api->set_option(_session, "ascii_mode", False);
    NSMutableDictionary *result = [[self snapshot] mutableCopy];
    if (!ok) result[@"error"] = @"无法切换输入方案";
    [RimeLock() unlock]; return result;
}
@end
