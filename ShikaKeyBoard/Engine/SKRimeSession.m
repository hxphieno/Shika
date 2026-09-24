#import "SKRimeSession.h"
#include <rime_api.h>

static NSRecursiveLock *RimeLock(void) {
    static NSRecursiveLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSRecursiveLock new]; });
    return lock;
}
static NSString *Text(const char *text) { return text ? [NSString stringWithUTF8String:text] ?: @"" : @""; }

@implementation SKRimeSession {
    RimeSessionId _session;
    RimeApi *_api;
}
- (instancetype)initWithSharedPath:(NSString *)sharedPath userPath:(NSString *)userPath schema:(NSString *)schema error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    [RimeLock() lock];
    _api = rime_get_api();
    static BOOL initialized = NO;
    if (!initialized) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:userPath withIntermediateDirectories:YES attributes:nil error:error]) {
            [RimeLock() unlock]; return nil;
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
        _api->setup(&traits);
        _api->initialize(&traits);
        initialized = YES;
    }
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
