#import "TPTweakStore.h"
#import "TPRoot.h"
#import <dlfcn.h>
#import <notify.h>
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

static uint64_t nameHash(NSString *name) {
	uint64_t hash = 1469598103934665603ULL;
	for (const unsigned char *p = (const unsigned char *)name.UTF8String; *p; p++) {
		hash ^= *p;
		hash *= 1099511628211ULL;
	}
	return hash & 0xFFFFFFFFFFFFULL;
}

static NSString *daemonError(int code, int err) {
	switch (code) {
		case 0: return nil;
		case 65: return @"This tweak can't be switched.";
		case 66: return @"Tweak file not found. Try closing and reopening the panel.";
		case 73: return [NSString stringWithFormat:@"Rename failed: %s", strerror(err)];
		default: return [NSString stringWithFormat:@"TweakPilot service error %d", code];
	}
}

static NSString *askDaemon(uint64_t action, NSString *name, BOOL *reachable, NSString **diagnosis) {
	*reachable = NO;
	NSString *failure;
	NSString *helper = findHelper(&failure);
	if (!helper) {
		*diagnosis = failure;
		return nil;
	}

	NSString *tokenPath = [helper.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"token"];
	struct stat st;
	if (stat(tokenPath.fileSystemRepresentation, &st) != 0) {
		*diagnosis = [NSString stringWithFormat:@"Service key missing (%s). The service never started.", strerror(errno)];
		return nil;
	}
	NSError *readError;
	NSString *token = [[NSString stringWithContentsOfFile:tokenPath encoding:NSUTF8StringEncoding error:&readError]
		stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (token.length != 32) {
		*diagnosis = [NSString stringWithFormat:@"Service key not readable (%@).", readError.localizedDescription ?: @"wrong length"];
		return nil;
	}

	static uint8_t counter;
	uint64_t seq = ++counter;
	uint64_t value = (action << 56) | (seq << 48) | (name ? nameHash(name) : 0);

	static dispatch_queue_t replyQueue;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ replyQueue = dispatch_queue_create("com.xsxs18.tweakpilot.reply", DISPATCH_QUEUE_SERIAL); });

	NSString *request = [@"com.xsxs18.tweakpilot.request." stringByAppendingString:token];
	NSString *response = [@"com.xsxs18.tweakpilot.response." stringByAppendingString:token];
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	__block uint64_t reply = 0;

	int responseToken;
	uint32_t status = notify_register_dispatch(response.UTF8String, &responseToken, replyQueue, ^(int t) {
		uint64_t state = 0;
		notify_get_state(t, &state);
		if ((state & 0xFF) == seq) {
			reply = state;
			dispatch_semaphore_signal(done);
		}
	});
	if (status != NOTIFY_STATUS_OK) {
		*diagnosis = [NSString stringWithFormat:@"Can't listen for the service (notify %u).", status];
		return nil;
	}

	int requestToken;
	status = notify_register_check(request.UTF8String, &requestToken);
	if (status == NOTIFY_STATUS_OK) {
		status = notify_set_state(requestToken, value);
		if (status == NOTIFY_STATUS_OK) status = notify_post(request.UTF8String);
		notify_cancel(requestToken);
	}
	if (status != NOTIFY_STATUS_OK) {
		notify_cancel(responseToken);
		*diagnosis = [NSString stringWithFormat:@"Can't reach the service (notify %u).", status];
		return nil;
	}

	long timedOut = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
	notify_cancel(responseToken);
	if (timedOut) {
		*diagnosis = @"Service key found, but the service didn't answer. It may have crashed or be stuck.";
		return nil;
	}

	*reachable = YES;
	return daemonError((int)((reply >> 8) & 0xFF), (int)((reply >> 16) & 0xFFFF));
}

static NSString *perform(uint64_t action, NSString *name, NSArray<NSString *> *helperArgs) {
	BOOL reachable;
	NSString *diagnosis = @"unknown";
	NSString *error = askDaemon(action, name, &reachable, &diagnosis);
	if (reachable) return error;

	NSString *helperError = runHelper(helperArgs);
	if (!helperError) return nil;
	return [NSString stringWithFormat:@"Service: %@\n\nHelper: %@", diagnosis, helperError];
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
	static dispatch_queue_t queue;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ queue = dispatch_queue_create("com.xsxs18.tweakpilot.work", DISPATCH_QUEUE_SERIAL); });
	dispatch_async(queue, ^{
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
		return perform(enabled ? 1 : 2, name, @[enabled ? @"enable" : @"disable", name]);
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

	id action = ((id (*)(id, SEL, NSString *, NSUInteger, NSURL *))objc_msgSend)(actionClass, actionSel, @"TweakPilot", 1 << 2, nil);
	id service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, sharedSel);
	if (!action || ![service respondsToSelector:sendSel]) return NO;

	((void (*)(id, SEL, NSSet *, id))objc_msgSend)(service, sendSel, [NSSet setWithObject:action], nil);
	return YES;
}

+ (void)respring:(void (^)(NSString *))completion {
	if (relaunchSpringBoard()) return;
	runInBackground(^NSString *{
		return perform(3, nil, @[@"respring"]);
	}, completion);
}

+ (void)restartInjection:(void (^)(NSString *))completion {
	runInBackground(^NSString *{
		return perform(4, nil, @[@"userspace"]);
	}, completion);
}

@end
