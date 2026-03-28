# shellcheck disable=SC2034

NAME=$(grep_prop name "${TMPDIR}/module.prop")
ID=$(grep_prop id "${TMPDIR}/module.prop")
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

if [ "$ARCH" = "x86" ] || [ "$ARCH" = "x64" ]; then
  rm -r "$MODPATH/zygisk/arm"*
  if [[ "$SUPPORTS_64BIT" == "true" ]]; then
    ui_print "- Keeping x64 libraries"
  else
    rm "$MODPATH/zygisk/x86_64.so"
  fi

  if [[ "$SUPPORTS_32BIT" == "true" ]]; then
    ui_print "- Keeping x86 libraries"
  else
    rm "$MODPATH/zygisk/x86.so"
  fi
else
  rm -r "$MODPATH/zygisk/x86"*
  if [[ "$SUPPORTS_64BIT" == "true" ]]; then
    ui_print "- Keeping arm64 libraries"
  else
    rm "$MODPATH/zygisk/arm64-v8a.so"
  fi

  if [[ "$SUPPORTS_32BIT" == "true" ]]; then
    ui_print "- Keeping arm libraries"
  else
    rm "$MODPATH/zygisk/armeabi-v7a.so"
  fi
fi

if [ -f "/data/adb/modules/${ID}/config.json" ]; then
  ui_print "- Keeping existing config"
  cp "/data/adb/modules/${ID}/config.json" "$MODPATH"
fi

ui_print "- Welcome to $NAME $VERSION"
