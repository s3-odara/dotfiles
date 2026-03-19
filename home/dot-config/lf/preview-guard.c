#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <linux/landlock.h>
#include <seccomp.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef SYS_landlock_create_ruleset
#error "Landlock syscalls are not available on this architecture"
#endif

static int ll_create_ruleset(const struct landlock_ruleset_attr *attr, size_t size,
                             __u32 flags)
{
    return syscall(SYS_landlock_create_ruleset, attr, size, flags);
}

static int ll_add_rule(int ruleset_fd, enum landlock_rule_type rule_type,
                       const void *rule_attr, __u32 flags)
{
    return syscall(SYS_landlock_add_rule, ruleset_fd, rule_type, rule_attr, flags);
}

static int ll_restrict_self(int ruleset_fd, __u32 flags)
{
    return syscall(SYS_landlock_restrict_self, ruleset_fd, flags);
}

static uint64_t handled_fs_access(int abi)
{
    uint64_t access = LANDLOCK_ACCESS_FS_EXECUTE |
                      LANDLOCK_ACCESS_FS_WRITE_FILE |
                      LANDLOCK_ACCESS_FS_READ_FILE |
                      LANDLOCK_ACCESS_FS_READ_DIR |
                      LANDLOCK_ACCESS_FS_REMOVE_DIR |
                      LANDLOCK_ACCESS_FS_REMOVE_FILE |
                      LANDLOCK_ACCESS_FS_MAKE_CHAR |
                      LANDLOCK_ACCESS_FS_MAKE_DIR |
                      LANDLOCK_ACCESS_FS_MAKE_REG |
                      LANDLOCK_ACCESS_FS_MAKE_SOCK |
                      LANDLOCK_ACCESS_FS_MAKE_FIFO |
                      LANDLOCK_ACCESS_FS_MAKE_BLOCK |
                      LANDLOCK_ACCESS_FS_MAKE_SYM |
                      LANDLOCK_ACCESS_FS_REFER;

    if (abi >= 3) {
        access |= LANDLOCK_ACCESS_FS_TRUNCATE;
    }

    if (abi >= 5) {
        access |= LANDLOCK_ACCESS_FS_IOCTL_DEV;
    }

    return access;
}

static uint64_t ro_access(void)
{
    return LANDLOCK_ACCESS_FS_EXECUTE |
           LANDLOCK_ACCESS_FS_READ_FILE |
           LANDLOCK_ACCESS_FS_READ_DIR;
}

static uint64_t dev_null_access(int abi)
{
    uint64_t access = LANDLOCK_ACCESS_FS_READ_FILE |
                      LANDLOCK_ACCESS_FS_WRITE_FILE;

    if (abi >= 5) {
        access |= LANDLOCK_ACCESS_FS_IOCTL_DEV;
    }

    return access;
}

static uint64_t tmp_access(int abi)
{
    uint64_t access = LANDLOCK_ACCESS_FS_READ_FILE |
                      LANDLOCK_ACCESS_FS_READ_DIR |
                      LANDLOCK_ACCESS_FS_WRITE_FILE |
                      LANDLOCK_ACCESS_FS_REMOVE_FILE |
                      LANDLOCK_ACCESS_FS_MAKE_REG;

    if (abi >= 3) {
        access |= LANDLOCK_ACCESS_FS_TRUNCATE;
    }

    return access;
}

static bool path_exists(const char *path)
{
    return access(path, F_OK) == 0;
}

typedef void (*ro_path_visitor)(const char *path, void *userdata);

static void visit_extra_ro_paths(ro_path_visitor visitor, void *userdata)
{
    const char *extra_paths = getenv("PREVIEW_EXTRA_RO_PATHS");
    char *cursor;
    char *path;
    char *paths_copy;

    if (extra_paths == NULL || extra_paths[0] == '\0') {
        return;
    }

    paths_copy = strdup(extra_paths);
    if (paths_copy == NULL) {
        fprintf(stderr, "preview-guard: strdup failed\n");
        exit(1);
    }

    cursor = paths_copy;
    while ((path = strsep(&cursor, ":")) != NULL) {
        if (path[0] == '\0') {
            continue;
        }

        if (path_exists(path)) {
            visitor(path, userdata);
        }
    }

    free(paths_copy);
}

