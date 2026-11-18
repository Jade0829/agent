#!/usr/bin/env bash
# Phase 2 — configure the user-level environment. Sourced by install.sh.

# Ask for (or load) every variable the selected MCP servers need.
collect_mcp_vars() {
    step "MCP 접속 정보"
    local name key secret prompt def value ask=0
    # Decide once, before stdin-independent loops: prompt only on a real terminal.
    if interactive && [ "$DRY_RUN" -eq 0 ]; then ask=1; fi
    for name in $MCP_SERVERS; do
        while IFS=$'\t' read -r -u 3 key secret prompt def; do
            [ -n "$key" ] || continue
            if [ -n "${!key:-}" ]; then export "${key?}"; continue; fi
            value=''
            if [ "$ask" -eq 1 ]; then
                if [ "$secret" = true ]; then
                    read -r -s -p "    [$name] $prompt: " value </dev/tty || true; echo
                else
                    read -r -p "    [$name] $prompt${def:+ [$def]}: " value </dev/tty || true
                fi
            fi
            value=${value:-$def}
            if [ -n "$value" ]; then save_var "$key" "$value"; fi
        done 3< <(jq -r --arg n "$name" '.[$n].vars // {} | to_entries[]
            | [.key, (.value.secret // false | tostring), (.value.prompt // .key), (.value.default // "")]
            | @tsv' "$CATALOG")
    done
    ok "값 저장 위치: $SECRETS_FILE (mode 600, git 에 올라가지 않음)"
}

mcp_missing_vars() {
    local name=$1 key out=''
    while IFS= read -r key; do
        [ -n "${!key:-}" ] || out="$out $key"
    done < <(jq -r --arg n "$name" '.[$n].vars // {} | keys[]' "$CATALOG")
    printf '%s' "${out# }"
}

# Resolved {command,args,env} for one server, ${VAR} expanded from the environment.
mcp_spec() {
    jq -c --arg n "$1" '
        def subst: walk(if type == "string"
            then gsub("\\$\\{(?<v>[A-Za-z0-9_]+)\\}"; env[.v] // "") else . end);
        .[$n] | {command, args: (.args // []), env: (.env // {})} | subst' "$CATALOG"
}

# The user-scope definition Claude Code currently holds for NAME (empty if none).
claude_mcp_current() {
    local cfg="$HOME/.claude.json"
    [ -n "${CLAUDE_CONFIG_DIR:-}" ] && cfg="$CLAUDE_CONFIG_DIR/.claude.json"
    jq -cS --arg n "$1" '.mcpServers[$n] // empty' "$cfg" 2>/dev/null || true
}

claude_mcp_add() {
    # JSON goes through stdin so tokens never appear in the process list.
    # (stdin is refused when run from inside an agent session — fall back to argv.)
    printf '%s' "$2" | claude mcp add-json -s user "$1" - >/dev/null 2>&1 ||
        claude mcp add-json -s user "$1" "$2" 2>&1
}

# redact SPEC TEXT: TEXT with every env value of SPEC masked, for safe logging.
redact() {
    local text=$2 v
    while IFS= read -r v; do
        [ ${#v} -ge 6 ] && text=${text//"$v"/***}
    done < <(jq -r '.env[]' <<<"$1")
    printf '%s' "$text"
}

register_mcp_servers() {
    step "MCP 서버 등록"
    local name missing spec cmd args envflags kv err
    for name in $MCP_SERVERS; do
        missing=$(mcp_missing_vars "$name")
        if [ -n "$missing" ]; then
            warn "$name 등록 건너뜀 — 값 없음: $missing ($SECRETS_FILE 에 넣고 './install.sh setup' 재실행)"
            continue
        fi
        spec=$(mcp_spec "$name")
        if has_tool claude && have claude; then
            if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] claude mcp add-json -s user $name"
            else
                # 'add-json' refuses to overwrite, so the old entry has to go first.
                # Keep it, and put it back if the new one is rejected.
                local cjson old
                cjson=$(jq -cS '. + {type: "stdio"}' <<<"$spec")
                old=$(claude_mcp_current "$name")
                if [ "$old" = "$cjson" ]; then ok "claude: $name (변경 없음)"
                else
                    claude mcp remove -s user "$name" >/dev/null 2>&1 || true
                    if err=$(claude_mcp_add "$name" "$cjson") && [ -n "$(claude_mcp_current "$name")" ]; then ok "claude: $name"
                    else
                        if [ -n "$old" ] && claude_mcp_add "$name" "$old" >/dev/null; then
                            warn "claude: $name 등록 실패, 이전 등록을 복원했습니다 — $(redact "$spec" "${err##*$'\n'}")"
                        else warn "claude: $name 등록 실패 — $(redact "$spec" "${err##*$'\n'}")"; fi
                    fi
                fi
            fi
        fi
        if has_tool codex && have codex; then
            cmd=$(jq -r '.command' <<<"$spec")
            mapfile -t args < <(jq -r '.args[]' <<<"$spec")
            envflags=()
            while IFS= read -r kv; do [ -n "$kv" ] && envflags+=(--env "$kv"); done \
                < <(jq -r '.env | to_entries[] | "\(.key)=\(.value)"' <<<"$spec")
            if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] codex mcp add $name"
            else
                # 'codex mcp add' replaces an existing entry itself, so nothing is removed first.
                if err=$(codex mcp add "$name" "${envflags[@]}" -- "$cmd" "${args[@]}" 2>&1); then ok "codex: $name"
                else warn "codex: $name 등록 실패 (기존 등록은 그대로) — $(redact "$spec" "${err##*$'\n'}")"; fi
            fi
        fi
    done
}

# Concatenate rule files into one rendered document.
compose_rules() {
    local dir=$1 out=$2 name f
    shift 2
    : >"$out"
    for name in "$@"; do
        f="$KIT_ROOT/rules/$dir/$name.md"
        [ -f "$f" ] || { warn "규칙 파일 없음: rules/$dir/$name.md"; continue; }
        [ -s "$out" ] && echo >>"$out"
        render "$f" >>"$out"
    done
}

install_global_rules() {
    step "전역 규칙"
    local doc
    doc=$(mktemp)
    # shellcheck disable=SC2086
    compose_rules global "$doc" $GLOBAL_RULES
    if has_tool claude && upsert_block "$CLAUDE_DIR/CLAUDE.md" global "$doc"; then ok "$CLAUDE_DIR/CLAUDE.md"; fi
    if has_tool codex && upsert_block "$CODEX_DIR/AGENTS.md" global "$doc"; then ok "$CODEX_DIR/AGENTS.md"; fi
    rm -f "$doc"
}

install_claude_settings() {
    has_tool claude || return 0
    step "Claude Code 설정"
    local dest="$CLAUDE_DIR/settings.json" tmp
    tmp=$(mktemp)
    if [ -f "$dest" ]; then
        # Existing user values always win over kit defaults.
        jq -s '.[0] * .[1]' "$KIT_ROOT/claude/settings.base.json" "$dest" >"$tmp" ||
            { warn "$dest 가 올바른 JSON 이 아니라 건드리지 않았습니다"; rm -f "$tmp"; return 0; }
    else
        cp "$KIT_ROOT/claude/settings.base.json" "$tmp"
    fi
    write_file "$dest" "$tmp"
    rm -f "$tmp"
    ok "$dest"
}

phase_setup() {
    if ! have jq; then
        [ "$DRY_RUN" -eq 1 ] && return 0
        die "jq 가 필요합니다 — 먼저 './install.sh deps' 를 실행하세요"
    fi
    jq -n '[1] | walk(.)' >/dev/null 2>&1 || die "jq 1.6 이상이 필요합니다 (현재: $(jq --version 2>&1))"
    load_secrets
    [ -n "${CATALOG:-}" ] || build_catalog
    collect_mcp_vars
    register_mcp_servers
    install_global_rules
    install_claude_settings
}

cmd_doctor() {
    step "상태 점검 (profile: $PROFILE)"
    local c v
    for c in git curl jq python3 node npm claude codex; do
        if have "$c"; then v=$("$c" --version 2>/dev/null | head -1) || true; ok "$c — $v"; else warn "$c 없음"; fi
    done
    build_catalog
    load_secrets
    local name missing
    for name in $MCP_SERVERS; do
        missing=$(mcp_missing_vars "$name")
        if [ -n "$missing" ]; then warn "MCP $name: 값 없음 ($missing)"; else ok "MCP $name: 접속 정보 준비됨"; fi
    done
    for c in "$CLAUDE_DIR/CLAUDE.md" "$CODEX_DIR/AGENTS.md"; do
        if grep -qs 'agent-kit:begin global' "$c"; then ok "전역 규칙: $c"; else warn "전역 규칙 미설치: $c"; fi
    done
    have claude && { info "claude mcp list:"; claude mcp list 2>&1 | sed 's/^/      /' || true; }
    have codex && { info "codex mcp list:"; codex mcp list 2>&1 | sed 's/^/      /' || true; }
    return 0
}
