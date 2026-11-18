#!/usr/bin/env bash
# Phase 1 — install everything a blank machine needs. Sourced by install.sh.

detect_pm() {
    if have dnf; then PM=dnf
    elif have yum; then PM=yum
    elif have apt-get; then PM=apt
    elif have brew; then PM=brew
    else PM=none; fi
}

pkg_install() {
    case $PM in
        dnf | yum) as_root "$PM" install -y "$@" ;;
        apt) as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
        brew) run brew install "$@" ;;
        *) die "지원하지 않는 패키지 관리자입니다. 직접 설치하세요: $*" ;;
    esac
}

install_base_packages() {
    step "기본 패키지"
    detect_pm
    local need=() c
    for c in git curl jq tar python3; do have "$c" || need+=("$c"); done
    if [ "$PM" = apt ] && [ ! -f /etc/ssl/certs/ca-certificates.crt ]; then need+=(ca-certificates); fi
    [ "$PM" = brew ] && need=("${need[@]/python3/python}")
    # shellcheck disable=SC2086
    for c in ${EXTRA_PACKAGES:-}; do need+=("$c"); done
    if [ "$PM" = apt ] && [ ${#need[@]} -gt 0 ]; then as_root apt-get update -qq; fi
    if [ ${#need[@]} -eq 0 ]; then ok "이미 설치됨 (git curl jq tar python3)"; return; fi
    info "설치: ${need[*]}"
    pkg_install "${need[@]}"
}

node_ok() {
    have node && [ "$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)" -ge "${NODE_MIN:-20}" ]
}

install_node() {
    step "Node.js"
    if node_ok; then ok "node $(node --version)"; return; fi
    local setup
    setup=$(mktemp)
    case $PM in
        dnf | yum)
            run curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" -o "$setup"
            # EL8/9 ship an old nodejs module stream that shadows the NodeSource package.
            [ "$PM" = dnf ] && { as_root dnf module disable -y nodejs >/dev/null 2>&1 || true; }
            as_root bash "$setup"
            as_root "$PM" install -y nodejs
            ;;
        apt)
            run curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" -o "$setup"
            as_root bash "$setup"
            as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
            ;;
        brew) run brew install node ;;
        *) die "Node.js ${NODE_MIN:-20}+ 를 직접 설치한 뒤 다시 실행하세요" ;;
    esac
    rm -f "$setup"
    [ "$DRY_RUN" -eq 1 ] || node_ok || die "Node.js 설치 실패"
    [ "$DRY_RUN" -eq 1 ] || ok "node $(node --version)"
}

# npm -g without root: fall back to a per-user prefix.
npm_global() {
    local prefix
    prefix=$(npm config get prefix)
    [ -d "$prefix/lib" ] && prefix="$prefix/lib"
    if [ "$(id -u)" -ne 0 ] && [ ! -w "$prefix" ]; then
        backup_once "$HOME/.npmrc"
        run npm config set prefix "$HOME/.local"
        ensure_local_bin_path
    fi
    run npm install -g --no-fund --no-audit "$@"
}

install_clis() {
    step "에이전트 CLI"
    if has_tool claude; then
        if have claude; then ok "claude $(claude --version 2>/dev/null | head -1)"
        else info "Claude Code 설치"; npm_global "@anthropic-ai/claude-code${CLAUDE_CODE_VERSION:+@$CLAUDE_CODE_VERSION}"; fi
    fi
    if has_tool codex; then
        if have codex; then ok "codex $(codex --version 2>/dev/null | head -1)"
        else info "Codex CLI 설치"; npm_global "@openai/codex${CODEX_VERSION:+@$CODEX_VERSION}"; fi
    fi
}

