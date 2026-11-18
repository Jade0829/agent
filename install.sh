#!/usr/bin/env bash
# agent-kit — one-shot AI coding environment for Claude Code and Codex CLI.
set -euo pipefail

if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ] ||
    { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
    echo "bash 4.4 이상이 필요합니다 (현재 ${BASH_VERSION:-?}). macOS: brew install bash" >&2
    exit 1
fi

KIT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
. "$KIT_ROOT/lib/common.sh"
. "$KIT_ROOT/lib/deps.sh"
. "$KIT_ROOT/lib/setup.sh"
. "$KIT_ROOT/lib/project.sh"

usage() {
    cat <<'EOF'
사용법: ./install.sh [명령] [옵션]

명령
  all (기본)        1단계 설치 + 2단계 환경 구축
  deps              1단계만: 패키지 · Node.js · Claude/Codex · MCP 서버 · 플러그인 설치
  setup             2단계만: MCP 등록 · 전역 규칙 · 설정
  project <dir>     프로젝트 작업 공간에 AGENTS.md / CLAUDE.md / agents/ / hook 구성
  doctor            설치 상태 점검

옵션
  --profile NAME    profiles/NAME.env 또는 profiles/local/NAME.env (기본: default)
  --tools "a b"     대상 도구 (기본: 프로필의 TOOLS, 보통 "claude codex")
  --mcp "a b"       설치·등록할 MCP 서버 (프로필의 MCP_SERVERS 대체)
  --modules "a b"   project 명령의 규칙 모듈 (프로필의 PROJECT_MODULES 대체)
  --name NAME       project 명령: 프로젝트 이름
  --repos "r:b ..." project 명령: 저장소와 기본 브랜치 (예: "api:develop web:main")
  -y, --yes         질문하지 않음 (없는 값은 건너뛰고 경고)
  --dry-run         실제로 바꾸지 않고 할 일만 출력
  -h, --help        도움말

비밀값은 ~/.config/agent-kit/secrets.env 에 저장되며, 같은 이름의 환경변수가 있으면 그 값이 우선합니다.
EOF
}

COMMAND=all
PROFILE=default
PROJECT_ARG=''
O_TOOLS='' O_MCP='' O_MODULES=''
O_MCP_SET=0

while [ $# -gt 0 ]; do
    case $1 in
        all | deps | setup | doctor) COMMAND=$1 ;;
        project)
            COMMAND=project
            case ${2:-} in '' | -*) usage >&2; die "project 뒤에 디렉터리를 지정하세요" ;; esac
            PROJECT_ARG=$2; shift ;;
        --profile) PROFILE=${2:?--profile 값 필요}; shift ;;
        --tools) O_TOOLS=${2:?--tools 값 필요}; shift ;;
        --mcp) [ $# -ge 2 ] || die "--mcp 값 필요 (없애려면 --mcp \"\")"; O_MCP=$2; O_MCP_SET=1; shift ;;
        --modules) O_MODULES=${2:?--modules 값 필요}; shift ;;
        --name) export PROJECT_NAME=${2:?--name 값 필요}; shift ;;
        --repos) PROJECT_REPOS=${2:?--repos 값 필요}; shift ;;
        -y | --yes) ASSUME_YES=1 ;;
        --dry-run) DRY_RUN=1 ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; die "알 수 없는 인자: $1" ;;
    esac
    shift
done

load_profile "$PROFILE"
[ -n "$O_TOOLS" ] && TOOLS=$O_TOOLS
[ "$O_MCP_SET" -eq 1 ] && MCP_SERVERS=$O_MCP
[ -n "$O_MODULES" ] && PROJECT_MODULES=$O_MODULES

case $COMMAND in
    all) phase_install; phase_setup ;;
    deps) phase_install ;;
    setup) phase_setup ;;
    project) have jq || die "jq 가 필요합니다 — 먼저 './install.sh deps'"; cmd_project "$PROJECT_ARG" ;;
    doctor) cmd_doctor ;;
esac

[ "$BACKED_UP" -eq 1 ] && info "변경 전 파일 백업: $BACKUP_DIR"

if [ ${#WARNINGS[@]} -gt 0 ]; then
    step "확인 필요 (${#WARNINGS[@]}건)"
    for w in "${WARNINGS[@]}"; do printf '    - %s\n' "$w"; done
fi

case $COMMAND in
    all | setup)
        step "완료 — 남은 일"
        has_tool claude && info "claude        # 첫 실행 시 로그인"
        has_tool codex && info "codex login   # 첫 실행 시 로그인"
        info "./install.sh project <작업공간>   # 프로젝트별 규칙 구성"
        ;;
esac
