#!/usr/bin/env bash
# Project scaffold — per-workspace agent environment. Sourced by install.sh.

# create_if_missing DEST SRC_TEMPLATE: never overwrites a file the user owns.
create_if_missing() {
    local dest=$1 src=$2 tmp
    if [ -e "$dest" ]; then info "유지: ${dest#"$PROJECT_DIR"/}"; return 0; fi
    tmp=$(mktemp)
    render "$src" >"$tmp"
    write_file "$dest" "$tmp"
    rm -f "$tmp"
    ok "생성: ${dest#"$PROJECT_DIR"/}"
}

merge_claude_project_settings() {
    local dest="$PROJECT_DIR/.claude/settings.json" kit=$1 tmp
    tmp=$(mktemp)
    if [ -f "$dest" ]; then
        jq -s '
            def add_new(a; b): reduce b[] as $x (a; if any(.[]; . == $x) then . else . + [$x] end);
            .[0] as $cur | .[1] as $kit
            | $cur
            | .permissions.allow = add_new($cur.permissions.allow // []; $kit.permissions.allow // [])
            | .hooks.PreToolUse  = add_new($cur.hooks.PreToolUse // []; $kit.hooks.PreToolUse // [])
        ' "$dest" "$kit" >"$tmp" || { warn "$dest JSON 오류 — 건드리지 않음"; rm -f "$tmp"; return 0; }
    else
        cp "$kit" "$tmp"
    fi
    write_file "$dest" "$tmp"
    rm -f "$tmp"
    write_file "$PROJECT_DIR/.claude/hooks/agent-kit-git-guard.sh" "$KIT_ROOT/claude/hooks/agent-kit-git-guard.sh"
    [ "$DRY_RUN" -eq 1 ] || chmod +x "$PROJECT_DIR/.claude/hooks/agent-kit-git-guard.sh"
    ok ".claude/settings.json (git 조회 명령 사전 허용 + 리뷰 ref checkout 차단 hook)"
}

cmd_project() {
    PROJECT_DIR=$1
    [ -n "$PROJECT_DIR" ] || die "사용법: ./install.sh project <dir> [--name NAME] [--repos \"repo:branch ...\"]"
    run mkdir -p "$PROJECT_DIR"
    [ "$DRY_RUN" -eq 1 ] && [ ! -d "$PROJECT_DIR" ] && { info "[dry-run] $PROJECT_DIR 생성 후 스캐폴드"; return 0; }
    PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd)
    export PROJECT_NAME=${PROJECT_NAME:-$(basename "$PROJECT_DIR")}
    step "프로젝트 환경: $PROJECT_DIR (modules: $PROJECT_MODULES)"

    # Project map rows from --repos "name:branch ..."
    local entry repo branch map='' notes=''
    for entry in ${PROJECT_REPOS:-}; do
        repo=${entry%%:*}; branch=${entry#*:}; [ "$branch" = "$entry" ] && branch=main
        map="$map- \`$repo/\`: <역할 설명>. 기본 브랜치 \`$branch\`."$'\n'
        notes="$notes- \`$repo/\`: <아키텍처 메모>"$'\n'
    done
    export PROJECT_MAP=${map:-"- \`<repo>/\`: <역할 설명>. 기본 브랜치 \`<branch>\`."$'\n'}
    export KNOWLEDGE_LAYOUT=${notes:-"- \`<repo>/\`: <아키텍처 메모>"$'\n'}

    create_if_missing "$PROJECT_DIR/AGENTS.md" "$KIT_ROOT/templates/AGENTS.md"
    if [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
        if grep -q '^@AGENTS.md' "$PROJECT_DIR/CLAUDE.md"; then info "유지: CLAUDE.md"
        else
            backup_once "$PROJECT_DIR/CLAUDE.md"
            run sh -c 'printf "\n@AGENTS.md\n" >>"$1"' _ "$PROJECT_DIR/CLAUDE.md"
            ok "CLAUDE.md 끝에 @AGENTS.md 한 줄 추가"
        fi
    else
        create_if_missing "$PROJECT_DIR/CLAUDE.md" "$KIT_ROOT/templates/CLAUDE.md"
    fi

    local doc
    doc=$(mktemp)
    # shellcheck disable=SC2086
    compose_rules modules "$doc" $PROJECT_MODULES
    if upsert_block "$PROJECT_DIR/AGENTS.md" rules "$doc"; then ok "AGENTS.md 규칙 블록 갱신"; fi
    rm -f "$doc"

    if in_list knowledge-base "$PROJECT_MODULES"; then
        create_if_missing "$PROJECT_DIR/agents/AGENTS.md" "$KIT_ROOT/templates/agents/AGENTS.md"
        for entry in ${PROJECT_REPOS:-}; do
            export REPO_NAME=${entry%%:*} REPO_BRANCH=${entry#*:}
            [ "$REPO_BRANCH" = "$entry" ] && REPO_BRANCH=main
            create_if_missing "$PROJECT_DIR/agents/$REPO_NAME/AGENTS.md" "$KIT_ROOT/templates/agents/repo.md"
        done
    fi
    in_list mr-workflow "$PROJECT_MODULES" &&
        create_if_missing "$PROJECT_DIR/agents/workflow-templates.md" "$KIT_ROOT/templates/agents/workflow-templates.md"

    if in_list ci-jenkins "$PROJECT_MODULES"; then
        local s d
        for s in "$KIT_ROOT"/scripts/jenkins/*.sh; do
            d="$PROJECT_DIR/agents/jenkins/scripts/$(basename "$s")"
            # A project keeps its own copy; say so when it no longer matches the kit's.
            if [ -e "$d" ] && [ "$(cksum <"$s")" != "$(cksum <"$d")" ]; then
                warn "agents/jenkins/scripts/$(basename "$s") 가 킷 버전과 다릅니다 — 새 버전을 쓰려면 그 파일을 지우고 다시 실행하세요"
                continue
            fi
            create_if_missing "$d" "$s"
            [ "$DRY_RUN" -eq 1 ] || chmod +x "$d"
        done
    fi

    if has_tool claude && in_list code-review "$PROJECT_MODULES"; then
        merge_claude_project_settings "$KIT_ROOT/claude/project-settings.code-review.json"
    fi

    info "다음: AGENTS.md 의 Project Map 과 agents/ 메모를 실제 내용으로 채우세요."
}
