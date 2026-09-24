#include <errno.h>
#include <mach-o/dyld.h>
#include <limits.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#if !defined(TP_ROOTLESS) && __has_include(<roothide.h>)
#include <roothide.h>
#else
static const char *jbroot(const char *path) {
	static char buf[PATH_MAX];
	snprintf(buf, sizeof(buf), "/var/jb%s", path);
	return buf;
}
#endif

#define MOBILE_UID 501
#define SELF_NAME "Tweakpilot"

extern char **environ;

static void root_path(const char *path, char *out, size_t size) {
	static const char suffix[] = "/usr/libexec/tweakpilot/tpctl";
	char exe[PATH_MAX], real[PATH_MAX];
	uint32_t len = sizeof(exe);
	if (_NSGetExecutablePath(exe, &len) == 0 && realpath(exe, real)) {
		size_t n = strlen(real), m = sizeof(suffix) - 1;
		if (n > m && strcmp(real + n - m, suffix) == 0) {
			real[n - m] = 0;
			snprintf(out, size, "%s%s", real, path);
			return;
		}
	}
	snprintf(out, size, "%s", jbroot(path));
}

static int usage(void) {
	fprintf(stderr, "usage: tpctl enable|disable <tweak> | respring | userspace\n");
	return 64;
}

static int valid_name(const char *name) {
	size_t len = strlen(name);
	if (len == 0 || len > 128 || name[0] == '.' || strstr(name, "..")) return 0;
	for (size_t i = 0; i < len; i++) {
		unsigned char c = (unsigned char)name[i];
		if (c < 0x20 || c == 0x7f || c == '/') return 0;
	}
	return 1;
}

static int is_regular_file(const char *path) {
	struct stat st;
	return lstat(path, &st) == 0 && S_ISREG(st.st_mode);
}

static int run(const char *path, char *const argv[]) {
	pid_t pid;
	int err = posix_spawn(&pid, path, NULL, NULL, argv, environ);
	if (err != 0) {
		fprintf(stderr, "tpctl: spawn %s failed: %s\n", path, strerror(err));
		return 1;
	}
	int status = 0;
	waitpid(pid, &status, 0);
	return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}

static int toggle(const char *name, int enable) {
	if (!valid_name(name)) {
		fprintf(stderr, "tpctl: invalid tweak name\n");
		return 65;
	}
	if (strcmp(name, SELF_NAME) == 0) {
		fprintf(stderr, "tpctl: refusing to toggle Tweakpilot itself\n");
		return 65;
	}

	char dir[PATH_MAX], on[PATH_MAX], off[PATH_MAX];
	root_path("/Library/MobileSubstrate/DynamicLibraries", dir, sizeof(dir));
	snprintf(on, sizeof(on), "%s/%s.dylib", dir, name);
	snprintf(off, sizeof(off), "%s/%s.dylib.disabled", dir, name);

	const char *from = enable ? off : on;
	const char *to = enable ? on : off;

	if (!is_regular_file(from)) {
		if (is_regular_file(to)) return 0;
		fprintf(stderr, "tpctl: %s not found\n", from);
		return 66;
	}
	if (rename(from, to) != 0) {
		fprintf(stderr, "tpctl: rename failed: %s\n", strerror(errno));
		return 73;
	}
	return 0;
}

int main(int argc, char *argv[]) {
	uid_t caller = getuid();
	if (caller != 0 && caller != MOBILE_UID) {
		fprintf(stderr, "tpctl: caller not allowed\n");
		return 77;
	}
	if (setgid(0) != 0 || setuid(0) != 0) {
		fprintf(stderr, "tpctl: not installed setuid root\n");
		return 77;
	}
	if (argc < 2) return usage();

	const char *cmd = argv[1];
	if ((strcmp(cmd, "enable") == 0 || strcmp(cmd, "disable") == 0) && argc == 3) {
		return toggle(argv[2], strcmp(cmd, "enable") == 0);
	}
	if (strcmp(cmd, "respring") == 0 && argc == 2) {
		char path[PATH_MAX];
		root_path("/usr/bin/killall", path, sizeof(path));
		char *const args[] = {"killall", "-9", "backboardd", NULL};
		return run(path, args);
	}
	if (strcmp(cmd, "userspace") == 0 && argc == 2) {
		char path[PATH_MAX];
		root_path("/usr/bin/launchctl", path, sizeof(path));
		char *const args[] = {"launchctl", "reboot", "userspace", NULL};
		return run(path, args);
	}
	return usage();
}
