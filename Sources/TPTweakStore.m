#import "TPTweakStore.h"
#import "TPRoot.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <unistd.h>

extern char **environ;

static NSString *const kSelfName = @"Tweakpilot";
static NSString *const kDisabledSuffix = @".dylib.disabled";
static NSString *const kHelperSubpath = @"usr/libexec/tweakpilot/tpctl";

@implementation TPTweakEntry
@end

@implementation TPTweakStore

static NSMutableSet<NSString *> *pendingNames(void) {
	static NSMutableSet *set;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ set = [NSMutableSet set]; });
	return set;
}

static NSString *tweakDirectory(void) {
	return TPJBRoot(@"/Library/MobileSubstrate/DynamicLibraries");
}

+ (NSArray<TPTweakEntry *> *)loadEntries {
	NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tweakDirectory() error:nil];
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

static NSArray<NSString *> *helperCandidates(void) {
	NSMutableOrderedSet *paths = [NSMutableOrderedSet orderedSet];
	[paths addObject:TPJBRoot([@"/" stringByAppendingString:kHelperSubpath])];

	Dl_info info;
	if (dladdr((const void *)&helperCandidates, &info) && info.dli_fname) {
		NSString *dylibDir = [[NSString stringWithUTF8String:info.dli_fname] stringByDeletingLastPathComponent];
		for (NSString *dir in @[dylibDir, dylibDir.stringByResolvingSymlinksInPath]) {
			for (NSString *suffix in @[@"/Library/MobileSubstrate/DynamicLibraries", @"/usr/lib/TweakInject"]) {
				if ([dir hasSuffix:suffix]) {
					NSString *root = [dir substringToIndex:dir.length - suffix.length];
					[paths addObject:[root stringByAppendingPathComponent:kHelperSubpath]];
				}
			}
		}
	}

	NSString *resolved = [tweakDirectory() stringByResolvingSymlinksInPath];
	if ([resolved hasSuffix:@"/usr/lib/TweakInject"]) {
		NSString *root = [resolved substringToIndex:resolved.length - @"/usr/lib/TweakInject".length];
		[paths addObject:[root stringByAppendingPathComponent:kHelperSubpath]];
	}
	return paths.array;
}

static NSString *findHelper(NSString **failure) {
	NSMutableArray *reasons = [NSMutableArray array];
	for (NSString *path in helperCandidates()) {
		struct stat st;
		if (stat(path.fileSystemRepresentation, &st) == 0 && S_ISREG(st.st_mode)) return path;
		[reasons addObject:[NSString stringWithFormat:@"%@ (%s)", path, strerror(errno)]];
	}
	if (failure) *failure = [NSString stringWithFormat:@"Helper not reachable:\n%@", [reasons componentsJoinedByString:@"\n"]];
	return nil;
}

static NSString *runHelper(NSArray<NSString *> *args) {
	NSString *failure;
	NSString *helper = findHelper(&failure);
	if (!helper) return failure;

	NSUInteger count = args.count;
	char *argv[count + 2];
	argv[0] = (char *)"tpctl";
	for (NSUInteger i = 0; i < count; i++) argv[i + 1] = (char *)args[i].UTF8String;
	argv[count + 1] = NULL;

	int fds[2];
	if (pipe(fds) != 0) return @"Could not create pipe";
	posix_spawn_file_actions_t actions;
	posix_spawn_file_actions_init(&actions);
	posix_spawn_file_actions_adddup2(&actions, fds[1], STDERR_FILENO);
	posix_spawn_file_actions_addclose(&actions, fds[0]);

	pid_t pid;
	int err = posix_spawn(&pid, helper.fileSystemRepresentation, &actions, NULL, argv, environ);
	posix_spawn_file_actions_destroy(&actions);
	close(fds[1]);
	if (err != 0) {
		close(fds[0]);
		return [NSString stringWithFormat:@"Could not launch helper at %@: %s", helper, strerror(err)];
	}

	NSMutableData *output = [NSMutableData data];
	char buffer[512];
	ssize_t n;
	while ((n = read(fds[0], buffer, sizeof(buffer))) > 0) [output appendBytes:buffer length:n];
	close(fds[0]);

	int status = 0;
	waitpid(pid, &status, 0);
	if (WIFEXITED(status) && WEXITSTATUS(status) == 0) return nil;

	NSString *message = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
	message = [message stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (message.length) return message;
	if (WIFSIGNALED(status)) return [NSString stringWithFormat:@"Helper was killed (signal %d). Your jailbreak may not allow it to run.", WTERMSIG(status)];
	return [NSString stringWithFormat:@"Helper failed with code %d", WEXITSTATUS(status)];
}

static BOOL renameDirectly(NSString *name, BOOL enable) {
	NSString *dir = tweakDirectory();
	NSString *on = [dir stringByAppendingPathComponent:[name stringByAppendingString:@".dylib"]];
	NSString *off = [dir stringByAppendingPathComponent:[name stringByAppendingString:kDisabledSuffix]];
	NSString *from = enable ? off : on;
	NSString *to = enable ? on : off;
	return rename(from.fileSystemRepresentation, to.fileSystemRepresentation) == 0;
}

static void runInBackground(NSString *(^work)(void), void (^completion)(NSString *error)) {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSString *error = work();
		dispatch_async(dispatch_get_main_queue(), ^{
			if (completion) completion(error);
		});
	});
}

+ (void)setEnabled:(BOOL)enabled forTweak:(NSString *)name completion:(void (^)(NSString *))completion {
	if ([name containsString:@"/"] || [name hasPrefix:@"."]) {
		if (completion) completion(@"Invalid tweak name");
		return;
	}
	runInBackground(^NSString *{
		if (renameDirectly(name, enabled)) return nil;
		return runHelper(@[enabled ? @"enable" : @"disable", name]);
	}, ^(NSString *error) {
		if (!error) {
			NSMutableSet *pending = pendingNames();
			if ([pending containsObject:name]) [pending removeObject:name];
			else [pending addObject:name];
		}
		if (completion) completion(error);
	});
}

static BOOL relaunchSpringBoard(void) {
	Class serviceClass = NSClassFromString(@"FBSSystemService");
	Class actionClass = NSClassFromString(@"SBSRelaunchAction");
	SEL actionSel = NSSelectorFromString(@"actionWithReason:options:targetURL:");
	SEL sharedSel = NSSelectorFromString(@"sharedService");
	SEL sendSel = NSSelectorFromString(@"sendActions:withResult:");
	if (!serviceClass || !actionClass || ![actionClass respondsToSelector:actionSel] || ![serviceClass respondsToSelector:sharedSel]) return NO;

	id action = ((id (*)(id, SEL, NSString *, NSUInteger, NSURL *))objc_msgSend)(actionClass, actionSel, @"Tweakpilot", 1 << 2, nil);
	id service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, sharedSel);
	if (!action || ![service respondsToSelector:sendSel]) return NO;

	((void (*)(id, SEL, NSSet *, id))objc_msgSend)(service, sendSel, [NSSet setWithObject:action], nil);
	return YES;
}

+ (void)respring:(void (^)(NSString *))completion {
	if (relaunchSpringBoard()) return;
	runInBackground(^NSString *{
		return runHelper(@[@"respring"]);
	}, completion);
}

+ (void)restartInjection:(void (^)(NSString *))completion {
	runInBackground(^NSString *{
		return runHelper(@[@"userspace"]);
	}, completion);
}

@end