static void visit_ro_paths(const char *target_dir, const char *lf_config_dir,
                           ro_path_visitor visitor, void *userdata)
{
    static const char *const base_paths[] = {
        "/bin",
        "/usr",
        "/lib",
        "/lib64",
        "/etc",
    };

    size_t i;
    for (i = 0; i < sizeof(base_paths) / sizeof(base_paths[0]); i++) {
        if (path_exists(base_paths[i])) {
            visitor(base_paths[i], userdata);
        }
    }

    if (path_exists(lf_config_dir)) {
        visitor(lf_config_dir, userdata);
    }

    if (path_exists(target_dir)) {
        visitor(target_dir, userdata);
    }

    visit_extra_ro_paths(visitor, userdata);
}

static int add_path_rule(int ruleset_fd, const char *path, uint64_t access)
{
    int fd = open(path, O_PATH | O_CLOEXEC);
    if (fd < 0) {
        return -1;
    }

    struct landlock_path_beneath_attr attr = {
        .allowed_access = access,
        .parent_fd = fd,
    };

    int rc = ll_add_rule(ruleset_fd, LANDLOCK_RULE_PATH_BENEATH, &attr, 0);
    int saved_errno = errno;
    close(fd);
    errno = saved_errno;
    return rc;
}

static void add_ro_rule_if_exists(int ruleset_fd, const char *path)
{
    if (!path_exists(path)) {
        return;
    }

    if (add_path_rule(ruleset_fd, path, ro_access()) != 0) {
        fprintf(stderr, "preview-guard: landlock rule failed for %s: %s\n",
                path, strerror(errno));
        exit(1);
    }
}

static void add_ro_rule_visitor(const char *path, void *userdata)
{
    int ruleset_fd = *(int *)userdata;
    add_ro_rule_if_exists(ruleset_fd, path);
}

static void print_ro_path_visitor(const char *path, void *userdata)
{
    (void)userdata;
    puts(path);
}

static void install_landlock(const char *target_dir, const char *lf_config_dir)
{
    int abi = ll_create_ruleset(NULL, 0, LANDLOCK_CREATE_RULESET_VERSION);
    if (abi < 1) {
        if (errno == ENOSYS || errno == EOPNOTSUPP) {
            return;
        }

        fprintf(stderr, "preview-guard: landlock ABI query failed: %s\n",
                strerror(errno));
        exit(1);
    }

    struct landlock_ruleset_attr ruleset = {
        .handled_access_fs = handled_fs_access(abi),
    };

    if (abi >= 4) {
        ruleset.handled_access_net = LANDLOCK_ACCESS_NET_BIND_TCP |
                                     LANDLOCK_ACCESS_NET_CONNECT_TCP;
    }

    int ruleset_fd = ll_create_ruleset(&ruleset, sizeof(ruleset), 0);
    if (ruleset_fd < 0) {
        fprintf(stderr, "preview-guard: landlock ruleset failed: %s\n",
                strerror(errno));
        exit(1);
    }

    visit_ro_paths(target_dir, lf_config_dir, add_ro_rule_visitor, &ruleset_fd);

    if (path_exists("/dev/null") &&
        add_path_rule(ruleset_fd, "/dev/null", dev_null_access(abi)) != 0) {
        fprintf(stderr, "preview-guard: /dev/null rule failed: %s\n",
                strerror(errno));
        exit(1);
    }

    if (path_exists("/var/tmp") &&
        add_path_rule(ruleset_fd, "/var/tmp", tmp_access(abi)) != 0) {
        fprintf(stderr, "preview-guard: /var/tmp rule failed: %s\n",
                strerror(errno));
        exit(1);
    }

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) {
        fprintf(stderr, "preview-guard: PR_SET_NO_NEW_PRIVS failed: %s\n",
                strerror(errno));
        exit(1);
    }

    if (ll_restrict_self(ruleset_fd, 0) != 0) {
        fprintf(stderr, "preview-guard: landlock_restrict_self failed: %s\n",
                strerror(errno));
        exit(1);
    }

    close(ruleset_fd);
}

static void add_errno_rule(scmp_filter_ctx ctx, int syscall_nr)
{
    if (seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), syscall_nr, 0) < 0) {
        fprintf(stderr, "preview-guard: seccomp rule failed for syscall %d\n",
                syscall_nr);
        exit(1);
    }
}

