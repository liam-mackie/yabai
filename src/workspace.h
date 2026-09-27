#ifndef WORKSPACE_H
#define WORKSPACE_H

#define SUPPORTED_MACOS_VERSION_LIST    \
    SUPPORT_MACOS_VERSION(goldengate,   27) \
    SUPPORT_MACOS_VERSION(tahoe,        26) \
    SUPPORT_MACOS_VERSION(sequoia,      15) \
    SUPPORT_MACOS_VERSION(sonoma,       14) \
    SUPPORT_MACOS_VERSION(ventura,      13) \
    SUPPORT_MACOS_VERSION(monterey,     12) \
    SUPPORT_MACOS_VERSION(bigsur,       11)

#define SUPPORT_MACOS_VERSION(name, major_version) \
static bool _workspace_is_macos_version_##name; \
static inline bool workspace_is_macos_##name(void) \
{ \
    return _workspace_is_macos_version_##name; \
}
    SUPPORTED_MACOS_VERSION_LIST
#undef SUPPORT_MACOS_VERSION

static inline void workspace_set_macos_version(long running_major_version)
{
    // NOTE: A release newer than the newest one listed takes the newest one's code paths;
    // otherwise every check is false and it falls through to the pre-Ventura ones.
    long newest_major_version = 0;
#define SUPPORT_MACOS_VERSION(name, major_version) if (major_version > newest_major_version) newest_major_version = major_version;
    SUPPORTED_MACOS_VERSION_LIST
#undef SUPPORT_MACOS_VERSION

    if (running_major_version > newest_major_version) running_major_version = newest_major_version;

#define SUPPORT_MACOS_VERSION(name, major_version) _workspace_is_macos_version_##name = running_major_version == major_version;
    SUPPORTED_MACOS_VERSION_LIST
#undef SUPPORT_MACOS_VERSION
}

@interface workspace_context : NSObject {
}
- (id)init;
@end

struct process;
void *workspace_application_create_running_ns_application(struct process *process);
void workspace_application_destroy_running_ns_application(void *context, struct process *process);
void workspace_application_unobserve(void *context, struct process *process);
bool workspace_application_is_observable(struct process *process);
bool workspace_application_is_finished_launching(struct process *process);
void workspace_application_observe_finished_launching(void *context, struct process *process);
void workspace_application_observe_activation_policy(void *context, struct process *process);
int workspace_display_notch_height(uint32_t did);
pid_t workspace_get_dock_pid(void);
bool workspace_event_handler_begin(void **context);
bool workspace_use_macos_space_workaround(void);

#endif
