#import "TPTweakStore.h"
#import "TPRoot.h"
#import <spawn.h>
#import <sys/wait.h>

extern char **environ;

static NSString *const kSelfName = @"Tweakpilot";
static NSString *const kDisabledSuffix = @".dylib.disabled";

@implementation TPTweakEntry
@end

@implementation TPTweakStore

static NSMutableSet<NSString *> *pendingNames(void) {
	static NSMutableSet *set;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ set = [NSMutableSet set]; });
	return set;
}

+ (NSArray<TPTweakEntry *> *)loadEntries {
	NSString *dir = TPJBRoot(@"/Library/MobileSubstrate/DynamicLibraries");
	NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
	NSMutableArray *entries = [NSMutableArray array];

	for (NSString *file in files) {
		NSString *name;
		BOOL enabled;
		if ([file hasSuffix:kDisabledSuffix]) {
			name = [file substringToIndex:file.length - kDisabledSuffix.length];
			enabled = NO;
		} else if ([file.pathExtension isEqualToString:@"dylib"]) {
			name = file.stringByDeletingPathExtension;
			enabled = YES;
		} else {
			continue;
		}
		if ([name isEqualToString:kSelfName] || [name hasPrefix:@"."]) continue;

		TPTweakEntry *entry = [TPTweakEntry new];
		entry.name = name;
		entry.enabled = enabled;
		entry.pending = [pendingNames() containsObject:name];
		[entries addObject:entry];
	}

	[entries sortUsingComparator:^NSComparisonResult(TPTweakEntry *a, TPTweakEntry *b) {
		return [a.name localizedCaseInsensitiveCompare:b.name];
	}];
	return entries;
}

static int runHelper(NSArray<NSString *> *args, BOOL wait) {
	NSString *helper = TPJBRoot(@"/usr/libexec/tweakpilot/tpctl");
	NSUInteger count = args.count;
	char *argv[count + 2];
	argv[0] = (char *)"tpctl";
	for (NSUInteger i = 0; i < count; i++) argv[i + 1] = (char *)args[i].UTF8String;
	argv[count + 1] = NULL;

	pid_t pid;
	if (posix_spawn(&pid, helper.fileSystemRepresentation, NULL, NULL, argv, environ) != 0) return -1;
	if (!wait) return 0;
	int status = 0;
	waitpid(pid, &status, 0);
	return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

+ (void)setEnabled:(BOOL)enabled forTweak:(NSString *)name completion:(void (^)(BOOL))completion {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		BOOL ok = runHelper(@[enabled ? @"enable" : @"disable", name], YES) == 0;
		dispatch_async(dispatch_get_main_queue(), ^{
			if (ok) {
				NSMutableSet *pending = pendingNames();
				// Toggling back to the original state clears the pending mark.
				if ([pending containsObject:name]) [pending removeObject:name];
				else [pending addObject:name];
			}
			if (completion) completion(ok);
		});
	});
}

+ (void)respring {
	runHelper(@[@"respring"], NO);
}

+ (void)restartInjection {
	runHelper(@[@"userspace"], NO);
}

@end
