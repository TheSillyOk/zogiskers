# shellcheck disable=SC2034

NAME=$(grep_prop name "${TMPDIR}/module.prop")
ID=$(grep_prop id "${TMPDIR}/module.prop")
VERSION=$(grep_prop version "${TMPDIR}/module.prop")
ui_print "- Installing $NAME $VERSION"

if [ "$ARCH" != "arm" ] || [ "$ARCH" != "arm64" ]; then
  ARCH_TYPE="arm"
elif [ "$ARCH" != "x86" ] || [ "$ARCH" != "x64" ]; then
  ARCH_TYPE="x86"
else
  abort "! Unsupported platform: $ARCH"
fi

ui_print "- Device platform: $ARCH"

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

rm_if_not_arch() {
  local path="$1"
  local target_arch="$2"
  local bits="$3"

  local supports_bit="SUPPORTS_${bits}BIT"
  eval supports_bit="\$$supports_bit"

  if [[ "$target_arch" != "$ARCH_TYPE" || "${supports_bit}" != "true" ]]; then
    rm "${MODPATH}/${path}"
  else
    ui_print "- Keeping ${path} (${target_arch} ${bits}-bits)"
  fi
}

rm_if_not_arch "zygisk/x86_64.so" "x86" "64"
rm_if_not_arch "zygisk/x86.so" "x86" "32"
rm_if_not_arch "zygisk/arm64-v8a.so" "arm" "64"
rm_if_not_arch "zygisk/armeabi-v7a.so" "arm" "32"

if [ -f "/data/adb/modules/${ID}/config.json" ]; then
  ui_print "- Keeping existing config"
  cp "/data/adb/modules/${ID}/config.json" "$MODPATH"
fi

ui_print "- Welcome to $NAME $VERSION"
