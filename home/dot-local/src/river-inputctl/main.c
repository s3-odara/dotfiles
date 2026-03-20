#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <stdbool.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <wayland-client.h>

#include "river-input-management-v1-client-protocol.h"
#include "river-libinput-config-v1-client-protocol.h"

enum rule_kind {
    RULE_TAP,
    RULE_TAP_BUTTON_MAP,
    RULE_NATURAL_SCROLL,
    RULE_ACCEL_PROFILE,
    RULE_ACCEL_SPEED,
};

enum action_result {
    ACTION_SUCCESS = 0,
    ACTION_UNSUPPORTED = 1,
    ACTION_INVALID = 2,
};

struct rule {
    enum rule_kind kind;
    char *match;
    union {
        uint32_t u32;
        double f64;
    } value;
};

struct device {
    struct app *app;
    struct river_input_device_v1 *input;
    struct river_libinput_device_v1 *libinput;
    char *name;
    uint32_t type;
    bool have_name;
    bool have_type;
    bool repeat_applied;
    bool libinput_rules_applied;
};

struct app {
    struct wl_display *display;
    struct wl_registry *registry;
    struct river_input_manager_v1 *input_manager;
    struct river_libinput_config_v1 *libinput_config;

    struct device **devices;
    size_t device_len;
    size_t device_cap;

    struct rule *rules;
    size_t rule_len;
    size_t rule_cap;

    bool have_repeat;
    int repeat_rate;
    int repeat_delay;
    bool watch;
    bool input_manager_finished;
    bool libinput_config_finished;
    bool input_manager_stopped;
    bool libinput_config_stopped;

    int exit_code;
    int pending_results;
};

struct pending_result {
    struct app *app;
    char *device_name;
    const char *action;
};

struct libinput_listener_data {
    struct app *app;
    struct device *device;
};

static void die_usage(FILE *stream, int code);
static char *xstrdup(const char *s);
static void *xreallocarray(void *ptr, size_t nmemb, size_t size);
static double parse_double(const char *s, const char *flag);
static int parse_int(const char *s, const char *flag);
static const char *device_name_or_unknown(const struct device *device);
static bool device_name_matches(const char *pattern, const char *name);
static void add_rule(struct app *app, struct rule rule);
static struct device *append_device(struct app *app, struct river_input_device_v1 *input);
static struct device *find_device_by_input(struct app *app, struct river_input_device_v1 *input);
static void apply_device_rules(struct app *app, struct device *device);
static void apply_rules(struct app *app);
static void setup_pending_result(struct app *app, struct river_libinput_result_v1 *result, const char *device_name, const char *action);
static void stop_globals(struct app *app);
static int dispatch_until_stopped(struct app *app);

static volatile sig_atomic_t g_terminate_requested;

static void handle_signal(int signo) {
    (void)signo;
    g_terminate_requested = 1;
}

static void input_manager_finished(void *data, struct river_input_manager_v1 *manager) {
    struct app *app = data;

    (void)manager;
    app->input_manager_finished = true;
}

static void libinput_config_finished(void *data, struct river_libinput_config_v1 *config) {
    struct app *app = data;

    (void)config;
    app->libinput_config_finished = true;
}

static void input_device_removed(void *data, struct river_input_device_v1 *input) {
    struct device *device = data;

    if (device->input == input) {
        device->input = NULL;
    }
}

static void input_device_type(void *data, struct river_input_device_v1 *input, uint32_t type) {
    struct device *device = data;

    (void)input;
    device->type = type;
    device->have_type = true;
    apply_device_rules(device->app, device);
}

static void input_device_name(void *data, struct river_input_device_v1 *input, const char *name) {
    struct device *device = data;

    (void)input;
    free(device->name);
    device->name = xstrdup(name);
    device->have_name = true;
    apply_device_rules(device->app, device);
}

static const struct river_input_device_v1_listener input_device_listener = {
    .removed = input_device_removed,
    .type = input_device_type,
    .name = input_device_name,
};

static void input_manager_input_device(void *data, struct river_input_manager_v1 *manager, struct river_input_device_v1 *input) {
    struct app *app = data;
    struct device *device;

    (void)manager;
    device = append_device(app, input);
    river_input_device_v1_add_listener(input, &input_device_listener, device);
    apply_device_rules(app, device);
}

static const struct river_input_manager_v1_listener input_manager_listener = {
    .finished = input_manager_finished,
    .input_device = input_manager_input_device,
};

