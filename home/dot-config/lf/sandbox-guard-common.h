#ifndef SANDBOX_GUARD_COMMON_H
#define SANDBOX_GUARD_COMMON_H

#include <linux/landlock.h>
#include <seccomp.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/syscall.h>

#ifndef SYS_landlock_create_ruleset
#error "Landlock syscalls are not available on this architecture"
#endif

typedef void (*guard_path_visitor)(const char *path, void *userdata);

int guard_ll_create_ruleset(const struct landlock_ruleset_attr *attr, size_t size, __u32 flags);
int guard_ll_add_rule(int ruleset_fd, enum landlock_rule_type rule_type, const void *rule_attr, __u32 flags);
int guard_ll_restrict_self(int ruleset_fd, __u32 flags);

uint64_t guard_handled_fs_access(void);
uint64_t guard_ro_access(void);
uint64_t guard_rw_access(void);
uint64_t guard_tmp_access(void);
uint64_t guard_dev_rw_access(void);
uint64_t guard_dev_null_access(void);
uint64_t guard_unix_socket_access(void);

bool guard_path_exists(const char *path);
bool guard_path_is_dir(const char *path);
bool guard_path_is_regular(const char *path);
void guard_visit_colon_env_paths(const char *program_name, const char *env_name, guard_path_visitor visitor, void *userdata);
void guard_visit_system_ro_paths(const char *program_name, guard_path_visitor visitor, void *userdata);
void guard_visit_minimal_dev_paths(guard_path_visitor visitor, void *userdata);
void guard_visit_base_ro_paths(const char *program_name, const char *target_path, const char *lf_config_dir, guard_path_visitor visitor, void *userdata);
int guard_add_path_rule(int ruleset_fd, const char *path, uint64_t access);
void guard_add_errno_rule(const char *program_name, scmp_filter_ctx ctx, int syscall_nr);
void guard_add_namespace_clone_deny_rules(const char *program_name, scmp_filter_ctx ctx);
void guard_add_common_deny_syscalls(const char *program_name, scmp_filter_ctx ctx);
void guard_validate_bind_path_or_die(const char *program_name, const char *path);

#endif
