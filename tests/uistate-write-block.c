// Test-only ui.json write barrier: hold the owned tmp publication inside its first write.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Fixed wait so a driver that never releases cannot hang the child forever.
#define RELEASE_WAIT_MS 15000
// Short prefix keeps the temp nonempty and incomplete for the killed proof.
#define PREFIX_LEN 16

static atomic_int held = 0;

// Sample input: /proc/self/fd/7 reads /run/.../flea/ui.json.12345.tmp for the owned child.
static int target_matches(const char *target, pid_t self) {
    char expect[64];
    snprintf(expect, sizeof expect, "ui.json.%d.tmp", (int)self);
    size_t tl = strlen(target);
    size_t el = strlen(expect);
    if (tl >= el && strcmp(target + tl - el, expect) == 0)
        return 1;
    // Explicit mutation mode only: the truncated ui.json itself, never a backup.
    const char *allow = getenv("FLEA_TEST_UIS_ALLOW_DIRECT");
    if (allow && strcmp(allow, "1") == 0) {
        if (tl >= 8 && strcmp(target + tl - 8, "/ui.json") == 0)
            return 1;
    }
    return 0;
}

static void publish_entered(int fd, const char *target) {
    const char *path = getenv("FLEA_TEST_UIS_ENTERED");
    if (!path || !path[0])
        return;
    // Atomic publish: existence means ready, so complete bytes must land via rename.
    char sib[PATH_MAX + 64];
    int sl = snprintf(sib, sizeof sib, "%s.%d.part", path, (int)getpid());
    if (sl <= 0 || sl >= (int)sizeof sib)
        return;
    int out = open(sib, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (out < 0)
        return;
    char line[PATH_MAX + 64];
    int len = snprintf(line, sizeof line, "%d %d %s\n", (int)getpid(), fd, target);
    ssize_t (*real_write)(int, const void *, size_t) = dlsym(RTLD_NEXT, "write");
    int ok = 0;
    // A truncated line is a malformed receipt, so length inside the buffer is checked first.
    if (len > 0 && len < (int)sizeof line && real_write && real_write(out, line, (size_t)len) == len)
        ok = 1;
    if (close(out) != 0)
        ok = 0;
    if (ok) {
        if (rename(sib, path) != 0) {
            int e = errno;
            unlink(sib);
            // The driver fails closed on the missing receipt; this names the publication failure.
            char msg[PATH_MAX + 128];
            int ml = snprintf(msg, sizeof msg, "flea-test: receipt publish %s failed (%s)\n", path, strerror(e));
            if (ml > 0 && real_write) {
                if (ml >= (int)sizeof msg)
                    ml = (int)sizeof msg - 1;
                real_write(STDERR_FILENO, msg, (size_t)ml);
            }
        }
    } else {
        unlink(sib);
    }
}

static void wait_for_release(void) {
    const char *path = getenv("FLEA_TEST_UIS_RELEASE");
    if (!path || !path[0])
        return;
    // Poll for the release file; the driver SIGKILLs first in the killed proof.
    for (int i = 0; i < RELEASE_WAIT_MS; i++) {
        if (access(path, F_OK) == 0)
            return;
        usleep(1000);
    }
}

ssize_t write(int fd, const void *buf, size_t count) {
    ssize_t (*real_write)(int, const void *, size_t) = dlsym(RTLD_NEXT, "write");
    const char *entered = getenv("FLEA_TEST_UIS_ENTERED");
    const char *release = getenv("FLEA_TEST_UIS_RELEASE");
    if (real_write && entered && entered[0] && release && release[0] && atomic_load(&held) == 0) {
        char link[64];
        char target[PATH_MAX + 1];
        snprintf(link, sizeof link, "/proc/self/fd/%d", fd);
        ssize_t n = readlink(link, target, sizeof target - 1);
        if (n > 0) {
            target[n] = '\0';
            if (target_matches(target, getpid())) {
                if (atomic_exchange(&held, 1) == 0) {
                    // Forward only the prefix so the temp stays nonempty and incomplete.
                    size_t prefix = count > PREFIX_LEN ? PREFIX_LEN : (count > 1 ? 1 : count);
                    ssize_t w = real_write(fd, buf, prefix);
                    publish_entered(fd, target);
                    wait_for_release();
                    return w;
                }
            }
        }
    }
    return real_write(fd, buf, count);
}