static void libinput_device_removed(void *data, struct river_libinput_device_v1 *libinput) {
    struct libinput_listener_data *listener_data = data;
    struct device *device = listener_data->device;

    if (device != NULL && device->libinput == libinput) {
        device->libinput = NULL;
    }
    free(listener_data);
}

static void libinput_device_input_device(void *data, struct river_libinput_device_v1 *libinput, struct river_input_device_v1 *input) {
    struct libinput_listener_data *listener_data = data;
    struct app *app = listener_data->app;
    struct device *device = find_device_by_input(app, input);

    if (device == NULL) {
        device = append_device(app, input);
    }
    device->libinput = libinput;
    listener_data->device = device;
    apply_device_rules(app, device);
}

static void libinput_device_noop_u32(void *data, struct river_libinput_device_v1 *libinput, uint32_t value) {
    (void)data;
    (void)libinput;
    (void)value;
}

static void libinput_device_noop_i32(void *data, struct river_libinput_device_v1 *libinput, int32_t value) {
    (void)data;
    (void)libinput;
    (void)value;
}

static void libinput_device_noop_array(void *data, struct river_libinput_device_v1 *libinput, struct wl_array *value) {
    (void)data;
    (void)libinput;
    (void)value;
}

static const struct river_libinput_device_v1_listener libinput_device_listener = {
    .removed = libinput_device_removed,
    .input_device = libinput_device_input_device,
    .send_events_support = libinput_device_noop_u32,
    .send_events_default = libinput_device_noop_u32,
    .send_events_current = libinput_device_noop_u32,
    .tap_support = libinput_device_noop_i32,
    .tap_default = libinput_device_noop_u32,
    .tap_current = libinput_device_noop_u32,
    .tap_button_map_default = libinput_device_noop_u32,
    .tap_button_map_current = libinput_device_noop_u32,
    .drag_default = libinput_device_noop_u32,
    .drag_current = libinput_device_noop_u32,
    .drag_lock_default = libinput_device_noop_u32,
    .drag_lock_current = libinput_device_noop_u32,
    .three_finger_drag_support = libinput_device_noop_i32,
    .three_finger_drag_default = libinput_device_noop_u32,
    .three_finger_drag_current = libinput_device_noop_u32,
    .calibration_matrix_support = libinput_device_noop_i32,
    .calibration_matrix_default = libinput_device_noop_array,
    .calibration_matrix_current = libinput_device_noop_array,
    .accel_profiles_support = libinput_device_noop_u32,
    .accel_profile_default = libinput_device_noop_u32,
    .accel_profile_current = libinput_device_noop_u32,
    .accel_speed_default = libinput_device_noop_array,
    .accel_speed_current = libinput_device_noop_array,
    .natural_scroll_support = libinput_device_noop_i32,
    .natural_scroll_default = libinput_device_noop_u32,
    .natural_scroll_current = libinput_device_noop_u32,
    .left_handed_support = libinput_device_noop_i32,
    .left_handed_default = libinput_device_noop_u32,
    .left_handed_current = libinput_device_noop_u32,
    .click_method_support = libinput_device_noop_u32,
    .click_method_default = libinput_device_noop_u32,
    .click_method_current = libinput_device_noop_u32,
    .clickfinger_button_map_default = libinput_device_noop_u32,
    .clickfinger_button_map_current = libinput_device_noop_u32,
    .middle_emulation_support = libinput_device_noop_i32,
    .middle_emulation_default = libinput_device_noop_u32,
    .middle_emulation_current = libinput_device_noop_u32,
    .scroll_method_support = libinput_device_noop_u32,
    .scroll_method_default = libinput_device_noop_u32,
    .scroll_method_current = libinput_device_noop_u32,
    .scroll_button_default = libinput_device_noop_u32,
    .scroll_button_current = libinput_device_noop_u32,
    .scroll_button_lock_default = libinput_device_noop_u32,
    .scroll_button_lock_current = libinput_device_noop_u32,
    .dwt_support = libinput_device_noop_i32,
    .dwt_default = libinput_device_noop_u32,
    .dwt_current = libinput_device_noop_u32,
    .dwtp_support = libinput_device_noop_i32,
    .dwtp_default = libinput_device_noop_u32,
    .dwtp_current = libinput_device_noop_u32,
    .rotation_support = libinput_device_noop_i32,
    .rotation_default = libinput_device_noop_u32,
    .rotation_current = libinput_device_noop_u32,
};

