#ifndef ios_explore_fishhook_h
#define ios_explore_fishhook_h

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*ios_explore_nslog_callback_t)(const char *message);

int ios_explore_install_nslog_hook(ios_explore_nslog_callback_t callback);

#ifdef __cplusplus
}
#endif

#endif