static void install_seccomp(void)
{
    scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_ALLOW);
    if (ctx == NULL) {
        fprintf(stderr, "preview-guard: seccomp_init failed\n");
        exit(1);
    }

    add_errno_rule(ctx, SCMP_SYS(socket));
    add_errno_rule(ctx, SCMP_SYS(socketpair));
    add_errno_rule(ctx, SCMP_SYS(connect));
    add_errno_rule(ctx, SCMP_SYS(bind));
    add_errno_rule(ctx, SCMP_SYS(listen));
    add_errno_rule(ctx, SCMP_SYS(accept));
    add_errno_rule(ctx, SCMP_SYS(accept4));
    add_errno_rule(ctx, SCMP_SYS(shutdown));
    add_errno_rule(ctx, SCMP_SYS(mount));
    add_errno_rule(ctx, SCMP_SYS(umount2));
    add_errno_rule(ctx, SCMP_SYS(pivot_root));
    add_errno_rule(ctx, SCMP_SYS(open_tree));
    add_errno_rule(ctx, SCMP_SYS(move_mount));
    add_errno_rule(ctx, SCMP_SYS(fsopen));
    add_errno_rule(ctx, SCMP_SYS(fsconfig));
    add_errno_rule(ctx, SCMP_SYS(fsmount));
    add_errno_rule(ctx, SCMP_SYS(fspick));
    add_errno_rule(ctx, SCMP_SYS(mount_setattr));
    add_errno_rule(ctx, SCMP_SYS(ptrace));
    add_errno_rule(ctx, SCMP_SYS(process_vm_readv));
    add_errno_rule(ctx, SCMP_SYS(process_vm_writev));
    add_errno_rule(ctx, SCMP_SYS(kcmp));
    add_errno_rule(ctx, SCMP_SYS(open_by_handle_at));
    add_errno_rule(ctx, SCMP_SYS(name_to_handle_at));
    add_errno_rule(ctx, SCMP_SYS(bpf));
    add_errno_rule(ctx, SCMP_SYS(perf_event_open));
    add_errno_rule(ctx, SCMP_SYS(userfaultfd));
    add_errno_rule(ctx, SCMP_SYS(init_module));
    add_errno_rule(ctx, SCMP_SYS(finit_module));
    add_errno_rule(ctx, SCMP_SYS(delete_module));
    add_errno_rule(ctx, SCMP_SYS(swapon));
    add_errno_rule(ctx, SCMP_SYS(swapoff));
    add_errno_rule(ctx, SCMP_SYS(reboot));
    add_errno_rule(ctx, SCMP_SYS(kexec_load));
    add_errno_rule(ctx, SCMP_SYS(kexec_file_load));
    add_errno_rule(ctx, SCMP_SYS(setns));
    add_errno_rule(ctx, SCMP_SYS(unshare));
    add_errno_rule(ctx, SCMP_SYS(keyctl));
    add_errno_rule(ctx, SCMP_SYS(add_key));
    add_errno_rule(ctx, SCMP_SYS(request_key));

    if (seccomp_load(ctx) < 0) {
        fprintf(stderr, "preview-guard: seccomp_load failed\n");
        seccomp_release(ctx);
        exit(1);
    }

    seccomp_release(ctx);
}

int main(int argc, char **argv)
{
    if (argc == 4 && strcmp(argv[1], "--print-bwrap-ro-paths") == 0) {
        visit_ro_paths(argv[2], argv[3], print_ro_path_visitor, NULL);
        return 0;
    }

    if (argc < 6) {
        fprintf(stderr,
                "usage: %s <target-dir> <lf-config-dir> <command> [args...]\n"
                "       %s --print-bwrap-ro-paths <target-dir> <lf-config-dir>\n",
                argv[0],
                argv[0]);
        return 1;
    }

    const char *target_dir = argv[1];
    const char *lf_config_dir = argv[2];
    char **cmd = &argv[3];

    install_landlock(target_dir, lf_config_dir);
    install_seccomp();

    execvp(cmd[0], cmd);
    fprintf(stderr, "preview-guard: execvp failed for %s: %s\n",
            cmd[0], strerror(errno));
    return 1;
}
