// SPDX-License-Identifier: GPL-3.0-only
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define TXID "00000000-0000-4000-8000-000000000001"
#define MAX_INPUT (128U * 1024U)

struct roots {
    int runtime;
    int settings;
    int presets;
    int niri;
};

static void fail(const char *message) {
    fprintf(stderr, "sleepy-journal-fs: %s: %s\n", message, strerror(errno));
    exit(2);
}

static int open_dir_at(int parent, const char *name) {
    int fd = openat(parent, name,
        O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) fail(name);
    return fd;
}

static void validate_regular_fd(int fd, const char *label) {
    struct stat st;
    if (fstat(fd, &st) < 0) fail(label);
    if (!S_ISREG(st.st_mode) || st.st_uid != geteuid() || st.st_nlink != 1) {
        errno = EPERM;
        fail(label);
    }
}

static int open_regular_at(int parent, const char *name) {
    int fd = openat(parent, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) fail(name);
    validate_regular_fd(fd, name);
    return fd;
}

static bool entry_absent(int parent, const char *name) {
    struct stat st;
    if (fstatat(parent, name, &st, AT_SYMLINK_NOFOLLOW) == 0) return false;
    if (errno == ENOENT) return true;
    fail(name);
    return false;
}

static void require_absent(int parent, const char *name) {
    if (!entry_absent(parent, name)) {
        errno = EEXIST;
        fail(name);
    }
}

static void require_regular_entry(int parent, const char *name) {
    int fd = open_regular_at(parent, name);
    close(fd);
}

static struct roots open_roots(const char *path) {
    struct roots result = {-1, -1, -1, -1};
    result.runtime = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (result.runtime < 0) fail("runtime root");
    int config = open_dir_at(result.runtime, "config");
    int state = open_dir_at(result.runtime, "state");
    result.settings = open_dir_at(config, "sleepy");
    result.niri = open_dir_at(config, "niri");
    result.presets = open_dir_at(state, "sleepy");
    close(config);
    close(state);
    return result;
}

static void close_roots(struct roots *roots) {
    close(roots->settings);
    close(roots->presets);
    close(roots->niri);
    close(roots->runtime);
}

static void write_all(int fd, const uint8_t *bytes, size_t length) {
    size_t written = 0;
    while (written < length) {
        ssize_t count = write(fd, bytes + written, length - written);
        if (count < 0) fail("write");
        written += (size_t)count;
    }
}

static uint8_t *read_stdin(size_t *length) {
    uint8_t *buffer = malloc(MAX_INPUT + 1U);
    if (buffer == NULL) fail("allocate input");
    size_t used = 0;
    while (used <= MAX_INPUT) {
        ssize_t count = read(STDIN_FILENO, buffer + used, MAX_INPUT + 1U - used);
        if (count < 0) fail("read input");
        if (count == 0) break;
        used += (size_t)count;
    }
    if (used == 0 || used > MAX_INPUT) {
        errno = EFBIG;
        fail("invalid input size");
    }
    *length = used;
    return buffer;
}

struct tracked_output {
    int parent;
    int fd;
    char name[256];
    dev_t device;
    ino_t inode;
};

