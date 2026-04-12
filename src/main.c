#include <sys/stat.h>
#include <unistd.h>

#include "zygisk.h"

#include "logger.h"

#include <jni.h>

#define JSMN_STRICT
#include "jsmn.h"
#include "oa_hash.h"
#include "jsmn-find.h"

struct api_table *api_table;
JNIEnv *java_env;

#define likely(x) __builtin_expect(!!(x), 1)

inline static void read_from_fd(int fd, char* var, size_t size, unsigned int i) {
  ssize_t reply = read(fd, var, size-1);
  if (reply <= 0) {
    var[0] = '\0';
    LOGE("(%u) Failed to read var (%zd)", i, reply);
    reply = 0;
  } else {
    var[reply] = '\0';
    LOGD("(%u) Read %s response(%zd)", i, var, reply);
  }
  write(fd, &reply, sizeof(reply));
}

inline static void write_to_fd(int fd, const char* var) {
  if (var == NULL) return;
  write(fd, var, strlen(var));

  size_t reply = 0;
  ssize_t r = read(fd, &reply, sizeof(reply));

  if (r <= 0) {
    LOGE("Received failed response from %s write (%zu)", var, reply);
  } else {
    LOGD("Written %s(%zu) reply(%zu)", var, strlen(var), reply);
  }
}

char *get_string_data(JNIEnv *env, jstring *value) {
  const char *str = (*env)->GetStringUTFChars(env, *value, 0);
  if (str == NULL) return NULL;

  char *out = strdup(str);
  (*env)->ReleaseStringUTFChars(env, *value, str);

  return out;
}

char *fd_to_path(int fd) {
    static char buffer[PATH_MAX];
    char proc_path[64];

    snprintf(proc_path, sizeof(proc_path), "/proc/self/fd/%d", fd);
    ssize_t len = readlink(proc_path, buffer, sizeof(buffer) - 1);

    if (len != -1) {
        buffer[len] = '\0';
        return buffer;
    }
    LOGE("Failed to convert fd %d to path", fd);
    return NULL;
}

char *get_package_name(char *data_dir, char *process_name) {
  struct stat st;
  if (stat(data_dir, &st) == -1) {
    LOGW("Failed to stat data directory: %s", data_dir);

    return process_name;
  }

  char *last_slash = strrchr(data_dir, '/');
  if (!last_slash) {
    LOGW("Failed to parse package name from data directory: %s", data_dir);

    return process_name;
  }

  char *pkg_name = last_slash + 1;
  LOGD("Package name: %s for process: %s", pkg_name, process_name);

  return pkg_name;
}

