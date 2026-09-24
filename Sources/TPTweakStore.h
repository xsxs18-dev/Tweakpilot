#import <Foundation/Foundation.h>

@interface TPTweakEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) BOOL enabled;
// Toggled this session; takes effect after a respring.
@property (nonatomic) BOOL pending;
@end

@interface TPTweakStore : NSObject
+ (NSArray<TPTweakEntry *> *)loadEntries;
+ (void)setEnabled:(BOOL)enabled forTweak:(NSString *)name completion:(void (^)(BOOL success))completion;
+ (void)respring;
+ (void)restartInjection;
@end
