#import "ios_explore_fishhook.h"
#import "fishhook.h"

#import <Foundation/Foundation.h>

static ios_explore_nslog_callback_t ios_explore_nslog_callback = NULL;
static void (*ios_explore_original_NSLog)(NSString *format, ...) = NULL;
static void (*ios_explore_original_NSLogv)(NSString *format, va_list args) = NULL;

static void ios_explore_emit_nslog_message(NSString *message) {
  ios_explore_nslog_callback_t callback = ios_explore_nslog_callback;
  if (callback == NULL || message == nil) {
    return;
  }
  const char *utf8 = [message UTF8String];
  if (utf8 != NULL) {
    callback(utf8);
  }
}

static void ios_explore_replacement_NSLog(NSString *format, ...) {
  va_list args;
  va_start(args, format);
  NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  ios_explore_emit_nslog_message(message);

  if (ios_explore_original_NSLogv != NULL) {
    va_list original_args;
    va_start(original_args, format);
    ios_explore_original_NSLogv(format, original_args);
    va_end(original_args);
  } else if (ios_explore_original_NSLog != NULL) {
    ios_explore_original_NSLog(@"%@", message);
  }
}

static void ios_explore_replacement_NSLogv(NSString *format, va_list args) {
  va_list callback_args;
  va_copy(callback_args, args);
  NSString *message = [[NSString alloc] initWithFormat:format arguments:callback_args];
  va_end(callback_args);

  ios_explore_emit_nslog_message(message);

  if (ios_explore_original_NSLogv != NULL) {
    ios_explore_original_NSLogv(format, args);
  }
}

int ios_explore_install_nslog_hook(ios_explore_nslog_callback_t callback) {
  ios_explore_nslog_callback = callback;
  struct rebinding rebindings[] = {
    {"NSLog", ios_explore_replacement_NSLog, (void **)&ios_explore_original_NSLog},
    {"NSLogv", ios_explore_replacement_NSLogv, (void **)&ios_explore_original_NSLogv},
  };
  return rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
}
