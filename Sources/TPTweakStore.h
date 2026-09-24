#import <Foundation/Foundation.h>

@interface TPTweakEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) BOOL enabled;
@property (nonatomic) BOOL pending;
@end

@interface TPTweakStore : NSObject
+ (NSArray<TPTweakEntry *> *)loadEntries;
+ (void)setEnabled:(BOOL)enabled forTweak:(NSString *)name completion:(void (^)(NSString *error))completion;
+ (void)respring:(void (^)(NSString *error))completion;
+ (void)restartInjection:(void (^)(NSString *error))completion;
@end