static bool open_tracked_output(struct tracked_output *output, int parent,
    const char *name) {
    output->parent = parent;
    output->fd = -1;
    int count = snprintf(output->name, sizeof(output->name), "%s", name);
    if (count < 0 || (size_t)count >= sizeof(output->name)) {
        errno = ENAMETOOLONG;
        return false;
    }
    if (!entry_absent(parent, name)) {
        errno = EEXIST;
        return false;
    }
    output->fd = openat(parent, name,
        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (output->fd < 0) return false;
    struct stat st;
    if (fstat(output->fd, &st) < 0) {
        int saved_errno = errno;
        (void)unlinkat(parent, name, 0);
        close(output->fd);
        output->fd = -1;
        errno = saved_errno;
        return false;
    }
    output->device = st.st_dev;
    output->inode = st.st_ino;
    return true;
}

static bool tracked_output_matches(const struct tracked_output *output) {
    struct stat st;
    if (fstatat(output->parent, output->name, &st, AT_SYMLINK_NOFOLLOW) < 0)
        return false;
    return S_ISREG(st.st_mode) && st.st_uid == geteuid() && st.st_nlink == 1 &&
        st.st_dev == output->device && st.st_ino == output->inode;
}

static void cleanup_tracked_outputs(struct tracked_output *outputs, size_t count) {
    for (size_t index = 0; index < count; index++) {
        if (outputs[index].fd >= 0 && tracked_output_matches(&outputs[index]))
            (void)unlinkat(outputs[index].parent, outputs[index].name, 0);
        if (outputs[index].fd >= 0) close(outputs[index].fd);
    }
    for (size_t index = 0; index < count; index++)
        (void)fsync(outputs[index].parent);
}

static bool fill_tracked_output(struct tracked_output *output, int parent,
    const char *source) {
    int input = openat(parent, source,
        O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (input < 0) return false;
    struct stat source_stat;
    if (fstat(input, &source_stat) < 0 || !S_ISREG(source_stat.st_mode) ||
        source_stat.st_uid != geteuid() || source_stat.st_nlink != 1) {
        close(input);
        errno = EPERM;
        return false;
    }
    uint8_t buffer[16384];
    for (;;) {
        ssize_t count = read(input, buffer, sizeof(buffer));
        if (count < 0) {
            close(input);
            return false;
        }
        if (count == 0) break;
        size_t written = 0;
        while (written < (size_t)count) {
            ssize_t result = write(output->fd, buffer + written,
                (size_t)count - written);
            if (result < 0) {
                close(input);
                return false;
            }
            written += (size_t)result;
        }
    }
    close(input);
    return fsync(output->fd) == 0 && tracked_output_matches(output);
}

static void atomic_replace(int parent, const char *destination,
    const char *temporary, const uint8_t *bytes, size_t length) {
    require_absent(parent, temporary);
    require_regular_entry(parent, destination);
    int output = openat(parent, temporary,
        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (output < 0) fail(temporary);
    write_all(output, bytes, length);
    if (fsync(output) < 0) fail(temporary);
    close(output);
    if (renameat(parent, temporary, parent, destination) < 0) fail("rename journal");
    if (fsync(parent) < 0) fail("sync journal directory");
}

struct artifact {
    int *directory;
    const char *name;
};

static void sidecar_name(char *output, size_t size, const char *name,
    const char *variant, bool production) {
    int count = production
        ? snprintf(output, size, ".%s.%s.%s", name, TXID, variant)
        : snprintf(output, size, "%s.sleepy-transaction.%s", name, variant);
    if (count < 0 || (size_t)count >= size) {
        errno = ENAMETOOLONG;
        fail("sidecar name");
    }
}

static void prepare(struct roots *roots) {
    size_t length;
    uint8_t *journal = read_stdin(&length);
    struct artifact artifacts[] = {
        {&roots->settings, "settings.json"},
        {&roots->presets, "presets.json"},
        {&roots->niri, "sleepy-user-bindings.kdl"},
    };
    char source[256], destination[256];
    struct tracked_output outputs[7];
    for (size_t index = 0; index < 7; index++) outputs[index].fd = -1;
    size_t created = 0;

    require_regular_entry(roots->presets, "bindings-transaction.json");
    require_absent(roots->presets, ".bindings-transaction.runner.prepare.tmp");
    for (size_t index = 0; index < 3; index++) {
        for (size_t variant = 0; variant < 2; variant++) {
            const char *label = variant == 0 ? "old" : "new";
            sidecar_name(source, sizeof(source), artifacts[index].name, label, false);
            require_regular_entry(*artifacts[index].directory, source);
            sidecar_name(destination, sizeof(destination), artifacts[index].name, label, true);
            require_absent(*artifacts[index].directory, destination);
        }
    }

    for (size_t index = 0; index < 3; index++) {
        for (size_t variant = 0; variant < 2; variant++) {
            const char *label = variant == 0 ? "old" : "new";
            sidecar_name(source, sizeof(source), artifacts[index].name, label, false);
            sidecar_name(destination, sizeof(destination), artifacts[index].name, label, true);
            created++;
            if (!open_tracked_output(&outputs[created - 1],
                    *artifacts[index].directory, destination)) {
                int saved_errno = errno;
                cleanup_tracked_outputs(outputs, created);
                free(journal);
                errno = saved_errno;
                fail("create production sidecar");
            }
            if (!fill_tracked_output(&outputs[created - 1],
                    *artifacts[index].directory, source)) {
                int saved_errno = errno;
                cleanup_tracked_outputs(outputs, created);
                free(journal);
                errno = saved_errno;
                fail("copy production sidecar");
            }
        }
    }

    created++;
    if (!open_tracked_output(&outputs[created - 1], roots->presets,
            ".bindings-transaction.runner.prepare.tmp")) {
        int saved_errno = errno;
        cleanup_tracked_outputs(outputs, created);
        free(journal);
        errno = saved_errno;
        fail("create journal staging");
    }
    size_t journal_written = 0;
    while (journal_written < length) {
        ssize_t count = write(outputs[created - 1].fd,
            journal + journal_written, length - journal_written);
        if (count < 0) break;
        journal_written += (size_t)count;
    }
    if (journal_written != length || fsync(outputs[created - 1].fd) < 0 ||
        !tracked_output_matches(&outputs[created - 1])) {
        int saved_errno = errno;
        cleanup_tracked_outputs(outputs, created);
        free(journal);
        errno = saved_errno;
        fail("prepare journal staging");
    }
    for (size_t index = 0; index < created; index++) {
        if (!tracked_output_matches(&outputs[index])) {
            cleanup_tracked_outputs(outputs, created);
            free(journal);
            errno = ESTALE;
            fail("prepared path identity changed");
        }
    }
    if (renameat(roots->presets, outputs[created - 1].name,
            roots->presets, "bindings-transaction.json") < 0) {
        int saved_errno = errno;
        cleanup_tracked_outputs(outputs, created);
        free(journal);
        errno = saved_errno;
        fail("rename journal");
    }
    for (size_t index = 0; index < created; index++) close(outputs[index].fd);
    if (fsync(roots->presets) < 0) fail("sync journal directory");
    free(journal);
}

static void replace_journal(struct roots *roots) {
    size_t length;
    uint8_t *journal = read_stdin(&length);
    atomic_replace(roots->presets, "bindings-transaction.json",
        ".bindings-transaction.runner.confirm.tmp", journal, length);
    free(journal);
}

static void consume(struct roots *roots, const char *phase) {
    int fd = open_regular_at(roots->runtime, "fault.must-consume");
    char bytes[128];
    ssize_t length = read(fd, bytes, sizeof(bytes));
    if (length < 0) fail("read canary");
    close(fd);
    size_t phase_length = strlen(phase);
    if (!((size_t)length == phase_length || (size_t)length == phase_length + 1U) ||
        memcmp(bytes, phase, phase_length) != 0 ||
        ((size_t)length == phase_length + 1U && bytes[phase_length] != '\n')) {
        errno = EINVAL;
        fail("canary content");
    }
    if (unlinkat(roots->runtime, "fault.must-consume", 0) < 0) fail("consume canary");
    if (fsync(roots->runtime) < 0) fail("sync runtime root");
}

static void cleanup(struct roots *roots) {
    require_absent(roots->presets, "bindings-transaction.json");
    struct artifact artifacts[] = {
        {&roots->settings, "settings.json"},
        {&roots->presets, "presets.json"},
        {&roots->niri, "sleepy-user-bindings.kdl"},
    };
    char fixture[256], production[256];
    for (size_t index = 0; index < 3; index++) {
        for (size_t variant = 0; variant < 2; variant++) {
            const char *label = variant == 0 ? "old" : "new";
            sidecar_name(production, sizeof(production), artifacts[index].name, label, true);
            require_absent(*artifacts[index].directory, production);
            sidecar_name(fixture, sizeof(fixture), artifacts[index].name, label, false);
            require_regular_entry(*artifacts[index].directory, fixture);
        }
    }
    for (size_t index = 0; index < 3; index++) {
        for (size_t variant = 0; variant < 2; variant++) {
            sidecar_name(fixture, sizeof(fixture), artifacts[index].name,
                variant == 0 ? "old" : "new", false);
            if (unlinkat(*artifacts[index].directory, fixture, 0) < 0) fail(fixture);
        }
        if (fsync(*artifacts[index].directory) < 0) fail("sync artifact directory");
    }
}

int main(int argc, char **argv) {
    if (argc < 3 || argc > 4) {
        errno = EINVAL;
        fail("usage: MODE RUNTIME [PHASE]");
    }
    struct roots roots = open_roots(argv[2]);
    if (strcmp(argv[1], "prepare") == 0 && argc == 3) prepare(&roots);
    else if (strcmp(argv[1], "replace-journal") == 0 && argc == 3) replace_journal(&roots);
    else if (strcmp(argv[1], "consume") == 0 && argc == 4) consume(&roots, argv[3]);
    else if (strcmp(argv[1], "cleanup") == 0 && argc == 3) cleanup(&roots);
    else {
        errno = EINVAL;
        fail("invalid operation");
    }
    close_roots(&roots);
    return 0;
}
