#!/usr/bin/env bash
set -euo pipefail

SCHEME="${1:-all}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_VALUE="${TARGET:-iphone:clang:13.7:14.0}"

resolve_theos_for_scheme() {
  local scheme="$1"
  local candidates=()

  if [[ -n "${THEOS:-}" ]]; then
    candidates+=("${THEOS}")
  fi
  candidates+=("/root/WeChat_tweak/theos-roothide")
  candidates+=("/opt/theos")

  for dir in "${candidates[@]}"; do
    if [[ -d "$dir" && ( -d "$dir/vendor/mod/${scheme}" || -d "$dir/mod/${scheme}" ) ]]; then
      echo "$dir"
      return 0
    fi
  done

  return 1
}

build_one() {
  local scheme="$1"
  local theos_dir
  local archs_value="${ARCHS:-}"
  local package_arch="${THEOS_PACKAGE_ARCH:-}"

  if [[ -z "$archs_value" ]]; then
    if [[ "$scheme" == "roothide" ]]; then
      archs_value="arm64 arm64e"
    else
      archs_value="arm64"
    fi
  fi

  if [[ -z "$package_arch" && "$scheme" == "roothide" ]]; then
    # roothide 设备常要求 arm64e 包标识；二进制 slice 仍可为 arm64
    package_arch="iphoneos-arm64e"
  fi

  theos_dir="$(resolve_theos_for_scheme "$scheme")" || {
    echo "[error] 未找到支持 ${scheme} 的 Theos，请设置 THEOS 或安装对应工具链。"
    exit 1
  }

  echo "[build] theos=${theos_dir} scheme=${scheme} target=${TARGET_VALUE} archs=${archs_value} package_arch=${package_arch:-auto}"

  local -a make_args
  make_args=(-C "$PROJECT_DIR" clean package TARGET="$TARGET_VALUE" ARCHS="$archs_value")
  if [[ -n "$package_arch" ]]; then
    make_args+=(THEOS_PACKAGE_ARCH="$package_arch")
  fi

  THEOS="$theos_dir" \
  THEOS_PACKAGE_SCHEME="$scheme" \
  make "${make_args[@]}"
}

case "$SCHEME" in
  rootless|roothide)
    build_one "$SCHEME"
    ;;
  all)
    build_one rootless
    build_one roothide
    ;;
  *)
    echo "用法: $0 [rootless|roothide|all]"
    exit 1
    ;;
esac

echo "[done] 构建完成，产物位于: ${PROJECT_DIR}/packages"
