#include <string.h>
#include <limits.h>
#include <stdio.h>

#include <dirent.h>
#include <sys/stat.h>
#include <fcntl.h>

#include <unistd.h>

#include "zygisk.h"

#include "logger.h"

#include <jni.h>

struct api_table *api_table;
JNIEnv *java_env;

jclass entrypoint;

char *get_string_data(JNIEnv *env, jstring *value) {
  const char *str = (*env)->GetStringUTFChars(env, *value, 0);
  if (str == NULL) return NULL;

  char *out = strdup(str);
  (*env)->ReleaseStringUTFChars(env, *value, str);

  return out;
}

void pre_specialize(const char *process) {
  // Demonstrate connecting to to companion process
  // We ask the companion for a random number
  unsigned r = 0;
  int fd = api_table->connectCompanion(api_table->impl);
  read(fd, &r, sizeof(r));
  close(fd);
  LOGD("process=[%s], r=[%u]\n", process, r);

  // Since we do not hook any functions, we should let Zygisk dlclose ourselves
  api_table->setOption(api_table->impl, DLCLOSE_MODULE_LIBRARY);
}

/* INFO: This is the beginning of zygisk's functions
those are triggered by it on each stage:
 * .preAppSpecialize: Called on app open; runs with elevated privileges before the process is sandboxed.
 * .postAppSpecialize: Called after app sandboxing; runs within the app's restricted security context.
 * .preServerSpecialize: Called before system_server forks; used for system-level modifications.
 * .postServerSpecialize: Called after system_server is specialized; runs with system-level privileges.
*/
void pre_app_specialize(void *mod_data, struct AppSpecializeArgs *args) {
  char *process = get_string_data(java_env, args->nice_name);
  pre_specialize(process);
}

void post_app_specialize(void *mod_data, const struct AppSpecializeArgs *args) {
  (void) mod_data; (void) args;
}

void pre_server_specialize(void *mod_data, struct ServerSpecializeArgs *args) {
  pre_specialize("system_server");
}

void post_server_specialize(void *mod_data, const struct ServerSpecializeArgs *args) {
  (void) mod_data; (void) args;
}

void zygisk_module_entry(struct api_table *table, JNIEnv *env) {
  api_table = table;
  java_env = env;

  static struct module_abi abi = {
    .api_version = 5,
    .preAppSpecialize = pre_app_specialize,
    .postAppSpecialize = post_app_specialize,
    .preServerSpecialize = pre_server_specialize,
    .postServerSpecialize = post_server_specialize
  };

  if (!table->registerModule(table, &abi)) return;
}

static int urandom = -1;

void zygisk_companion_entry(int fd) {
    if (urandom < 0) {
        urandom = open("/dev/urandom", O_RDONLY);
    }
    unsigned r;
    read(urandom, &r, sizeof(r));
    LOGD("companion r=[%u]\n", r);
    write(fd, &r, sizeof(r));
}
