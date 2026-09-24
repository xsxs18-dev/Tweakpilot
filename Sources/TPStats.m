#import "TPStats.h"
#import <UIKit/UIKit.h>
#import <mach/mach.h>

@implementation TPStats

+ (uint64_t)usedMemory {
	vm_statistics64_data_t vm;
	mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
	if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vm, &count) != KERN_SUCCESS) return 0;
	uint64_t pages = (uint64_t)vm.active_count + vm.wire_count + vm.compressor_page_count;
	return pages * vm_kernel_page_size;
}

+ (double)cpuUsage {
	static uint64_t prevBusy, prevTotal;

	natural_t cpuCount = 0;
	processor_info_array_t info = NULL;
	mach_msg_type_number_t infoCount = 0;
	if (host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) != KERN_SUCCESS) return 0;

	uint64_t busy = 0, total = 0;
	for (natural_t i = 0; i < cpuCount; i++) {
		integer_t *ticks = &info[i * CPU_STATE_MAX];
		uint64_t user = ticks[CPU_STATE_USER], sys = ticks[CPU_STATE_SYSTEM];
		uint64_t nice = ticks[CPU_STATE_NICE], idle = ticks[CPU_STATE_IDLE];
		busy += user + sys + nice;
		total += user + sys + nice + idle;
	}
	vm_deallocate(mach_task_self(), (vm_address_t)info, infoCount * sizeof(integer_t));

	double usage = 0;
	if (prevTotal != 0 && total > prevTotal) {
		usage = 100.0 * (double)(busy - prevBusy) / (double)(total - prevTotal);
	}
	prevBusy = busy;
	prevTotal = total;
	return MAX(0, MIN(100, usage));
}

+ (NSInteger)batteryLevel {
	UIDevice *device = [UIDevice currentDevice];
	device.batteryMonitoringEnabled = YES;
	float level = device.batteryLevel;
	return level < 0 ? -1 : (NSInteger)lroundf(level * 100);
}

@end
