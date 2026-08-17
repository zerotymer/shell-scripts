#!/bin/sh
# =============================================================================
#  posix-template.sh - POSIX sh 최소 틀
#  대상: dash / ash(busybox) / bash --posix 등 sh 인터프리터 전반
#  용도: 컨테이너 엔트리포인트, initramfs, Alpine 등 bash 가 없는 환경
#  제약: 배열 / [[ ]] / ${var^^} / declare / (( )) / 프로세스 치환 사용 불가
# =============================================================================

set -eu
# pipefail 은 POSIX.1-2024(Issue 8)에 추가됐지만 dash 등 미구현 셸이 있어 조건부 적용
(set -o pipefail 2>/dev/null) && set -o pipefail

SCRIPT_NAME=$(basename -- "$0")
VERSION='1.0.0'
DRY_RUN=0
TMP_DIR=''

log()   { printf '%s [%s] %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$1" "$2" >&2; }
info()  { log INFO  "$1"; }
warn()  { log WARN  "$1"; }
error() { log ERROR "$1"; }
die()   { error "$1"; exit "${2:-1}"; }

cleanup() {
  code=$?
  trap - EXIT INT TERM HUP
  [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ] && rm -rf -- "$TMP_DIR"
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

require_cmd() {
  for cmd in "$@"; do
    command -v -- "$cmd" >/dev/null 2>&1 || die "필수 명령 없음: $cmd"
  done
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] $*"; return 0; fi
  "$@"
}

usage() {
  cat <<EOF
${SCRIPT_NAME} v${VERSION}
사용법: ${SCRIPT_NAME} [-n] [-h] <인자>...
  -n  dry-run
  -h  도움말
EOF
}

# 배열이 없으므로 위치 인자($@)를 그대로 유지하며 shift 로 소비
while [ $# -gt 0 ]; do
  case "$1" in
    -n) DRY_RUN=1; shift ;;
    -h) usage; exit 0 ;;
    --) shift; break ;;
    -*) die "알 수 없는 옵션: $1" 2 ;;
    *)  break ;;
  esac
done

main() {
  require_cmd date whiptail
  [ $# -gt 0 ] || { usage; die "인자가 필요합니다" 2; }

  TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/${SCRIPT_NAME%.*}.XXXXXXXX")

  for item in "$@"; do
    info "처리 중: $item"
    run true "$item"
  done
  info '완료'
}

main "$@"
