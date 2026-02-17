#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

THEOS_DIR="${THEOS:-/opt/theos}"
TARGET_VALUE="${TARGET:-iphone:clang:13.7:14.0}"
ARCHS_VALUE="${ARCHS:-arm64}"
PACKAGE_VERSION_VALUE="${PACKAGE_VERSION:-1.0.0-local.$(date +%Y%m%d%H%M%S)}"

# 复现这次可注入的关键点：使用新版 ldid
LDID_URL="${LDID_URL:-https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_linux_x86_64}"
UPDATE_THEOS="${UPDATE_THEOS:-1}"
UPDATE_LDID="${UPDATE_LDID:-1}"

tmp_ldid=""
tmp_unpack=""
cleanup() {
  [[ -n "$tmp_ldid" && -f "$tmp_ldid" ]] && rm -f "$tmp_ldid"
  [[ -n "$tmp_unpack" && -d "$tmp_unpack" ]] && rm -rf "$tmp_unpack"
}
trap cleanup EXIT

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[error] missing command: $1"
    exit 1
  }
}

require_cmd git
require_cmd make
require_cmd curl
require_cmd install
require_cmd dpkg-deb
require_cmd python3

if [[ ! -d "$THEOS_DIR/.git" ]]; then
  echo "[error] THEOS dir is not a git repository: $THEOS_DIR"
  echo "        set THEOS=/path/to/theos and retry"
  exit 1
fi

if [[ "$UPDATE_THEOS" == "1" ]]; then
  echo "[step] update theos: $THEOS_DIR"
  git -C "$THEOS_DIR" pull --ff-only
  git -C "$THEOS_DIR" submodule update --init --recursive
fi

LDID_BIN="$THEOS_DIR/toolchain/linux/iphone/bin/ldid"
if [[ "$UPDATE_LDID" == "1" ]]; then
  if [[ ! -x "$LDID_BIN" ]]; then
    echo "[error] ldid binary not found: $LDID_BIN"
    exit 1
  fi
  if [[ ! -w "$LDID_BIN" ]]; then
    echo "[error] no write permission for: $LDID_BIN"
    echo "        run as a user with write access, or pre-upgrade ldid manually"
    exit 1
  fi

  backup="${LDID_BIN}.backup-$(date +%Y%m%d%H%M%S)"
  tmp_ldid="$(mktemp)"

  echo "[step] backup ldid -> $backup"
  cp "$LDID_BIN" "$backup"

  echo "[step] download new ldid"
  curl -L --fail "$LDID_URL" -o "$tmp_ldid"

  echo "[step] install new ldid"
  install -m 0755 "$tmp_ldid" "$LDID_BIN"
fi

echo "[step] build rootless arm64"
THEOS="$THEOS_DIR" make -C "$PROJECT_DIR" clean package \
  THEOS_PACKAGE_SCHEME=rootless \
  ARCHS="$ARCHS_VALUE" \
  TARGET="$TARGET_VALUE" \
  FINALPACKAGE=1 \
  PACKAGE_VERSION="$PACKAGE_VERSION_VALUE"

deb_path="$(ls -1t "$PROJECT_DIR"/packages/com.yourname.wechatkeyboardswitch_"$PACKAGE_VERSION_VALUE"_*.deb 2>/dev/null | head -n 1 || true)"
if [[ -z "$deb_path" ]]; then
  deb_path="$(ls -1t "$PROJECT_DIR"/packages/*.deb | head -n 1)"
fi

echo "[done] deb: $deb_path"

echo "[check] codesign CodeDirectory version"
tmp_unpack="$(mktemp -d)"
dpkg-deb -x "$deb_path" "$tmp_unpack"

python3 - "$tmp_unpack/var/jb/Library/MobileSubstrate/DynamicLibraries/WeChatKeyboardSwitch.dylib" <<'PY'
import pathlib
import struct
import sys

p = pathlib.Path(sys.argv[1])
b = p.read_bytes()
ncmds = struct.unpack_from("<I", b, 16)[0]
off = 32
cs_off = None
cs_size = None
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack_from("<II", b, off)
    if cmd == 0x1D:
        cs_off, cs_size = struct.unpack_from("<II", b, off + 8)
        break
    off += cmdsize

if cs_off is None:
    print("  no LC_CODE_SIGNATURE found")
    sys.exit(0)

sb = b[cs_off:cs_off + cs_size]
_, _, scount = struct.unpack_from(">III", sb, 0)
versions = []
for i in range(scount):
    stype, soff = struct.unpack_from(">II", sb, 12 + i * 8)
    cmagic = struct.unpack_from(">I", sb, soff)[0]
    if cmagic != 0xFADE0C02:
        continue
    values = struct.unpack_from(">IIIIIIIII4B I", sb, soff)
    version = values[2]
    hash_type = values[10]
    versions.append((stype, version, hash_type))

if not versions:
    print("  no CodeDirectory blob found")
else:
    for stype, version, hash_type in versions:
        print(f"  slot={stype} version=0x{version:x} hashType={hash_type}")
PY

echo "[hint] expected stable rootless signature includes version 0x20400"
