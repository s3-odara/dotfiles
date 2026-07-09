#define _GNU_SOURCE

#include "sandbox-guard-common.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int guard_ll_create_ruleset(const struct landlock_ruleset_attr *attr, size_t size,
                            __u32 flags)
{
    return syscall(SYS_landlock_create_ruleset, attr, size, flags);
}

int guard_ll_add_rule(int ruleset_fd, enum landlock_rule_type rule_type,
                      const void *rule_attr, __u32 flags)
{
    return syscall(SYS_landlock_add_rule, ruleset_fd, rule_type, rule_attr, flags);
}

int guard_ll_restrict_self(int ruleset_fd, __u32 flags)
{
    return syscall(SYS_landlock_restrict_self, ruleset_fd, flags);
}

uint64_t guard_handled_fs_access(void)
{
    return LANDLOCK_ACCESS_FS_EXECUTE |
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
           LANDLOCK_ACCESS_FS_REFER |
           LANDLOCK_ACCESS_FS_TRUNCATE |
           LANDLOCK_ACCESS_FS_IOCTL_DEV |
           LANDLOCK_ACCESS_FS_RESOLVE_UNIX;
}

uint64_t guard_ro_access(void)
{
    return LANDLOCK_ACCESS_FS_EXECUTE |
           LANDLOCK_ACCESS_FS_READ_FILE |
           LANDLOCK_ACCESS_FS_READ_DIR;
}

uint64_t guard_rw_access(void)
{
    return LANDLOCK_ACCESS_FS_READ_FILE |
           LANDLOCK_ACCESS_FS_READ_DIR |
           LANDLOCK_ACCESS_FS_WRITE_FILE |
           LANDLOCK_ACCESS_FS_TRUNCATE |
           LANDLOCK_ACCESS_FS_IOCTL_DEV;
}

uint64_t guard_tmp_access(void)
{
    return LANDLOCK_ACCESS_FS_READ_FILE |
           LANDLOCK_ACCESS_FS_READ_DIR |
           LANDLOCK_ACCESS_FS_WRITE_FILE |
           LANDLOCK_ACCESS_FS_REMOVE_FILE |
           LANDLOCK_ACCESS_FS_MAKE_REG |
           LANDLOCK_ACCESS_FS_TRUNCATE;
}

uint64_t guard_dev_rw_access(void)
{
    return LANDLOCK_ACCESS_FS_READ_FILE |
           LANDLOCK_ACCESS_FS_WRITE_FILE |
           LANDLOCK_ACCESS_FS_IOCTL_DEV;
}

uint64_t guard_dev_null_access(void)
{
    return guard_dev_rw_access();
}

uint64_t guard_unix_socket_access(void)
{
    return LANDLOCK_ACCESS_FS_RESOLVE_UNIX;
}

bool guard_path_exists(const char *path)
{
    return access(path, F_OK) == 0;
}

bool guard_path_is_dir(const char *path)
{
    struct stat st;

    if (stat(path, &st) != 0) {
        return false;
    }

    return S_ISDIR(st.st_mode);
}

bool guard_path_is_regular(const char *path)
{
    struct stat st;

    if (stat(path, &st) != 0) {
        return false;
    }

    return S_ISREG(st.st_mode);
}

void guard_visit_colon_env_paths(const char *program_name, const char *env_name,
                                 guard_path_visitor visitor, void *userdata)
{
    const char *extra_paths = getenv(env_name);
    char *cursor;
    char *path;
    char *paths_copy;

    if (extra_paths == NULL || extra_paths[0] == '\0') {
        return;
    }

    paths_copy = strdup(extra_paths);
    if (paths_copy == NULL) {
        fprintf(stderr, "%s: strdup failed\n", program_name);
        exit(1);
    }

    cursor = paths_copy;
    while ((path = strsep(&cursor, ":")) != NULL) {
        if (path[0] == '\0') {
            continue;
        }
        if (guard_path_exists(path)) {
            visitor(path, userdata);
        }
    }

    free(paths_copy);
}

void guard_visit_system_ro_paths(guard_path_visitor visitor, void *userdata)
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
        if (guard_path_exists(base_paths[i])) {
            visitor(base_paths[i], userdata);
        }
    }
}

void guard_visit_minimal_dev_paths(guard_path_visitor visitor, void *userdata)
{
    static const char *const dev_paths[] = {
        "/dev/null",
        "/dev/zero",
        "/dev/full",
        "/dev/random",
        "/dev/urandom",
    };

    size_t i;
    for (i = 0; i < sizeof(dev_paths) / sizeof(dev_paths[0]); i++) {
        if (guard_path_exists(dev_paths[i])) {
            visitor(dev_paths[i], userdata);
        }
    }
}

