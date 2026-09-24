#include <dirent.h>
#include <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <notify.h>
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
#define REQUEST_PREFIX "com.xsxs18.tweakpilot.request."
#define RESPONSE_PREFIX "com.xsxs18.tweakpilot.response."

enum {
	ACTION_ENABLE = 1,
	ACTION_DISABLE = 2,
	ACTION_RESPRING = 3,
	ACTION_USERSPACE = 4,
};

extern char **environ;

static int last_errno;

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

static void resolve(const char *path, char *out, size_t size) {
	char candidates[3][PATH_MAX];
	root_path(path, candidates[0], PATH_MAX);
	snprintf(candidates[1], PATH_MAX, "%s", jbroot(path));
	snprintf(candidates[2], PATH_MAX, "%s", path);

	struct stat st;
	for (int i = 0; i < 3; i++) {
		if (stat(candidates[i], &st) == 0) {
			snprintf(out, size, "%s", candidates[i]);
			return;
		}
	}
	snprintf(out, size, "%s", candidates[0]);
}

static int usage(void) {
	fprintf(stderr, "usage: tpctl enable|disable <tweak> | respring | userspace | daemon\n");
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

static uint64_t name_hash(const char *name) {
	uint64_t hash = 1469598103934665603ULL;
	for (const unsigned char *p = (const unsigned char *)name; *p; p++) {
		hash ^= *p;
		hash *= 1099511628211ULL;
	}
	return hash & 0xFFFFFFFFFFFFULL;
}

static int run(const char *path, char *const argv[]) {
	pid_t pid;
	int err = posix_spawn(&pid, path, NULL, NULL, argv, environ);
	if (err != 0) {
		fprintf(stderr, "tpctl: spawn %s failed: %s\n", path, strerror(err));
		last_errno = err;
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
	resolve("/Library/MobileSubstrate/DynamicLibraries", dir, sizeof(dir));
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
		last_errno = errno;
		fprintf(stderr, "tpctl: rename failed: %s\n", strerror(errno));
		return 73;
	}
	return 0;
}

static int respring(void) {
	char path[PATH_MAX];
	resolve("/usr/bin/killall", path, sizeof(path));
	char *const args[] = {"killall", "-9", "backboardd", NULL};
	return run(path, args);
}

static int userspace_reboot(void) {
	char path[PATH_MAX];
	resolve("/usr/bin/launchctl", path, sizeof(path));
	char *const args[] = {"launchctl", "reboot", "userspace", NULL};
	return run(path, args);
}

static int find_tweak(uint64_t hash, char *name, size_t size) {
	char dir[PATH_MAX];
	resolve("/Library/MobileSubstrate/DynamicLibraries", dir, sizeof(dir));
	DIR *d = opendir(dir);
	if (!d) return 0;

	static const char disabled[] = ".dylib.disabled";
	static const char enabled[] = ".dylib";
	int found = 0;
	struct dirent *entry;
	while ((entry = readdir(d))) {
		char base[NAME_MAX + 1];
		snprintf(base, sizeof(base), "%s", entry->d_name);
		size_t n = strlen(base);
		if (n > sizeof(disabled) - 1 && strcmp(base + n - (sizeof(disabled) - 1), disabled) == 0) {
			base[n - (sizeof(disabled) - 1)] = 0;
		} else if (n > sizeof(enabled) - 1 && strcmp(base + n - (sizeof(enabled) - 1), enabled) == 0) {
			base[n - (sizeof(enabled) - 1)] = 0;
		} else {
			continue;
		}
		if (name_hash(base) == hash) {
			snprintf(name, size, "%s", base);
			found = 1;
			break;
		}
	}
	closedir(d);
	return found;
}

static int read_token(const char *path, char *token, size_t size) {
	int fd = open(path, O_RDONLY | O_NOFOLLOW);
	if (fd < 0) return 0;
	ssize_t n = read(fd, token, size - 1);
	close(fd);
	if (n < 32) return 0;
	token[32] = 0;
	for (int i = 0; i < 32; i++) {
		char c = token[i];
		if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return 0;
	}
	return 1;
}

static int load_token(char *token, size_t size) {
	char candidates[3][PATH_MAX];
	root_path("/usr/libexec/tweakpilot/token", candidates[0], PATH_MAX);
	snprintf(candidates[1], PATH_MAX, "%s", jbroot("/usr/libexec/tweakpilot/token"));
	snprintf(candidates[2], PATH_MAX, "%s", "/usr/libexec/tweakpilot/token");

	for (int i = 0; i < 3; i++) {
		if (read_token(candidates[i], token, size)) return 1;
		fprintf(stderr, "tpctl: can't read %s: %s\n", candidates[i], strerror(errno));
	}

	uint8_t raw[16];
	arc4random_buf(raw, sizeof(raw));
	for (size_t i = 0; i < sizeof(raw); i++) snprintf(token + i * 2, 3, "%02x", raw[i]);

	for (int i = 0; i < 3; i++) {
		int fd = open(candidates[i], O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0644);
		if (fd < 0) {
			fprintf(stderr, "tpctl: can't create %s: %s\n", candidates[i], strerror(errno));
			continue;
		}
		fchmod(fd, 0644);
		ssize_t written = write(fd, token, 32);
		close(fd);
		if (written == 32) return 1;
		fprintf(stderr, "tpctl: can't write %s: %s\n", candidates[i], strerror(errno));
	}
	return 0;
}

static int response_token;
static char response_name[128];

static void handle_request(int t) {
	uint64_t value = 0;
	notify_get_state(t, &value);
	uint64_t hash = value & 0xFFFFFFFFFFFFULL;
	uint64_t seq = (value >> 48) & 0xFF;
	int action = (int)((value >> 56) & 0xF);

	last_errno = 0;
	int code = 64;
	if (action == ACTION_ENABLE || action == ACTION_DISABLE) {
		char name[NAME_MAX + 1];
		code = find_tweak(hash, name, sizeof(name)) ? toggle(name, action == ACTION_ENABLE) : 66;
	} else if (action == ACTION_RESPRING || action == ACTION_USERSPACE) {
		code = 0;
	}

	uint64_t reply = seq | ((uint64_t)(code & 0xFF) << 8) | ((uint64_t)(last_errno & 0xFFFF) << 16);
	notify_set_state(response_token, reply);
	notify_post(response_name);

	if (action == ACTION_RESPRING) respring();
	if (action == ACTION_USERSPACE) userspace_reboot();
}

static int run_daemon(void) {
	char token[33] = {0};
	if (!load_token(token, sizeof(token))) {
		fprintf(stderr, "tpctl: no usable token, giving up\n");
		return 1;
	}
	fprintf(stderr, "tpctl: service running\n");

	char request[128];
	snprintf(request, sizeof(request), REQUEST_PREFIX "%s", token);
	snprintf(response_name, sizeof(response_name), RESPONSE_PREFIX "%s", token);
	notify_register_check(response_name, &response_token);

	int request_token;
	notify_register_dispatch(request, &request_token, dispatch_get_main_queue(), ^(int t) {
		handle_request(t);
	});

	dispatch_main();
}

int main(int argc, char *argv[]) {
	if (argc == 2 && strcmp(argv[1], "daemon") == 0) {
		if (getuid() != 0) {
			fprintf(stderr, "tpctl: daemon must run as root\n");
			return 77;
		}
		return run_daemon();
	}

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
	if (strcmp(cmd, "respring") == 0 && argc == 2) return respring();
	if (strcmp(cmd, "userspace") == 0 && argc == 2) return userspace_reboot();
	return usage();
}
