#import <Foundation/Foundation.h>

@interface TPStats : NSObject
// Used physical memory in bytes.
+ (uint64_t)usedMemory;
// Total CPU load in percent since the previous call (0–100).
+ (double)cpuUsage;
// Battery level in percent, or -1 if unknown.
+ (NSInteger)batteryLevel;
@end
