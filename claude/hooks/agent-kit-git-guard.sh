#!/usr/bin/env bash
# agent-kit git guard — Claude Code PreToolUse hook for Bash.
# Denies (1) checking out a review ref (MR/PR) in the shared working tree and
# (2) git options that turn a "read" command into a write or a command launch.
# Anything it cannot parse is passed through to the normal permission flow.

cmd=$(jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

deny() {
    jq -cn --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse",
        permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0
}

review_ref='^(refs/)?(remotes/)?([^/]+/)?(mr|pr|pull|merge-requests)/[0-9]'

set -f
while IFS= read -r segment; do
    read -ra tok <<<"$segment"
    i=0
    while [ $i -lt ${#tok[@]} ] && [[ ${tok[$i]} =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do i=$((i + 1)); done
    [ "${tok[$i]:-}" = git ] || continue
    i=$((i + 1))
    # git's own options, some of which take a value
    while [ $i -lt ${#tok[@]} ] && [[ ${tok[$i]} == -* ]]; do
        case ${tok[$i]} in -C | -c | --git-dir | --work-tree | --namespace) i=$((i + 2)) ;; *) i=$((i + 1)) ;; esac
    done
    sub=${tok[$i]:-}
    i=$((i + 1))
    for ((j = i; j < ${#tok[@]}; j++)); do
        t=${tok[$j]}
        t=${t#[\"\']}
        [ "$t" = -- ] && break
        case $t in
            --upload-pack* | --receive-pack* | --exec=* | --output | --output=* | --open-files-in-pager* | --ext-diff)
                deny "agent-kit guard: git option '$t' can write files or launch a command; it is not allowed in auto-approved git calls. Use the plain form of the command." ;;
        esac
        if [ "$sub" = grep ] && [[ $t == -O* ]]; then
            deny "agent-kit guard: 'git grep -O' launches a pager command; use plain 'git grep'."
        fi
        if { [ "$sub" = checkout ] || [ "$sub" = switch ]; } && [[ $t =~ $review_ref ]]; then
            deny "AGENTS.md > Code Review: never checkout a review ref (MR/PR) in a shared working tree — concurrent reviews silently clobber each other and submodule pointers go dirty. Use a throwaway worktree: git worktree add --detach <scratch>/mr-<id> <ref> (clean up with git worktree remove --force). Read-only git show/diff/grep against the ref are fine."
        fi
    done
done < <(printf '%s\n' "$cmd" | sed -E 's/(\&\&|\|\||[;|(){}])/\n/g')
exit 0