void guard_visit_base_ro_paths(const char *target_path, const char *lf_config_dir,
                               guard_path_visitor visitor, void *userdata)
{
    guard_visit_system_ro_paths(visitor, userdata);

    if (guard_path_exists(lf_config_dir)) {
        visitor(lf_config_dir, userdata);
    }

    if (guard_path_exists(target_path)) {
        visitor(target_path, userdata);
    }
}

int guard_add_path_rule(int ruleset_fd, const char *path, uint64_t access)
{
    int fd = open(path, O_PATH | O_CLOEXEC);
    if (fd < 0) {
        return -1;
    }

    struct landlock_path_beneath_attr attr = {
        .allowed_access = access,
        .parent_fd = fd,
    };

    int rc = guard_ll_add_rule(ruleset_fd, LANDLOCK_RULE_PATH_BENEATH, &attr, 0);
    int saved_errno = errno;
    close(fd);
    errno = saved_errno;
    return rc;
}

void guard_add_errno_rule(const char *program_name, scmp_filter_ctx ctx, int syscall_nr)
{
    if (seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), syscall_nr, 0) < 0) {
        fprintf(stderr, "%s: seccomp rule failed for syscall %d\n",
                program_name, syscall_nr);
        exit(1);
    }
}

static void guard_add_syscall_errno_rule(const char *program_name,
                                         scmp_filter_ctx ctx,
                                         int syscall_nr,
                                         int errno_value)
{
    if (seccomp_rule_add(ctx, SCMP_ACT_ERRNO(errno_value), syscall_nr, 0) < 0) {
        fprintf(stderr, "%s: seccomp rule failed for syscall %d\n",
                program_name, syscall_nr);
        exit(1);
    }
}

static void guard_add_clone_flag_errno_rule(const char *program_name,
                                            scmp_filter_ctx ctx,
                                            scmp_datum_t flag,
                                            const char *flag_name)
{
    if (seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(clone), 1,
                         SCMP_A0(SCMP_CMP_MASKED_EQ, flag, flag)) < 0) {
        fprintf(stderr, "%s: seccomp clone rule failed for %s\n",
                program_name, flag_name);
        exit(1);
    }
}

void guard_add_namespace_clone_deny_rules(const char *program_name,
                                          scmp_filter_ctx ctx)
{
#ifdef __NR_clone3
    /*
     * Return ENOSYS instead of EPERM so ordinary clone3 users (notably
     * glibc pthread_create) fall back to legacy clone. Namespace creation
     * remains blocked by the masked CLONE_NEW* rules on clone below.
     */
    guard_add_syscall_errno_rule(program_name, ctx, SCMP_SYS(clone3), ENOSYS);
#endif

    guard_add_clone_flag_errno_rule(program_name, ctx, CLONE_NEWNS,
                                    "CLONE_NEWNS");
    guard_add_clone_flag_errno_rule(program_name, ctx, CLONE_NEWUTS,
                                    "CLONE_NEWUTS");
    guard_add_clone_flag_errno_rule(program_name, ctx, CLONE_NEWIPC,
                                    "CLONE_NEWIPC");
    guard_add_clone_flag_errno_rule(program_name, ctx, CLONE_NEWUSER,
                                    "CLONE_NEWUSER");
    guard_add_clone_flag_errno_rule(program_name, ctx, CLONE_NEWPID,
                                    "CLONE_NEWPID");
    guard_add_clone_flag_errno_rule(program_name, ctx, CLONE_NEWNET,
                                    "CLONE_NEWNET");
#ifdef CLONE_NEWCGROUP
    guard_add_clone_flag_errno_rule(program_name, ctx, CLONE_NEWCGROUP,
                                    "CLONE_NEWCGROUP");
#endif
#ifdef CLONE_NEWTIME
    guard_add_clone_flag_errno_rule(program_name, ctx, CLONE_NEWTIME,
                                    "CLONE_NEWTIME");
#endif
}

void guard_add_common_deny_syscalls(const char *program_name, scmp_filter_ctx ctx)
{
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(mount));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(umount2));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(pivot_root));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(open_tree));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(move_mount));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(fsopen));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(fsconfig));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(fsmount));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(fspick));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(mount_setattr));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(ptrace));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(process_vm_readv));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(process_vm_writev));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(kcmp));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(open_by_handle_at));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(name_to_handle_at));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(bpf));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(perf_event_open));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(userfaultfd));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(init_module));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(finit_module));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(delete_module));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(swapon));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(swapoff));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(reboot));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(kexec_load));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(kexec_file_load));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(setns));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(unshare));
    guard_add_namespace_clone_deny_rules(program_name, ctx);
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(keyctl));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(add_key));
    guard_add_errno_rule(program_name, ctx, SCMP_SYS(request_key));
}

void guard_validate_bind_path_or_die(const char *program_name, const char *path)
{
    if (strchr(path, '\n') != NULL) {
        fprintf(stderr,
                "%s: newline in bind path is not supported: %s\n",
                program_name, path);
        exit(1);
    }
}