static void libinput_config_libinput_device(void *data, struct river_libinput_config_v1 *config, struct river_libinput_device_v1 *libinput) {
    struct app *app = data;
    struct libinput_listener_data *listener_data = xreallocarray(NULL, 1, sizeof(*listener_data));

    (void)config;
    listener_data->app = app;
    listener_data->device = NULL;
    river_libinput_device_v1_add_listener(libinput, &libinput_device_listener, listener_data);
}

static const struct river_libinput_config_v1_listener libinput_config_listener = {
    .finished = libinput_config_finished,
    .libinput_device = libinput_config_libinput_device,
};

static void result_success(void *data, struct river_libinput_result_v1 *result) {
    struct pending_result *pending = data;

    river_libinput_result_v1_destroy(result);
    pending->app->pending_results--;
    free(pending->device_name);
    free(pending);
}

static void result_failure(void *data, struct river_libinput_result_v1 *result, enum action_result status) {
    struct pending_result *pending = data;
    const char *reason = status == ACTION_UNSUPPORTED ? "unsupported" : "invalid";

    fprintf(stderr, "river-inputctl: %s for \"%s\" failed: %s\n",
        pending->action, pending->device_name, reason);
    pending->app->exit_code = 1;
    river_libinput_result_v1_destroy(result);
    pending->app->pending_results--;
    free(pending->device_name);
    free(pending);
}

static void result_unsupported(void *data, struct river_libinput_result_v1 *result) {
    result_failure(data, result, ACTION_UNSUPPORTED);
}

static void result_invalid(void *data, struct river_libinput_result_v1 *result) {
    result_failure(data, result, ACTION_INVALID);
}

static const struct river_libinput_result_v1_listener result_listener = {
    .success = result_success,
    .unsupported = result_unsupported,
    .invalid = result_invalid,
};

static void registry_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    struct app *app = data;

    if (strcmp(interface, river_input_manager_v1_interface.name) == 0) {
        uint32_t bind_version = version < 1 ? version : 1;
        app->input_manager = wl_registry_bind(registry, name, &river_input_manager_v1_interface, bind_version);
        river_input_manager_v1_add_listener(app->input_manager, &input_manager_listener, app);
    } else if (strcmp(interface, river_libinput_config_v1_interface.name) == 0) {
        uint32_t bind_version = version < 1 ? version : 1;
        app->libinput_config = wl_registry_bind(registry, name, &river_libinput_config_v1_interface, bind_version);
        river_libinput_config_v1_add_listener(app->libinput_config, &libinput_config_listener, app);
    }
}

static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

static void die_usage(FILE *stream, int code) {
    fprintf(stream,
        "usage:\n"
        "  river-inputctl [options]\n"
        "\n"
        "options:\n"
        "  --repeat RATE DELAY\n"
        "  --tap MATCH enabled|disabled\n"
        "  --tap-button-map MATCH left-right-middle|left-middle-right\n"
        "  --natural-scroll MATCH enabled|disabled\n"
        "  --accel-profile MATCH none|flat|adaptive\n"
        "  --pointer-accel MATCH SPEED\n"
        "  --help\n");
    exit(code);
}

static char *xstrdup(const char *s) {
    char *copy = strdup(s);

    if (copy == NULL) {
        perror("strdup");
        exit(1);
    }
    return copy;
}

static void *xreallocarray(void *ptr, size_t nmemb, size_t size) {
    if (nmemb != 0 && size > SIZE_MAX / nmemb) {
        fprintf(stderr, "river-inputctl: allocation overflow\n");
        exit(1);
    }

    ptr = realloc(ptr, nmemb * size);
    if (ptr == NULL) {
        perror("realloc");
        exit(1);
    }
    return ptr;
}

static double parse_double(const char *s, const char *flag) {
    char *end = NULL;
    double value;

    errno = 0;
    value = strtod(s, &end);
    if (errno != 0 || end == s || *end != '\0') {
        fprintf(stderr, "river-inputctl: invalid %s value: %s\n", flag, s);
        exit(2);
    }
    return value;
}

static int parse_int(const char *s, const char *flag) {
    char *end = NULL;
    long value;

    errno = 0;
    value = strtol(s, &end, 10);
    if (errno != 0 || end == s || *end != '\0' || value < INT32_MIN || value > INT32_MAX) {
        fprintf(stderr, "river-inputctl: invalid %s value: %s\n", flag, s);
        exit(2);
    }
    return (int)value;
}

