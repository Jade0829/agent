#!/usr/bin/env bash
# Shared helpers. Sourced by install.sh — not executable on its own.

CONFIG_HOME="${AGENT_KIT_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/agent-kit}"
DATA_HOME="${AGENT_KIT_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/agent-kit}"
SECRETS_FILE="$CONFIG_HOME/secrets.env"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
export MCP_HOME="$DATA_HOME/mcp"

DRY_RUN=${DRY_RUN:-0}
ASSUME_YES=${ASSUME_YES:-0}
RUN_TS=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$DATA_HOME/backups/$RUN_TS"
BACKED_UP=0
WARNINGS=()

if [ -t 1 ]; then C_B=$'\033[1m' C_G=$'\033[32m' C_Y=$'\033[33m' C_R=$'\033[31m' C_0=$'\033[0m'
else C_B='' C_G='' C_Y='' C_R='' C_0=''; fi

step() { printf '\n%s==> %s%s\n' "$C_B" "$*" "$C_0"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s✓%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '    %s!%s %s\n' "$C_Y" "$C_0" "$*" >&2; WARNINGS+=("$*"); }
die()  { printf '%sERROR:%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# run CMD...: execute, or only print under --dry-run.
run() {
    if [ "$DRY_RUN" -eq 1 ]; then printf '    [dry-run] %s\n' "$*"; return 0; fi
    "$@"
}

as_root() {
    if [ "$(id -u)" -eq 0 ]; then run "$@"
    elif have sudo; then run sudo "$@"
    else die "root 권한이 필요합니다 (sudo 없음): $*"; fi
}

has_tool() { case " $TOOLS " in *" $1 "*) return 0 ;; esac; return 1; }
in_list()  { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

interactive() { [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; }

ensure_local_bin_path() {
    case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
    local rc line='export PATH="$HOME/.local/bin:$PATH"' found=0
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        [ -f "$rc" ] || continue
        found=1
        grep -qF '.local/bin' "$rc" && continue
        backup_once "$rc"
        run sh -c 'printf "\n# agent-kit\n%s\n" "$1" >>"$2"' _ "$line" "$rc"
    done
    [ "$found" -eq 1 ] || run sh -c 'printf "# agent-kit\n%s\n" "$1" >>"$2"' _ "$line" "$HOME/.profile"
}

# backup_once FILE: keep one pre-change copy per run, outside the edited tree
# (so nothing stray lands in a project repository).
backup_once() {
    local f=$1 abs dest
    [ -e "$f" ] || return 0
    [ "$DRY_RUN" -eq 1 ] && return 0
    abs="$(cd "$(dirname "$f")" && pwd -P)/$(basename "$f")"
    dest="$BACKUP_DIR$abs"
    [ -e "$dest" ] && return 0
    # Backups can hold tokens (settings, .npmrc): the tree is owner-only.
    ( umask 077; mkdir -p "$(dirname "$dest")" )
    chmod 700 "$DATA_HOME/backups" "$BACKUP_DIR"
    cp -pL "$f" "$dest"
    BACKED_UP=1
}

# write_file DEST SRC: replace DEST content with SRC, writing through symlinks.
write_file() {
    local dest=$1 src=$2
    if [ "$DRY_RUN" -eq 1 ]; then printf '    [dry-run] write %s\n' "$dest"; return 0; fi
    mkdir -p "$(dirname "$dest")"
    if [ -e "$dest" ] && [ "$(cksum <"$src")" = "$(cksum <"$dest")" ]; then return 0; fi
    backup_once "$dest"
    cat "$src" >"$dest"
}

# render SRC: substitute {{VAR}} with exported environment values (unknown vars stay as-is).
render() {
    jq -Rrsj 'gsub("\\{\\{(?<v>[A-Za-z0-9_]+)\\}\\}"; env[.v] // ("{{" + .v + "}}"))' "$1"
}

# upsert_block FILE ID SRC: replace the managed block ID in place, or append it
# when absent. Content outside the markers is never touched. A file whose
# markers are unbalanced is left alone.
upsert_block() {
    local file=$1 id=$2 src=$3 tmp nb=0 ne=0 lb=0 le=0
    local begin="<!-- agent-kit:begin $id -->" end="<!-- agent-kit:end $id -->"
    [ -r "$src" ] || { warn "$file: 블록 내용 파일을 읽을 수 없어 건드리지 않았습니다"; return 1; }
    if [ -f "$file" ]; then
        # No counts (awk failed) means the markers are unverified: do not go on.
        if ! read -r nb ne lb le < <(awk -v b="$begin" -v e="$end" '
            { l = $0; sub(/[[:space:]]+$/, "", l) }
            l == b { nb++; lb = NR }
            l == e { ne++; le = NR }
            END { print nb + 0, ne + 0, lb + 0, le + 0 }' "$file"); then
            warn "$file: 블록 마커를 확인하지 못해 건드리지 않았습니다"
            return 1
        fi
        if [ "$nb" -ne "$ne" ] || [ "$nb" -gt 1 ] || [ "$lb" -gt "$le" ]; then
            warn "$file: agent-kit '$id' 블록 마커가 짝이 맞지 않아 건드리지 않았습니다 (begin $nb / end $ne)"
            return 1
        fi
    fi
    tmp=$(mktemp)
    awk -v b="$begin" -v e="$end" -v src="$src" '
        function emit(   x, r) {
            print b
            while ((r = (getline x < src)) > 0) print x
            if (r < 0) { failed = 1; exit 2 }
            close(src); print e
        }
        { l = $0; sub(/[[:space:]]+$/, "", l) }
        l == b { emit(); skip = 1; placed = 1; next }
        l == e && skip { skip = 0; next }
        !skip { print; n++; blank = (l ~ /^[[:space:]]*$/) }
        END { if (failed) exit 2; if (!placed) { if (n && !blank) print ""; emit() } }' \
        "$( [ -f "$file" ] && echo "$file" || echo /dev/null )" >"$tmp" && [ -s "$tmp" ] || {
        rm -f "$tmp"
        warn "$file: 블록을 만들지 못해 건드리지 않았습니다"
        return 1
    }
    write_file "$file" "$tmp"
    rm -f "$tmp"
}

# secret_value RAW: the literal value of one KEY=RAW line. Nothing is evaluated:
# quotes are stripped, $(...) and backticks stay plain text.
secret_value() {
    local v=$1
    # Trailing blanks and a CR (CRLF file) are not part of the value.
    v=${v%"${v##*[![:space:]]}"}
    case $v in
        \'*\') v=${v:1:${#v}-2}; v=${v//"'\\''"/"'"} ;;
        \"*\") v=${v:1:${#v}-2}; v=$(printf '%s' "$v" | sed 's/\\\(["\\$`]\)/\1/g') ;;
        *) v=$(printf '%s' "$v" | sed 's/\\\(.\)/\1/g') ;;
    esac
    printf '%s' "$v"
}

# save_var KEY VALUE: persist to the secrets file (mode 600) and export.
# Written as export KEY='value' so the file can also be sourced by a shell.
save_var() {
    local key=$1 value=$2 tmp
    export "$key=$value"
    [ "$DRY_RUN" -eq 1 ] && return 0
    mkdir -p "$CONFIG_HOME"
    ( umask 077
      tmp=$(mktemp "$CONFIG_HOME/.secrets.XXXXXX")
      if [ -f "$SECRETS_FILE" ]; then grep -vE "^(export )?$key=" "$SECRETS_FILE" >"$tmp" || true; fi
      printf "export %s='%s'\n" "$key" "${value//"'"/"'\\''"}" >>"$tmp"
      mv "$tmp" "$SECRETS_FILE" )
    chmod 600 "$SECRETS_FILE"
}

load_profile() {
    local name=$1 f
    # shellcheck disable=SC1091
    . "$KIT_ROOT/profiles/default.env"
    PROFILE_MCP_FILES=("$KIT_ROOT/mcp/catalog.json")
    if [ "$name" != default ]; then
        f=''
        for c in "$KIT_ROOT/profiles/$name.env" "$KIT_ROOT/profiles/local/$name.env"; do
            [ -f "$c" ] && f=$c
        done
        [ -n "$f" ] || die "프로필을 찾을 수 없습니다: $name (profiles/ 또는 profiles/local/)"
        # shellcheck disable=SC1090
        . "$f"
        [ -f "${f%.env}.mcp.json" ] && PROFILE_MCP_FILES+=("${f%.env}.mcp.json")
    fi
    # shellcheck disable=SC1091
    [ -f "$CONFIG_HOME/profile.env" ] && . "$CONFIG_HOME/profile.env"
    for f in "$CONFIG_HOME"/mcp.d/*.json; do [ -f "$f" ] && PROFILE_MCP_FILES+=("$f"); done
    export AGENT_LANG RESEARCH_DIR REVIEW_TAG_MUST REVIEW_TAG_SHOULD
}

# load_secrets: stored MCP values into the environment. Called only by the
# steps that need them, so phase 1 (package, npm and build scripts) runs
# without the stored tokens. Explicit environment wins over stored values;
# within the file the last line for a key wins. Lines are parsed, never
# evaluated.
load_secrets() {
    if [ -f "$SECRETS_FILE" ]; then
        local line key from_file=' '
        while IFS= read -r line; do
            line=${line#export }
            key=${line%%=*}
            case $from_file in
                *" $key "*) ;;
                *) [ -n "${!key:-}" ] && continue ;;
            esac
            export "$key=$(secret_value "${line#*=}")"
            from_file="$from_file$key "
        done < <(grep -E '^(export )?[A-Za-z_][A-Za-z0-9_]*=' "$SECRETS_FILE")
    fi
}

# Merged MCP catalog (later files override earlier ones). Needs jq.
build_catalog() {
    CATALOG=$(mktemp)
    jq -s 'add' "${PROFILE_MCP_FILES[@]}" >"$CATALOG" || die "MCP 카탈로그 JSON 오류"
    local n
    for n in $MCP_SERVERS; do
        jq -e --arg n "$n" 'has($n)' "$CATALOG" >/dev/null || die "MCP '$n' 가 카탈로그에 없습니다"
    done
}
