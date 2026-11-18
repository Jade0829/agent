# agent-kit

아무것도 없는 장비에서 스크립트 하나로 **Claude Code + Codex CLI** 작업 환경을 만드는 킷입니다.
필요한 패키지와 CLI, MCP 서버를 먼저 전부 설치하고, 그 다음에 규칙·설정을 구성합니다.

```bash
git clone https://github.com/Jade0829/agent.git && cd agent
./install.sh                      # 1단계 설치 → 2단계 환경 구축
./install.sh project ~/work/foo   # 프로젝트 작업 공간 구성
```

## 실행 순서

| 단계 | 내용 |
|---|---|
| 1-1 기본 패키지 | `git curl jq tar python3` + 프로필의 `EXTRA_PACKAGES` (dnf / yum / apt / brew) |
| 1-2 Node.js | 없거나 20 미만이면 NodeSource 에서 설치 |
| 1-3 에이전트 CLI | `claude`, `codex` 가 없으면 npm 으로 설치 |
| 1-4 MCP 서버 | 카탈로그의 설치 방식대로 설치 (`npx` 사전 다운로드 / `npm -g` / `git clone` + 빌드) |
| 1-5 플러그인 | Claude Code 플러그인과 마켓플레이스 |
| 2-1 접속 정보 | MCP 가 요구하는 URL·토큰을 터미널에서 묻고 `~/.config/agent-kit/secrets.env` (600) 에 저장 |
| 2-2 MCP 등록 | Claude(`claude mcp add-json -s user`) 와 Codex(`codex mcp add`) 양쪽에 등록 |
| 2-3 전역 규칙 | `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` 의 관리 블록에 같은 규칙을 기록 |
| 2-4 설정 | `~/.claude/settings.json` 에 기본값 병합 (기존 값이 우선) |

## 명령

```text
./install.sh [all|deps|setup|project <dir>|doctor] [옵션]

--profile NAME     profiles/NAME.env 또는 profiles/local/NAME.env
--tools "a b"      대상 도구 (기본 "claude codex")
--mcp "a b"        설치·등록할 MCP 서버
--modules "a b"    project 명령의 규칙 모듈
--name / --repos   project 명령: 이름, "repo:branch ..." 목록
-y, --yes          질문 없이 진행 (없는 값은 건너뛰고 끝에 경고로 모아 보여줌)
--dry-run          바꾸지 않고 할 일만 출력
```

다시 실행해도 안전합니다.

- 규칙 파일(`CLAUDE.md`, `AGENTS.md`)은 `<!-- agent-kit:begin … -->` 블록 안쪽만 그 자리에서 교체합니다.
  마커 짝이 맞지 않으면 건드리지 않고 경고합니다.
- `project` 는 이미 있는 파일을 덮어쓰지 않습니다. 예외는 킷이 관리하는 세 가지입니다: `AGENTS.md` 의
  규칙 블록, `.claude/settings.json` 에 항목 추가, `.claude/hooks/agent-kit-git-guard.sh`.
  기존 `CLAUDE.md` 에 `@AGENTS.md` 가 없으면 끝에 한 줄을 붙입니다.
- root 가 아닌 계정에서 npm 전역 경로에 쓸 수 없으면 prefix 를 `~/.local` 로 바꾸고(`~/.npmrc`),
  셸 rc 파일에 PATH 한 줄을 추가합니다. 사설 레지스트리를 쓰는 MCP 는 `~/.npmrc` 에 scope 설정을 추가합니다.
- 바꾸기 전 파일은 `~/.local/share/agent-kit/backups/<시각>/<원래 경로>` 에 남깁니다.

## 구성

```text
install.sh          진입점
lib/                deps(1단계) · setup(2단계) · project · 공통 함수
profiles/           default.env, minimal.env, local/(gitignore — 사내 URL·사설 레지스트리)
mcp/catalog.json    MCP 서버 정의: 설치 방법, 실행 명령, 필요한 값
rules/global/       사용자 전역 규칙 (모든 프로젝트 공통)
rules/modules/      프로젝트 규칙 모듈
templates/          프로젝트 AGENTS.md / CLAUDE.md / agents/ 골격
claude/             settings 기본값, git guard hook
scripts/jenkins/    빌드 대기 · 노드 복구 헬퍼
```

### 규칙

| 전역 (`GLOBAL_RULES`) | 내용 |
|---|---|
| `communication` | 응답 언어(`AGENT_LANG`), 용어 |
| `scope` | 승인된 범위까지만 구현, 새로 발견한 건 보고 |
| `evidence` | 검증 후 보고, 기존 이슈·MR 먼저 검색, origin 기준 사실 확인 |
| `git`, `git-signoff` | fetch 후 브랜치, root 커밋 금지, 세션 링크 금지, `-s` |
| `subagents` | 서브에이전트 결과는 파일로 주고받기 |
| `ops-safety` | 라이브 장비에는 합의된 스크립트만, 예약 자원 유지, `--dry-run` 규약 |

