#import <Foundation/Foundation.h>
#import "SKRimeSession.h"
#import "rime_api.h"
int main(int argc, const char **argv) {
  @autoreleasepool {
    if (argc != 3) return 2;
    NSError *error = nil;
    SKRimeSession *session = [[SKRimeSession alloc] initWithSharedPath:@(argv[1]) userPath:@(argv[2]) schema:@"shika_flypy" error:&error];
    if (!session) { NSLog(@"%@", error); return 1; }
    RimeApi *api = rime_get_api();
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"version"] = @(api->get_version());
    for (NSString *schema in @[@"shika_flypy", @"shika_pinyin", @"shika_flypy_assist"]) {
      RimeConfig config = {0};
      if (!api->schema_open(schema.UTF8String, &config)) return 3;
      int sentences = 0, homophones = 0; double cutoff = 0;
      api->config_get_int(&config, "translator/max_sentences", &sentences);
      api->config_get_int(&config, "translator/max_homophones", &homophones);
      api->config_get_double(&config, "translator/sentence_cutoff_threshold", &cutoff);
      result[schema] = @{@"max_sentences": @(sentences), @"max_homophones": @(homophones), @"sentence_cutoff_threshold": @(cutoff)};
      api->config_close(&config);
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
    puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
  }
}
