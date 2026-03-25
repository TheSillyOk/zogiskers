# shellcheck disable=SC2034
SKIPUNZIP=1

NAME=$(grep_prop name "${TMPDIR}/module.prop")
VERSION=$(grep_prop version "${TMPDIR}/module.prop")
ui_print "- Installing $NAME $VERSION"

if [ "$ARCH" != "arm" ] && [ "$ARCH" != "arm64" ] && [ "$ARCH" != "x86" ] && [ "$ARCH" != "x64" ]; then
  abort "! Unsupported platform: $ARCH"
else
  ui_print "- Device platform: $ARCH"
fi

CPU_ABIS_PROP1=$(getprop ro.system.product.cpu.abilist)
CPU_ABIS_PROP2=$(getprop ro.product.cpu.abilist)

if [ "${#CPU_ABIS_PROP2}" -gt "${#CPU_ABIS_PROP1}" ]; then
  CPU_ABIS=$CPU_ABIS_PROP2
else
  CPU_ABIS=$CPU_ABIS_PROP1
fi

SUPPORTS_64BIT=false
SUPPORTS_32BIT=false

if [[ "$CPU_ABIS" == *"x86_64"* || "$CPU_ABIS" == *"arm64-v8a"* ]]; then
  SUPPORTS_64BIT=true
  ui_print "- Device supports 64-bit"
fi

if [[ "$CPU_ABIS" == *"x86"* && "$CPU_ABIS" != "x86_64" || "$CPU_ABIS" == *"armeabi"* ]]; then
  SUPPORTS_32BIT=true
  ui_print "- Device supports 32-bit"
fi

abort_verify() {
  ui_print "***********************************************************"
  ui_print "! $1"
  ui_print "! This zip is incomplete"
  abort    "***********************************************************"
}

extract() {
  local zip="$1"
  local target="$2"
  local dir="$3"
  local junk_paths="${4:-false}"
  local opts="-o"
  local target_path

  [[ "$junk_paths" == true ]] && opts="-oj"

  if [[ "$target" == */ ]]; then
    target_path="$dir/$(basename "$target")"
    unzip $opts "$zip" "${target}*" -d "$dir" >&2
    [[ -d "$target_path" ]] || abort_verify "$target directory doesn't exist"
  else
    target_path="$dir/$(basename "$file")"
    unzip $opts "$zip" "$target" -d "$dir" >&2
    [[ -f "$target_path" || -d "$target_path" ]] || abort_verify "$target file doesn't exist"
  fi
}

ui_print "- Extracting module files"
extract "$ZIPFILE" 'module.prop'     "$MODPATH"

if [ "$ARCH" = "x86" ] || [ "$ARCH" = "x64" ]; then
  if [[ "$SUPPORTS_64BIT" == "true" ]]; then
    ui_print "- Extracting x64 libraries"
    extract "$ZIPFILE" 'zygisk/x64.so' "$MODPATH/zygisk" true
    mv "$MODPATH/zygisk/x64.so" "$MODPATH/zygisk/x86_64.so"
  fi

  if [[ "$SUPPORTS_32BIT" == "true" ]]; then
    ui_print "- Extracting x86 libraries"
    extract "$ZIPFILE" 'zygisk/x86.so' "$MODPATH/zygisk" true
    mv "$MODPATH/zygisk/x86.so" "$MODPATH/zygisk/x86.so"
  fi
else
  if [[ "$SUPPORTS_64BIT" == "true" ]]; then
    ui_print "- Extracting arm64 libraries"
    extract "$ZIPFILE" 'zygisk/arm64-v8a.so' "$MODPATH/zygisk" true
    mv "$MODPATH/zygisk/arm64-v8a.so" "$MODPATH/zygisk/arm64-v8a.so"
  fi

  if [[ "$SUPPORTS_32BIT" == "true" ]]; then
    ui_print "- Extracting arm libraries"
    extract "$ZIPFILE" 'zygisk/armeabi-v7a.so' "$MODPATH/zygisk" true
    mv "$MODPATH/zygisk/armeabi-v7a.so" "$MODPATH/zygisk/armeabi-v7a.so"
  fi
fi

ui_print "- Welcome to $NAME $VERSION"