/* INFO: This is the beginning of zygisk's functions
those are triggered by it on each stage:
 * .preAppSpecialize: Called on app open; runs with elevated privileges before the process is sandboxed.
 * .postAppSpecialize: Called after app sandboxing; runs within the app's restricted security context.
 * .preServerSpecialize: Called before system_server forks; used for system-level modifications.
 * .postServerSpecialize: Called after system_server is specialized; runs with system-level privileges.
*/
void pre_app_specialize(void *mod_data, struct AppSpecializeArgs *args) {
  (void) mod_data;
  LOGD("Pre app specialize");
  api_table->setOption(api_table->impl, DLCLOSE_MODULE_LIBRARY);

  char *process_name = get_string_data(java_env, args->nice_name);
  char *data_dir = get_string_data(java_env, args->app_data_dir);
  if (!process_name && !data_dir) {
    LOGE("Failed to get process name and data dir");
    goto free;
  }

  char *package_name;
  if (data_dir) {
    package_name = get_package_name(data_dir, process_name);
  } else {
    package_name = process_name;
  }

  if (strlen(package_name) <= 1) {
    LOGE("Failed to get package name for process: %s", process_name);
    goto free;
  }

  int fd = api_table->connectCompanion(api_table->impl);
  if (fd == -1) {
    LOGE("Failed to connect to companion");
    goto free;
  }

  write(fd, package_name, strlen(package_name));
  LOGD("pkg sent: %s len(%u)", package_name, (unsigned int)strlen(package_name));

  unsigned int fields = 0;
  read(fd, &fields, sizeof(fields));
  LOGD("pre-fields: %d", fields);

  if (fields == 0) {
    LOGD("pkg: %s not in target, skip.", package_name);
    close(fd);
    goto free;
  }

  char name[64] = {0}, type[64] = {0}, class[64] = {0}, value[256] = {0};
  unsigned int r = 0;

  jclass fclass;
  for (unsigned int i = 0; i < fields; i++) {
    LOGD("(%d) receiving field...", i);

    write(fd, &i, sizeof(i));
    read(fd, &r, sizeof(r));
    LOGD("reconcile r:%d vs i:%d", r, i);
    if (r > i) continue;
    write(fd, &i, sizeof(i)); // ready reply

    read_from_fd(fd, name, sizeof(name), i);
    read_from_fd(fd, type, sizeof(type), i);
    read_from_fd(fd, class, sizeof(class), i);
    read_from_fd(fd, value, sizeof(value), i);
    LOGD("(%u) name: %s\ntype: %s\nclass: %s\nvalue: %s", i, name, type, class, value);

    if (strcmp(class, "build") == 0) {
      fclass = (*java_env)->FindClass(java_env, "android/os/Build");
    } else if (strcmp(class, "version") == 0) {
      fclass = (*java_env)->FindClass(java_env, "android/os/Build$VERSION");
    } else {
      LOGE("(%u) Could not find requested class (%s)", i, class);
      continue;
    }
    jfieldID fid = (*java_env)->GetStaticFieldID(java_env, fclass, name, type);

    if (strcmp(type, "Ljava/lang/String;") == 0) {
      jstring str = (*java_env)->NewStringUTF(java_env, value);
      if (!str || (*java_env)->ExceptionCheck(java_env)) {
        LOGE("(%u) Failed to set string for %s", i, name);
        (*java_env)->ExceptionClear(java_env);
        continue;
      }
      (*java_env)->SetStaticObjectField(java_env, fclass, fid, str);
      (*java_env)->DeleteLocalRef(java_env, str);
    } else if (strcmp(type, "I") == 0) {
      (*java_env)->SetStaticIntField(java_env, fclass, fid, (jint)atoi(value));
    } else if (strcmp(type, "J") == 0) {
      (*java_env)->SetStaticLongField(java_env, fclass, fid, (jlong)atoi(value));
    } else {
      LOGE("(%u) Could not find requested type (%s)", i, type);
      continue;
    }

    if ((*java_env)->ExceptionCheck(java_env)) (*java_env)->ExceptionClear(java_env);
    (*java_env)->DeleteLocalRef(java_env, fclass);
  }
  close(fd);

free:
  if (process_name) free(process_name);
  if (data_dir) free(data_dir);
  return;
}

void post_app_specialize(void *mod_data, const struct AppSpecializeArgs *args) {
  (void) mod_data; (void) args;
}

void pre_server_specialize(void *mod_data, struct ServerSpecializeArgs *args) {
  (void) mod_data; (void) args;
}

void post_server_specialize(void *mod_data, const struct ServerSpecializeArgs *args) {
  (void) mod_data; (void) args;
}

void zygisk_module_entry(struct api_table *table, JNIEnv *env) {
  java_env = env;
  api_table = table;

  static struct module_abi abi = {
    .api_version = 5,
    .impl = "zogisko_one",
    .preAppSpecialize = pre_app_specialize,
    .postAppSpecialize = post_app_specialize,
    .preServerSpecialize = pre_server_specialize,
    .postServerSpecialize = post_server_specialize
  };

  if (!table->registerModule(table, &abi)) return;
}

static time_t cached_mtime = 0;
char *json_ptr;
const jsmnf_pair *apps; const jsmnf_pair *fields_obj;

char *strndup(const char *restrict str, size_t length) {
  char *restrict copy = malloc(length + 1);
  if (copy == NULL) return NULL;

  memcpy(copy, str, length);
  copy[length] = '\0';

  return copy;
}