| 프로젝트 (`PROJECT_MODULES`) | 내용 |
|---|---|
| `knowledge-base` | `agents/` 지식 베이스 구조 |
| `code-review` | 리뷰는 전용 worktree, head 커밋 기준, 인라인 thread 게시 + git guard hook |
| `mr-workflow` | MR 본문 규칙, 리뷰 반영 후 CI 재검증 순서 |
| `ci-jenkins` | 빌드 번호 확인, 체크아웃 게이트, 대기·노드 복구 헬퍼 |
| `multi-repo` | submodule 커밋 순서, 토픽 브랜치 |

Claude Code 는 `CLAUDE.md` 의 `@AGENTS.md` 로, Codex 는 `AGENTS.md` 를 직접 읽으므로 두 도구가 같은
규칙을 봅니다. hook 은 Claude Code 에만 걸리고, Codex 에서는 같은 내용이 규칙 문장으로 적용됩니다.

## 내 환경에 맞추기

**프로필** — `profiles/default.env` 를 복사해 고칩니다. 공개해도 되는 건 `profiles/<name>.env`,
사내 주소가 들어가는 건 `profiles/local/<name>.env` (커밋되지 않음).

**MCP 추가** — `profiles/local/<name>.mcp.json` 또는 `~/.config/agent-kit/mcp.d/*.json`:

```json
{
  "my-server": {
    "install": { "type": "npm", "package": "@scope/my-mcp", "scope": "@scope", "registry": "https://npm.example.com/" },
    "command": "my-mcp",
    "args": [],
    "env": { "MY_URL": "${MY_URL}", "MY_TOKEN": "${MY_TOKEN}" },
    "vars": {
      "MY_URL": { "prompt": "서버 URL", "default": "https://example.com" },
      "MY_TOKEN": { "prompt": "토큰", "secret": true }
    }
  }
}
```

`install.type` 은 `npx` · `npm` · `git`(`repo`, `build`) · `none`. `${VAR}` 는 환경변수 또는
`secrets.env` 값으로 치환되고, `${MCP_HOME}` 은 git 설치 경로(`~/.local/share/agent-kit/mcp`)입니다.

**규칙 추가** — `rules/global/` 나 `rules/modules/` 에 `.md` 를 만들고 프로필 목록에 이름을 넣습니다.
`{{AGENT_LANG}}` 같은 `{{이름}}` 은 같은 이름의 export 된 변수로 치환됩니다.

**자동 설치 (CI·이미지 빌드)** — 값을 환경변수로 넘기고 `-y`:

```bash
GITLAB_TOKEN=… JENKINS_BASE_URL=… JENKINS_USER=… JENKINS_TOKEN=… ./install.sh -y --mcp "gitlab jenkins"
```

환경변수로 넘긴 값은 그 실행에만 쓰이고 `secrets.env` 에 저장되지 않습니다. 직접 적어 둘 때는
한 줄에 하나씩 `KEY='값'` 형식으로 씁니다.

**git guard hook** — `code-review` 모듈은 Claude Code 에 `git show/diff/log/grep/status`,
`git fetch origin …`, `git worktree add --detach …` 를 사전 허용하고, hook 으로 두 가지를 막습니다:
리뷰 ref(`mr/12`, `pull/3` 등) 를 `checkout`/`switch` 하는 것, 그리고 조회 명령을 쓰기·명령 실행으로
바꾸는 옵션(`--output`, `--upload-pack`, `--ext-diff`, `git grep -O`).

## 알아둘 점

- bash 4.4 이상, jq 1.6 이상이 필요합니다 (macOS 기본 bash 3.2 는 `brew install bash` 후 실행).
- `claude` / `codex` 로그인은 설치 후 직접 해야 합니다.
- Codex 에 MCP 를 등록할 때는 CLI 특성상 토큰이 잠깐 프로세스 인자로 전달됩니다. Claude 는 stdin 으로
  넘기지만, 에이전트 세션 안에서 설치를 돌리면 같은 방식으로 대체됩니다.
- MCP 재등록은 "삭제 후 추가" 라서, 추가가 실패하면 그 서버 등록이 빠진 채로 경고가 남습니다.
- `--dry-run` 은 jq 가 없는 장비에서는 CLI 설치 단계까지만 미리 보여줍니다.
- Jenkins 헬퍼는 `JENKINS_*` 환경변수가 필요합니다: `. ~/.config/agent-kit/secrets.env && <헬퍼>`.
- 토큰은 `~/.claude.json`, `~/.codex/config.toml`, `secrets.env` 에 평문으로 저장됩니다 (각 도구의 기본 방식).