static uint32_t parse_enabled_disabled(const char *s, const char *flag, uint32_t enabled, uint32_t disabled) {
    if (strcmp(s, "enabled") == 0) {
        return enabled;
    }
    if (strcmp(s, "disabled") == 0) {
        return disabled;
    }
    fprintf(stderr, "river-inputctl: invalid %s value: %s\n", flag, s);
    exit(2);
}

static uint32_t parse_tap_button_map(const char *s) {
    if (strcmp(s, "left-right-middle") == 0) {
        return RIVER_LIBINPUT_DEVICE_V1_TAP_BUTTON_MAP_LRM;
    }
    if (strcmp(s, "left-middle-right") == 0) {
        return RIVER_LIBINPUT_DEVICE_V1_TAP_BUTTON_MAP_LMR;
    }
    fprintf(stderr, "river-inputctl: invalid --tap-button-map value: %s\n", s);
    exit(2);
}

static uint32_t parse_accel_profile(const char *s) {
    if (strcmp(s, "none") == 0) {
        return RIVER_LIBINPUT_DEVICE_V1_ACCEL_PROFILE_NONE;
    }
    if (strcmp(s, "flat") == 0) {
        return RIVER_LIBINPUT_DEVICE_V1_ACCEL_PROFILE_FLAT;
    }
    if (strcmp(s, "adaptive") == 0) {
        return RIVER_LIBINPUT_DEVICE_V1_ACCEL_PROFILE_ADAPTIVE;
    }
    fprintf(stderr, "river-inputctl: invalid --accel-profile value: %s\n", s);
    exit(2);
}

static const char *device_name_or_unknown(const struct device *device) {
    return device->have_name && device->name != NULL ? device->name : "<unknown>";
}

static bool device_name_matches(const char *pattern, const char *name) {
    if (strcmp(pattern, "*") == 0) {
        return true;
    }
    return strcmp(pattern, name) == 0;
}

static void add_rule(struct app *app, struct rule rule) {
    if (app->rule_len == app->rule_cap) {
        app->rule_cap = app->rule_cap == 0 ? 8 : app->rule_cap * 2;
        app->rules = xreallocarray(app->rules, app->rule_cap, sizeof(*app->rules));
    }
    app->rules[app->rule_len++] = rule;
}

static struct device *append_device(struct app *app, struct river_input_device_v1 *input) {
    struct device *device = find_device_by_input(app, input);

    if (device != NULL) {
        return device;
    }
    if (app->device_len == app->device_cap) {
        app->device_cap = app->device_cap == 0 ? 8 : app->device_cap * 2;
        app->devices = xreallocarray(app->devices, app->device_cap, sizeof(*app->devices));
    }
    device = calloc(1, sizeof(*device));
    if (device == NULL) {
        perror("calloc");
        exit(1);
    }
    device->app = app;
    device->input = input;
    app->devices[app->device_len++] = device;
    return device;
}

static struct device *find_device_by_input(struct app *app, struct river_input_device_v1 *input) {
    size_t i;

    for (i = 0; i < app->device_len; i++) {
        if (app->devices[i]->input == input) {
            return app->devices[i];
        }
    }
    return NULL;
}

static void setup_pending_result(struct app *app, struct river_libinput_result_v1 *result, const char *device_name, const char *action) {
    struct pending_result *pending;

    if (result == NULL) {
        fprintf(stderr, "river-inputctl: failed to create result object for \"%s\"\n", device_name);
        app->exit_code = 1;
        return;
    }

    pending = calloc(1, sizeof(*pending));
    if (pending == NULL) {
        perror("calloc");
        exit(1);
    }
    pending->app = app;
    pending->device_name = xstrdup(device_name);
    pending->action = action;

    app->pending_results++;
    river_libinput_result_v1_add_listener(result, &result_listener, pending);
}

static void apply_repeat(struct app *app, struct device *device) {
    if (!app->have_repeat || device->repeat_applied || device->input == NULL || !device->have_type) {
        return;
    }
    if (device->type != RIVER_INPUT_DEVICE_V1_TYPE_KEYBOARD) {
        return;
    }
    river_input_device_v1_set_repeat_info(device->input, app->repeat_rate, app->repeat_delay);
    device->repeat_applied = true;
}