void zygisk_companion_entry(int fd) {
  char pkg[128] = {0}; unsigned int f_s = 0; struct stat st;
  const char *filename = "/data/adb/modules/zogisko_one/config.json";

  #undef TAG
  #define TAG "zogisko-one-companion"

  size_t r = read(fd, pkg, sizeof(pkg) - 1);
  if (r <= 0) {
    LOGE("Failed to read the package name");
    goto fd_close;
  }
  LOGD("pkg: %s len(%u)", pkg, (unsigned int)strlen(pkg));

  int c_fd = open(filename, O_RDONLY);
  if (c_fd < 0) {
    PLOGE("Couldn't open config");
    goto close;
  }

  if (fstat(c_fd, &st) != 0) {
    PLOGE("Couldn't stat config");
    goto close;
  }

  /* json is cached and up-to-date, re-use json_ptr */
  if (likely(st.st_mtime == cached_mtime) && likely(apps->v->size > 0)) {
    LOGD("skipped table creation, re-using existing ptr");
    close(c_fd);
    goto skip_creation;
  }
  if(cached_mtime != 0) free(json_ptr); // not first execution, free ptr
  cached_mtime = st.st_mtime;

  json_ptr = malloc(st.st_size);
  if (json_ptr == NULL) {
    PLOGE("Couldn't allocate json_ptr");
    goto close;
  }

  ssize_t bytes_read = read(c_fd, json_ptr, st.st_size);
  if (bytes_read < st.st_size) {
    PLOGE("Failed to read the entire JSON");
    free(json_ptr);
    goto close;
  }

  jsmnf_loader loader;
  jsmnf_table *table = NULL;
  size_t table_len = 0;

  jsmnf_init(&loader);
  if (jsmnf_load_auto(&loader, json_ptr, st.st_size, &table, &table_len) < 0) {
    PLOGE("Failed to parse JSON");
    goto free;
  }

  const jsmnf_pair *root = loader.root;
  fields_obj = jsmnf_find(root, "fields", 6);
  if (!fields_obj) {
    LOGW("Couldn't find the fields object array. Proceeding...");
  }
  const jsmnf_pair *field;

  apps = jsmnf_find(root, "apps", 4);
  if (!apps) {
    LOGE("Error finding apps object");
    goto free;
  }

skip_creation:
  ;
  const jsmnf_pair *app = jsmnf_find(apps, pkg, strlen(pkg));
  /* find requested app for early skip or execution */
  if (!app) {
    LOGI("pkg: %s not targetted, skip", pkg);
    write(fd, &f_s, sizeof(f_s));
    goto close;
  }

  const char *app_name = strndup(json_ptr + app->k->start, (int)(app->k->end - app->k->start));
  LOGD("Matched app: %s, fields=%d", app_name, app->v->size);
  f_s = app->v->size;
  write(fd, &f_s, sizeof(f_s));

  for (unsigned int i = 0; i < f_s; i++) {
    /* current entry in the app's array of objects
    can obtain field, value, name, type, build... */
    const jsmnf_pair *entry = &app->fields[i];

    const jsmnf_pair *field_pair = jsmnf_find(entry, "field", 5);
    if (field_pair && fields_obj) {
      const char *field_value = strndup(json_ptr + field_pair->v->start, (int)(field_pair->v->end - field_pair->v->start));
      LOGV("(%d) field_value: %s", i, field_value);

      field = jsmnf_find(fields_obj, field_value, strlen(field_value));
      if (!field) {
        LOGD("(%d) No entries for %s, fallbacking to per-app config", i, field_value);
        field = entry;
      }
      free((void*)field_value);
    } else {
      LOGD("(%d) Field not set or fields missing", i);
      field = entry;
    }
    const jsmnf_pair *f_name = jsmnf_find(field, "name", 4);
    const jsmnf_pair *f_type = jsmnf_find(field, "type", 4);
    const jsmnf_pair *f_class = jsmnf_find(field, "class", 5);
    const jsmnf_pair *f_value = jsmnf_find(entry, "value", 5);
    if (!f_name || !f_type || !f_class) {
      LOGW("(%d) Missing class, type or name", i);
      continue;
    }
    const char *name = strndup(json_ptr + f_name->v->start, (int)(f_name->v->end - f_name->v->start));
    const char *type = strndup(json_ptr + f_type->v->start, (int)(f_type->v->end - f_type->v->start));
    const char *fclass = strndup(json_ptr + f_class->v->start, (int)(f_class->v->end - f_class->v->start));
    const char *value = strndup(json_ptr + f_value->v->start, (int)(f_value->v->end - f_value->v->start));
    LOGD("app(%d)=%s\nname: %s\ntype: %s\nclass: %s\nvalue: %s", i, app_name, name, type, fclass, value);

    unsigned int r = 0;

    wait:
    /* here we keep waiting till both loops match
    since we do skip invalid fields (missing keys) */
    read(fd, &r, sizeof(r));
    write(fd, &i, sizeof(i));
    LOGD("reconcile r:%d vs i:%d", r, i);
    if(r < i) goto wait;
    read(fd, &r, sizeof(r)); // wait for ready reply

    write_to_fd(fd, name);
    write_to_fd(fd, type);
    write_to_fd(fd, fclass);
    write_to_fd(fd, value);
    LOGD("(%d) finished writing", i);

    free((void*)name); free((void*)type); free((void*)fclass); free((void*)value);
  }
  free((void*)app_name);

close:
  if(c_fd) close(c_fd);
fd_close:
  if(fd) {
    close(fd);
  }
  return;
free:
  close(c_fd);
  free(table);
  free(json_ptr);
  if(fd) {
    write(fd, &f_s, sizeof(f_s));
    close(fd);
  }
  return;
}