install_mcp_servers() {
    step "MCP 서버 설치"
    [ -n "${MCP_SERVERS// /}" ] || { info "선택된 MCP 없음"; return; }
    local name type pkg repo build dir scope registry ref
    for name in $MCP_SERVERS; do
        type=$(jq -r --arg n "$name" '.[$n].install.type // "none"' "$CATALOG")
        case $type in
            npx)
                pkg=$(jq -r --arg n "$name" '.[$n].install.package' "$CATALOG")
                # Pre-fetch so the first session does not stall on download.
                if run npm cache add "$pkg" >/dev/null 2>&1; then ok "$name (npx $pkg)"
                else warn "$name: $pkg 사전 다운로드 실패 (첫 실행 시 npx 가 다시 시도)"; fi
                ;;
            npm)
                pkg=$(jq -r --arg n "$name" '.[$n].install.package' "$CATALOG")
                scope=$(jq -r --arg n "$name" '.[$n].install.scope // ""' "$CATALOG")
                registry=$(jq -r --arg n "$name" '.[$n].install.registry // ""' "$CATALOG")
                [ -n "$scope" ] && [ -n "$registry" ] && run npm config set "$scope:registry" "$registry"
                if npm_global "$pkg" >/dev/null; then ok "$name (npm -g $pkg)"
                else warn "$name: $pkg 설치 실패"; fi
                ;;
            git)
                repo=$(jq -r --arg n "$name" '.[$n].install.repo' "$CATALOG")
                build=$(jq -r --arg n "$name" '.[$n].install.build // ""' "$CATALOG")
                ref=$(jq -r --arg n "$name" '.[$n].install.ref // ""' "$CATALOG")
                dir="$MCP_HOME/$name"
                if [ -n "$ref" ]; then
                    # Pinned: a tag or commit from the catalog.
                    if [ ! -d "$dir/.git" ]; then
                        run mkdir -p "$MCP_HOME"
                        run git clone -q "$repo" "$dir" || { warn "$name: clone 실패"; continue; }
                    elif [ "$(git -C "$dir" rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
                        # An earlier unpinned install was a depth-1 clone; older refs need full history.
                        run git -C "$dir" fetch -q --unshallow --tags origin || warn "$name: git fetch 실패"
                    else run git -C "$dir" fetch -q --tags origin || warn "$name: git fetch 실패"; fi
                    run git -C "$dir" checkout -q "$ref" || { warn "$name: ref '$ref' 체크아웃 실패"; continue; }
                elif [ -d "$dir/.git" ]; then
                    # Coming back from a pinned (detached) checkout: return to the default branch first.
                    if ! git -C "$dir" symbolic-ref -q HEAD >/dev/null 2>&1; then
                        run git -C "$dir" checkout -q "$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')" ||
                            warn "$name: 기본 브랜치로 돌아가지 못했습니다"
                    fi
                    run git -C "$dir" pull -q --ff-only || warn "$name: git pull 실패 (기존 버전 유지)"
                else run mkdir -p "$MCP_HOME"; run git clone -q --depth 1 "$repo" "$dir" || { warn "$name: clone 실패"; continue; }; fi
                if [ -n "$build" ]; then
                    if run sh -c 'cd "$1" && eval "$2"' _ "$dir" "$build" >/dev/null 2>&1; then ok "$name ($dir)"
                    else warn "$name: 빌드 실패 ($build)"; fi
                else ok "$name ($dir)"; fi
                ;;
            none) ok "$name (설치 불필요)" ;;
            *) warn "$name: 알 수 없는 install.type '$type'" ;;
        esac
    done
}

install_claude_plugins() {
    has_tool claude || return 0
    [ -n "${CLAUDE_PLUGINS// /}" ] || return 0
    step "Claude Code 플러그인"
    local entry plugin source
    for entry in $CLAUDE_PLUGINS; do
        plugin=${entry%%|*}
        source=${entry#*|}
        if run claude plugin install "$plugin" --marketplace "$source" -y >/dev/null 2>&1; then ok "$plugin"
        else warn "플러그인 설치 실패: $plugin ($source) — 로그인 후 'claude plugin install' 로 재시도"; fi
    done
}

phase_install() {
    install_base_packages
    install_node
    install_clis
    if [ "$DRY_RUN" -eq 1 ] && ! have jq; then
        info "[dry-run] jq 설치 뒤에 이어지는 단계: MCP 서버 설치 → 플러그인 → 환경 구축 (jq 가 없어 미리보기 생략)"
        return 0
    fi
    build_catalog
    install_mcp_servers
    install_claude_plugins
}