static void apply_libinput_rule(struct app *app, struct device *device, const struct rule *rule) {
    struct river_libinput_result_v1 *result = NULL;
    struct wl_array array;
    double *value_ptr;
    const char *name = device_name_or_unknown(device);

    if (device->libinput == NULL || !device->have_name) {
        return;
    }
    if (!device_name_matches(rule->match, device->name)) {
        return;
    }

    switch (rule->kind) {
    case RULE_TAP:
        result = river_libinput_device_v1_set_tap(device->libinput, rule->value.u32);
        setup_pending_result(app, result, name, "set_tap");
        break;
    case RULE_TAP_BUTTON_MAP:
        result = river_libinput_device_v1_set_tap_button_map(device->libinput, rule->value.u32);
        setup_pending_result(app, result, name, "set_tap_button_map");
        break;
    case RULE_NATURAL_SCROLL:
        result = river_libinput_device_v1_set_natural_scroll(device->libinput, rule->value.u32);
        setup_pending_result(app, result, name, "set_natural_scroll");
        break;
    case RULE_ACCEL_PROFILE:
        result = river_libinput_device_v1_set_accel_profile(device->libinput, rule->value.u32);
        setup_pending_result(app, result, name, "set_accel_profile");
        break;
    case RULE_ACCEL_SPEED:
        wl_array_init(&array);
        value_ptr = wl_array_add(&array, sizeof(*value_ptr));
        if (value_ptr == NULL) {
            perror("wl_array_add");
            wl_array_release(&array);
            exit(1);
        }
        *value_ptr = rule->value.f64;
        result = river_libinput_device_v1_set_accel_speed(device->libinput, &array);
        wl_array_release(&array);
        setup_pending_result(app, result, name, "set_accel_speed");
        break;
    }
}

static void apply_libinput_rules(struct app *app, struct device *device) {
    size_t i;

    if (device->libinput_rules_applied || device->libinput == NULL || !device->have_name) {
        return;
    }
    for (i = 0; i < app->rule_len; i++) {
        apply_libinput_rule(app, device, &app->rules[i]);
    }
    device->libinput_rules_applied = true;
}

static void apply_device_rules(struct app *app, struct device *device) {
    if (app == NULL || device == NULL) {
        return;
    }
    apply_repeat(app, device);
    apply_libinput_rules(app, device);
}

static void apply_rules(struct app *app) {
    size_t i;

    for (i = 0; i < app->device_len; i++) {
        apply_device_rules(app, app->devices[i]);
    }
}

static void stop_globals(struct app *app) {
    if (app->input_manager != NULL && !app->input_manager_stopped) {
        river_input_manager_v1_stop(app->input_manager);
        app->input_manager_stopped = true;
    }
    if (app->libinput_config != NULL && !app->libinput_config_stopped) {
        river_libinput_config_v1_stop(app->libinput_config);
        app->libinput_config_stopped = true;
    }
}

static int dispatch_until_stopped(struct app *app) {
    while ((!app->input_manager_finished || (app->libinput_config != NULL && !app->libinput_config_finished)) ||
            app->pending_results > 0) {
        if (wl_display_roundtrip(app->display) < 0) {
            if (errno == EINTR && g_terminate_requested) {
                continue;
            }
            return -1;
        }
    }
    return 0;
}

static void cleanup(struct app *app) {
    size_t i;

    if (app->input_manager != NULL && app->input_manager_finished) {
        river_input_manager_v1_destroy(app->input_manager);
    }
    if (app->libinput_config != NULL && app->libinput_config_finished) {
        river_libinput_config_v1_destroy(app->libinput_config);
    }
    for (i = 0; i < app->device_len; i++) {
        struct device *device = app->devices[i];

        if (device->libinput != NULL) {
            river_libinput_device_v1_destroy(device->libinput);
        }
        if (device->input != NULL) {
            river_input_device_v1_destroy(device->input);
        }
        free(device->name);
        free(device);
    }
    free(app->devices);
    for (i = 0; i < app->rule_len; i++) {
        free(app->rules[i].match);
    }
    free(app->rules);
    if (app->registry != NULL) {
        wl_registry_destroy(app->registry);
    }
    if (app->display != NULL) {
        wl_display_disconnect(app->display);
    }
}

