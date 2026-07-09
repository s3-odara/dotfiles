#define _GNU_SOURCE

#include "sandbox-guard-common.h"

#include <errno.h>
#include <linux/landlock.h>
#include <seccomp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <unistd.h>

/*
 * Preview guard policy summary:
 * - Profile: preview; CLI compatibility is part of the security contract.
 * - Read-only filesystem inputs: LF_SANDBOX_SYSTEM_RO_PATHS entries,
 *   lf_config_dir, regular-file target_path, and PREVIEW_EXTRA_RO_PATHS.
 * - Special access: minimal /dev nodes may be read/written/ioctl'd; /var/tmp
 *   allows limited temporary-file creation, writes, truncation, reads, and removal.
 * - Networking/socket policy: Landlock handles TCP bind/connect restrictions;
 *   seccomp denies socket, socketpair, connect, bind, listen, accept, accept4,
 *   and shutdown outright for this preview profile.
 * - Shared hardening: no-new-privs, then Landlock restriction, then seccomp,
 *   all installed before execvp of the requested command.
 */

static void visit_extra_ro_paths(guard_path_visitor visitor, void *userdata)
{
    guard_visit_colon_env_paths("preview-guard", "PREVIEW_EXTRA_RO_PATHS",
                                visitor, userdata);
}

static void visit_ro_paths(const char *target_path, const char *lf_config_dir,
                           guard_path_visitor visitor, void *userdata)
{
    guard_visit_system_ro_paths("preview-guard", visitor, userdata);

    if (guard_path_exists(lf_config_dir)) {
        visitor(lf_config_dir, userdata);
    }

    if (guard_path_is_regular(target_path)) {
        visitor(target_path, userdata);
    }

    visit_extra_ro_paths(visitor, userdata);
}

static void add_ro_rule_with_access(int ruleset_fd, const char *path,
                                    uint64_t access)
{
    if (!guard_path_exists(path)) {
        return;
    }

    if (guard_add_path_rule(ruleset_fd, path, access) != 0) {
        fprintf(stderr, "preview-guard: landlock rule failed for %s: %s\n",
                path, strerror(errno));
        exit(1);
    }
}

static void add_ro_rule_if_exists(int ruleset_fd, const char *path)
{
    uint64_t access = guard_path_is_regular(path)
                          ? (LANDLOCK_ACCESS_FS_READ_FILE |
                             LANDLOCK_ACCESS_FS_EXECUTE)
                          : guard_ro_access();

    add_ro_rule_with_access(ruleset_fd, path, access);
}

static void add_target_ro_rule_if_exists(int ruleset_fd, const char *path)
{
    uint64_t access = guard_path_is_regular(path) ? LANDLOCK_ACCESS_FS_READ_FILE
                                                   : guard_ro_access();

    add_ro_rule_with_access(ruleset_fd, path, access);
}

static void add_ro_rule_visitor(const char *path, void *userdata)
{
    int ruleset_fd = *(int *)userdata;
    add_ro_rule_if_exists(ruleset_fd, path);
}

static void add_dev_rule_visitor(const char *path, void *userdata)
{
    int ruleset_fd = *(int *)userdata;

    if (guard_add_path_rule(ruleset_fd, path, guard_dev_rw_access()) != 0) {
        fprintf(stderr, "preview-guard: device rule failed for %s: %s\n",
                path, strerror(errno));
        exit(1);
    }
}

static void print_ro_path_visitor(const char *path, void *userdata)
{
    (void)userdata;

    guard_validate_bind_path_or_die("preview-guard", path);
    puts(path);
}

static void install_landlock(const char *target_path, const char *lf_config_dir)
{
    struct landlock_ruleset_attr ruleset = {
        .handled_access_fs = guard_handled_fs_access(),
        .handled_access_net = LANDLOCK_ACCESS_NET_BIND_TCP |
                              LANDLOCK_ACCESS_NET_CONNECT_TCP,
        .scoped = LANDLOCK_SCOPE_ABSTRACT_UNIX_SOCKET |
                  LANDLOCK_SCOPE_SIGNAL,
    };

    int ruleset_fd = guard_ll_create_ruleset(&ruleset, sizeof(ruleset), 0);
    if (ruleset_fd < 0) {
        fprintf(stderr, "preview-guard: landlock ruleset failed: %s\n",
                strerror(errno));
        exit(1);
    }

    guard_visit_system_ro_paths("preview-guard", add_ro_rule_visitor, &ruleset_fd);

    if (guard_path_exists(lf_config_dir)) {
        add_ro_rule_if_exists(ruleset_fd, lf_config_dir);
    }

    if (guard_path_is_regular(target_path)) {
        add_target_ro_rule_if_exists(ruleset_fd, target_path);
    }

    visit_extra_ro_paths(add_ro_rule_visitor, &ruleset_fd);

    guard_visit_minimal_dev_paths(add_dev_rule_visitor, &ruleset_fd);

    if (guard_path_exists("/var/tmp") &&
        guard_add_path_rule(ruleset_fd, "/var/tmp", guard_tmp_access()) != 0) {
        fprintf(stderr, "preview-guard: /var/tmp rule failed: %s\n",
                strerror(errno));
        exit(1);
    }

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) {
        fprintf(stderr, "preview-guard: PR_SET_NO_NEW_PRIVS failed: %s\n",
                strerror(errno));
        exit(1);
    }

    if (guard_ll_restrict_self(ruleset_fd, LANDLOCK_RESTRICT_SELF_TSYNC) != 0) {
        fprintf(stderr, "preview-guard: landlock_restrict_self failed: %s\n",
                strerror(errno));
        exit(1);
    }

    close(ruleset_fd);
}

static void install_seccomp(void)
{
    scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_ALLOW);
    if (ctx == NULL) {
        fprintf(stderr, "preview-guard: seccomp_init failed\n");
        exit(1);
    }

    guard_add_errno_rule("preview-guard", ctx, SCMP_SYS(socket));
    guard_add_errno_rule("preview-guard", ctx, SCMP_SYS(socketpair));
    guard_add_errno_rule("preview-guard", ctx, SCMP_SYS(connect));
    guard_add_errno_rule("preview-guard", ctx, SCMP_SYS(bind));
    guard_add_errno_rule("preview-guard", ctx, SCMP_SYS(listen));
    guard_add_errno_rule("preview-guard", ctx, SCMP_SYS(accept));
    guard_add_errno_rule("preview-guard", ctx, SCMP_SYS(accept4));
    guard_add_errno_rule("preview-guard", ctx, SCMP_SYS(shutdown));
    guard_add_common_deny_syscalls("preview-guard", ctx);

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
                "usage: %s <target-path> <lf-config-dir> <command> [args...]\n"
                "       %s --print-bwrap-ro-paths <target-path> <lf-config-dir>\n",
                argv[0],
                argv[0]);
        return 1;
    }

    const char *target_path = argv[1];
    const char *lf_config_dir = argv[2];
    char **cmd = &argv[3];

    install_landlock(target_path, lf_config_dir);
    install_seccomp();

    execvp(cmd[0], cmd);
    fprintf(stderr, "preview-guard: execvp failed for %s: %s\n",
            cmd[0], strerror(errno));
    return 1;
}
