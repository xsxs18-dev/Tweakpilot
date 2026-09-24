#import <Foundation/Foundation.h>

@interface TPStats : NSObject
+ (uint64_t)usedMemory;
+ (double)cpuUsage;
+ (NSInteger)batteryLevel;
@end