int main(int argc, char **argv) {
    struct app app = {.watch = true};
    struct sigaction sa = {0};
    int i;

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--help") == 0) {
            die_usage(stdout, 0);
        } else if (strcmp(argv[i], "--watch") == 0) {
            app.watch = true;
        } else if (strcmp(argv[i], "--repeat") == 0) {
            if (i + 2 >= argc) {
                die_usage(stderr, 2);
            }
            app.have_repeat = true;
            app.repeat_rate = parse_int(argv[++i], "--repeat");
            app.repeat_delay = parse_int(argv[++i], "--repeat");
        } else if (strcmp(argv[i], "--tap") == 0) {
            struct rule rule;
            if (i + 2 >= argc) {
                die_usage(stderr, 2);
            }
            rule.kind = RULE_TAP;
            rule.match = xstrdup(argv[++i]);
            rule.value.u32 = parse_enabled_disabled(argv[++i], "--tap",
                RIVER_LIBINPUT_DEVICE_V1_TAP_STATE_ENABLED,
                RIVER_LIBINPUT_DEVICE_V1_TAP_STATE_DISABLED);
            add_rule(&app, rule);
        } else if (strcmp(argv[i], "--tap-button-map") == 0) {
            struct rule rule;
            if (i + 2 >= argc) {
                die_usage(stderr, 2);
            }
            rule.kind = RULE_TAP_BUTTON_MAP;
            rule.match = xstrdup(argv[++i]);
            rule.value.u32 = parse_tap_button_map(argv[++i]);
            add_rule(&app, rule);
        } else if (strcmp(argv[i], "--natural-scroll") == 0) {
            struct rule rule;
            if (i + 2 >= argc) {
                die_usage(stderr, 2);
            }
            rule.kind = RULE_NATURAL_SCROLL;
            rule.match = xstrdup(argv[++i]);
            rule.value.u32 = parse_enabled_disabled(argv[++i], "--natural-scroll",
                RIVER_LIBINPUT_DEVICE_V1_NATURAL_SCROLL_STATE_ENABLED,
                RIVER_LIBINPUT_DEVICE_V1_NATURAL_SCROLL_STATE_DISABLED);
            add_rule(&app, rule);
        } else if (strcmp(argv[i], "--accel-profile") == 0) {
            struct rule rule;
            if (i + 2 >= argc) {
                die_usage(stderr, 2);
            }
            rule.kind = RULE_ACCEL_PROFILE;
            rule.match = xstrdup(argv[++i]);
            rule.value.u32 = parse_accel_profile(argv[++i]);
            add_rule(&app, rule);
        } else if (strcmp(argv[i], "--pointer-accel") == 0) {
            struct rule rule;
            if (i + 2 >= argc) {
                die_usage(stderr, 2);
            }
            rule.kind = RULE_ACCEL_SPEED;
            rule.match = xstrdup(argv[++i]);
            rule.value.f64 = parse_double(argv[++i], "--pointer-accel");
            add_rule(&app, rule);
        } else {
            fprintf(stderr, "river-inputctl: unknown option: %s\n", argv[i]);
            die_usage(stderr, 2);
        }
    }

    if (!app.have_repeat && app.rule_len == 0) {
        die_usage(stderr, 2);
    }

    sa.sa_handler = handle_signal;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);

    app.display = wl_display_connect(NULL);
    if (app.display == NULL) {
        fprintf(stderr, "river-inputctl: failed to connect to wayland display\n");
        return 1;
    }

    app.registry = wl_display_get_registry(app.display);
    wl_registry_add_listener(app.registry, &registry_listener, &app);

    if (wl_display_roundtrip(app.display) < 0 || wl_display_roundtrip(app.display) < 0) {
        fprintf(stderr, "river-inputctl: failed while reading wayland globals\n");
        cleanup(&app);
        return 1;
    }

    if (app.input_manager == NULL) {
        fprintf(stderr, "river-inputctl: river_input_manager_v1 is not available\n");
        cleanup(&app);
        return 1;
    }
    if (app.rule_len > 0 && app.libinput_config == NULL) {
        fprintf(stderr, "river-inputctl: river_libinput_config_v1 is not available\n");
        cleanup(&app);
        return 1;
    }

    apply_rules(&app);

    if (app.watch) {
        while (!g_terminate_requested) {
            if (wl_display_dispatch(app.display) < 0) {
                if (errno == EINTR && g_terminate_requested) {
                    break;
                }
                fprintf(stderr, "river-inputctl: failed while dispatching wayland events\n");
                app.exit_code = 1;
                break;
            }
        }
    } else {
        while (app.pending_results > 0) {
            if (wl_display_roundtrip(app.display) < 0) {
                fprintf(stderr, "river-inputctl: failed while waiting for results\n");
                app.exit_code = 1;
                break;
            }
        }
    }

    stop_globals(&app);
    if (dispatch_until_stopped(&app) < 0) {
        fprintf(stderr, "river-inputctl: failed while stopping wayland globals\n");
        app.exit_code = 1;
    }

    cleanup(&app);
    return app.exit_code;
}
