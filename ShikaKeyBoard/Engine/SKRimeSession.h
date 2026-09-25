#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Thin, serialized C API boundary. Swift never owns Rime's temporary pointers.
@interface SKRimeSession : NSObject
- (nullable instancetype)initWithSharedPath:(NSString *)sharedPath
                                  userPath:(NSString *)userPath
                                    schema:(NSString *)schema
                                     error:(NSError **)error;
- (NSDictionary *)processKey:(int)key;
- (NSDictionary *)selectCandidate:(NSUInteger)index;
- (NSDictionary *)candidatePageFromIndex:(NSUInteger)index limit:(NSUInteger)limit;
- (NSDictionary *)changePage:(BOOL)backward;
- (NSDictionary *)commitComposition;
- (NSDictionary *)clearComposition;
- (NSDictionary *)selectSchema:(NSString *)schema;
- (NSDictionary *)snapshot;
- (NSDictionary *)replaceInput:(NSString *)input;
- (NSDictionary *)selectText:(NSString *)text;
@end
NS_ASSUME_NONNULL_END
