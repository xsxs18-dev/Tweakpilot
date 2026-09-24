#import "TPTweakStore.h"
#import "TPRoot.h"
#import <spawn.h>
#import <unistd.h>
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

static NSString *runHelper(NSArray<NSString *> *args) {
	NSString *helper = TPJBRoot(@"/usr/libexec/tweakpilot/tpctl");
	if (![[NSFileManager defaultManager] isExecutableFileAtPath:helper]) {
		return [NSString stringWithFormat:@"Helper not found at %@", helper];
	}

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
		return [NSString stringWithFormat:@"Could not launch helper: %s", strerror(err)];
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

static void runInBackground(NSArray<NSString *> *args, void (^completion)(NSString *error)) {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSString *error = runHelper(args);
		dispatch_async(dispatch_get_main_queue(), ^{
			if (completion) completion(error);
		});
	});
}

+ (void)setEnabled:(BOOL)enabled forTweak:(NSString *)name completion:(void (^)(NSString *))completion {
	runInBackground(@[enabled ? @"enable" : @"disable", name], ^(NSString *error) {
		if (!error) {
			NSMutableSet *pending = pendingNames();
			if ([pending containsObject:name]) [pending removeObject:name];
			else [pending addObject:name];
		}
		if (completion) completion(error);
	});
}

+ (void)respring:(void (^)(NSString *))completion {
	runInBackground(@[@"respring"], completion);
}

+ (void)restartInjection:(void (^)(NSString *))completion {
	runInBackground(@[@"userspace"], completion);
}

@end
