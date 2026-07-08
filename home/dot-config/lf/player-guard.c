#define _GNU_SOURCE

#include "sandbox-guard-common.h"

#include <errno.h>
#include <linux/landlock.h>
#include <seccomp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <unistd.h>

/*
 * Player guard policy summary:
 * - Profile: player; CLI compatibility is part of the security contract.
 * - Read-only filesystem inputs: /bin, /usr, /lib, /lib64, /etc,
 *   lf_config_dir, target_path, and PLAYER_EXTRA_RO_PATHS.
 * - Read/write filesystem inputs: PLAYER_EXTRA_RW_PATHS, currently used by
 *   the launcher for /dev/shm.
 * - Unix socket resolution inputs: PLAYER_EXTRA_UNIX_SOCKET_PATHS.
 * - Networking/socket policy: seccomp denies internet, netlink, packet,
 *   bluetooth, and vsock socket domains plus bind/listen/accept/accept4;
 *   Unix socket client behavior is allowed only where constrained by bwrap
 *   binds and Landlock RESOLVE_UNIX rules.
 * - Shared hardening: no-new-privs, then Landlock restriction, then seccomp,
 *   all installed before execvp of the selected player.
 */

static void visit_extra_ro_paths(guard_path_visitor visitor, void *userdata)
{
    guard_visit_colon_env_paths("player-guard", "PLAYER_EXTRA_RO_PATHS",
                                visitor, userdata);
}

static void visit_extra_rw_paths(guard_path_visitor visitor, void *userdata)
{
    guard_visit_colon_env_paths("player-guard", "PLAYER_EXTRA_RW_PATHS",
                                visitor, userdata);
}

static void visit_extra_unix_socket_paths(guard_path_visitor visitor, void *userdata)
{
    guard_visit_colon_env_paths("player-guard", "PLAYER_EXTRA_UNIX_SOCKET_PATHS",
                                visitor, userdata);
}

static void visit_ro_paths(const char *target_path, const char *lf_config_dir,
                           guard_path_visitor visitor, void *userdata)
{
    guard_visit_base_ro_paths(target_path, lf_config_dir, visitor, userdata);
    visit_extra_ro_paths(visitor, userdata);
}

static void add_ro_rule_if_exists(int ruleset_fd, const char *path)
{
    if (!guard_path_exists(path)) {
        return;
    }

    uint64_t access = guard_path_is_dir(path) ? guard_ro_access()
                                               : LANDLOCK_ACCESS_FS_READ_FILE;

    if (guard_add_path_rule(ruleset_fd, path, access) != 0) {
        fprintf(stderr, "player-guard: landlock RO rule failed for %s: %s\n",
                path, strerror(errno));
        exit(1);
    }
}

static void add_rw_rule_if_exists(int ruleset_fd, const char *path)
{
    if (!guard_path_exists(path)) {
        return;
    }

    if (guard_add_path_rule(ruleset_fd, path, guard_rw_access()) != 0) {
        fprintf(stderr, "player-guard: landlock RW rule failed for %s: %s\n",
                path, strerror(errno));
        exit(1);
    }
}

static void add_unix_socket_rule_if_exists(int ruleset_fd, const char *path)
{
    if (!guard_path_exists(path)) {
        return;
    }

    if (guard_add_path_rule(ruleset_fd, path, guard_unix_socket_access()) != 0) {
        fprintf(stderr,
                "player-guard: landlock UNIX socket rule failed for %s: %s\n",
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

    guard_validate_bind_path_or_die("player-guard", path);
    puts(path);
}

struct rw_rule_ctx {
    int ruleset_fd;
};

static void add_rw_rule_visitor(const char *path, void *userdata)
{
    struct rw_rule_ctx *ctx = userdata;
    add_rw_rule_if_exists(ctx->ruleset_fd, path);
}

static void add_unix_socket_rule_visitor(const char *path, void *userdata)
{
    int ruleset_fd = *(int *)userdata;
    add_unix_socket_rule_if_exists(ruleset_fd, path);
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
        fprintf(stderr, "player-guard: landlock ruleset failed: %s\n",
                strerror(errno));
        exit(1);
    }

    visit_ro_paths(target_path, lf_config_dir, add_ro_rule_visitor, &ruleset_fd);

    if (guard_path_exists("/var/tmp") &&
        guard_add_path_rule(ruleset_fd, "/var/tmp", guard_tmp_access()) != 0) {
        fprintf(stderr, "player-guard: /var/tmp rule failed: %s\n",
                strerror(errno));
        exit(1);
    }

    {
        struct rw_rule_ctx ctx = {
            .ruleset_fd = ruleset_fd,
        };
        visit_extra_rw_paths(add_rw_rule_visitor, &ctx);
    }

    visit_extra_unix_socket_paths(add_unix_socket_rule_visitor, &ruleset_fd);

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) {
        fprintf(stderr, "player-guard: PR_SET_NO_NEW_PRIVS failed: %s\n",
                strerror(errno));
        exit(1);
    }

    if (guard_ll_restrict_self(ruleset_fd, LANDLOCK_RESTRICT_SELF_TSYNC) != 0) {
        fprintf(stderr, "player-guard: landlock_restrict_self failed: %s\n",
                strerror(errno));
        exit(1);
    }

    close(ruleset_fd);
}

static void add_socket_domain_errno_rule(scmp_filter_ctx ctx, int domain)
{
    if (seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(socket), 1,
                         SCMP_A0(SCMP_CMP_EQ, domain)) < 0) {
        fprintf(stderr,
                "player-guard: seccomp socket rule failed for domain %d\n",
                domain);
        exit(1);
    }
}

static void install_seccomp(void)
{
    scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_ALLOW);
    if (ctx == NULL) {
        fprintf(stderr, "player-guard: seccomp_init failed\n");
        exit(1);
    }

    add_socket_domain_errno_rule(ctx, AF_INET);
    add_socket_domain_errno_rule(ctx, AF_INET6);
    add_socket_domain_errno_rule(ctx, AF_NETLINK);
    add_socket_domain_errno_rule(ctx, AF_PACKET);
#ifdef AF_BLUETOOTH
    add_socket_domain_errno_rule(ctx, AF_BLUETOOTH);
#endif
#ifdef AF_VSOCK
    add_socket_domain_errno_rule(ctx, AF_VSOCK);
#endif

    guard_add_errno_rule("player-guard", ctx, SCMP_SYS(bind));
    guard_add_errno_rule("player-guard", ctx, SCMP_SYS(listen));
    guard_add_errno_rule("player-guard", ctx, SCMP_SYS(accept));
    guard_add_errno_rule("player-guard", ctx, SCMP_SYS(accept4));
    guard_add_common_deny_syscalls("player-guard", ctx);

    if (seccomp_load(ctx) < 0) {
        fprintf(stderr, "player-guard: seccomp_load failed\n");
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
    fprintf(stderr, "player-guard: execvp failed for %s: %s\n",
            cmd[0], strerror(errno));
    return 1;
}
