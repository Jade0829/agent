# agent-kit

아무것도 없는 장비에서 스크립트 하나로 **Claude Code + Codex CLI** 작업 환경을 만드는 킷입니다.
필요한 패키지·CLI·MCP 서버를 먼저 전부 설치하고, 그 다음에 두 도구가 같은 규칙을 보도록 구성합니다.

```bash
git clone https://github.com/Jade0829/agent.git && cd agent
./install.sh                      # 1단계 설치 → 2단계 환경 구축
./install.sh project ~/work/foo   # 프로젝트 작업 공간 구성
```

## 지원 환경

| 환경 | 상태 |
|---|---|
| Rocky Linux 8.10 (dnf), root | 빈 컨테이너에서 전체 설치·재실행 확인 |
| Ubuntu 24.04 (apt), root | 빈 컨테이너에서 전체 설치·재실행 확인 |
| 그 밖의 dnf / yum / apt 배포판 | 같은 코드 경로를 쓰지만 실행해 보지 않음 |
| macOS (Homebrew) | 코드는 있으나 실행해 보지 않음. 기본 bash 3.2 로는 동작하지 않음 |
| root 가 아닌 계정 (sudo, `~/.local` prefix) | 코드는 있으나 실행해 보지 않음 |

| 필요한 것 | 버전 | 없을 때 |
|---|---|---|
| bash | 4.4 이상 | 시작할 때 확인하고 중단 |
| jq | 1.6 이상 | 1단계에서 설치 |
| Node.js | 20 이상 | 1단계에서 NodeSource 22 설치 (`NODE_MAJOR`) |
| Claude Code, Codex CLI | 제한 없음 | 1단계에서 npm 으로 설치 (확인한 버전: 2.1.327, 0.170.0) |
| git, curl, tar, python3 | 제한 없음 | 1단계에서 설치 |

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

## 실행 예시

빈 `rockylinux:8` 컨테이너에서 실제로 돌린 출력입니다. 접속 정보는 가짜 값을 환경변수로 넘겼습니다
(`./install.sh -y --mcp "gitlab jenkins"`). 패키지 관리자와 npm 이 찍는 줄만 `…` 로 줄였습니다.

```text
==> 기본 패키지
    설치: git jq python3
    … (dnf 출력)

==> Node.js
    … (NodeSource 설치 출력)
    ✓ node v22.23.5

==> 에이전트 CLI
    Claude Code 설치
    … (npm 출력)
    Codex CLI 설치
    … (npm 출력)

==> MCP 서버 설치
    ✓ gitlab (npx @zereight/mcp-gitlab)
    ✓ jenkins (/root/.local/share/agent-kit/mcp/jenkins)

==> Claude Code 플러그인
    ✓ oh-my-claudecode
    ✓ andrej-karpathy-skills
    ✓ codex
    ✓ visual-explainer
    ✓ humanizer

==> MCP 접속 정보
    ✓ 값 저장 위치: /root/.config/agent-kit/secrets.env (mode 600, git 에 올라가지 않음)

==> MCP 서버 등록
    ✓ claude: gitlab
    ✓ codex: gitlab
    ✓ claude: jenkins
    ✓ codex: jenkins

==> 전역 규칙
    ✓ /root/.claude/CLAUDE.md
    ✓ /root/.codex/AGENTS.md

==> Claude Code 설정
    ✓ /root/.claude/settings.json
    변경 전 파일 백업: /root/.local/share/agent-kit/backups/20261118-121445

==> 완료 — 남은 일
    claude        # 첫 실행 시 로그인
    codex login   # 첫 실행 시 로그인
    ./install.sh project <작업공간>   # 프로젝트별 규칙 구성
```

같은 명령을 한 번 더 실행하면 패키지·Node.js·CLI 설치는 건너뜁니다. MCP 서버와 플러그인은 매번 최신
상태를 다시 확인합니다(npm 캐시 갱신, `git pull` 과 빌드, 플러그인 설치 명령). 앞부분 발췌:

```text
==> 기본 패키지
    ✓ 이미 설치됨 (git curl jq tar python3)

==> Node.js
    ✓ node v22.23.5

==> 에이전트 CLI
    ✓ claude 2.1.327 (Claude Code)
    ✓ codex codex-cli 0.170.0

…

==> MCP 서버 등록
    ✓ claude: gitlab (변경 없음)
    ✓ codex: gitlab
    ✓ claude: jenkins (변경 없음)
    ✓ codex: jenkins
```

`./install.sh doctor --mcp "gitlab jenkins"` (curl 버전 줄은 뒷부분을, `claude mcp list` 는 플러그인이
자체 등록한 서버 한 줄을 생략했습니다):

```text
==> 상태 점검 (profile: default)
    ✓ git — git version 2.43.7
    ✓ curl — curl 7.61.1 (x86_64-redhat-linux-gnu) …
    ✓ jq — jq-1.6
    ✓ python3 — Python 3.6.8
    ✓ node — v22.23.5
    ✓ npm — 10.9.9
    ✓ claude — 2.1.327 (Claude Code)
    ✓ codex — codex-cli 0.170.0
    ✓ MCP gitlab: 접속 정보 준비됨
    ✓ MCP jenkins: 접속 정보 준비됨
    ✓ 전역 규칙: /root/.claude/CLAUDE.md
    ✓ 전역 규칙: /root/.codex/AGENTS.md
    claude mcp list:
      Checking MCP server health…

      gitlab: npx -y @zereight/mcp-gitlab - ✔ Connected
      jenkins: node /root/.local/share/agent-kit/mcp/jenkins/build/index.js - ✔ Connected
    codex mcp list:
      Name     Command  Args                                                     Env                                                         Cwd  Status   Auth
      gitlab   npx      -y @zereight/mcp-gitlab                                  GITLAB_API_URL=*****, GITLAB_PERSONAL_ACCESS_TOKEN=*****    -    enabled  Unsupported
      jenkins  node     /root/.local/share/agent-kit/mcp/jenkins/build/index.js  JENKINS_TOKEN=*****, JENKINS_URL=*****, JENKINS_USER=*****  -    enabled  Unsupported
```

`✔ Connected` 는 MCP 서버 프로세스가 떴다는 뜻입니다. 가짜 토큰으로 돌린 것이라 실제 GitLab·Jenkins
호출이 되는지는 이 출력으로 알 수 없습니다.

## 왜 이렇게 만들었나

회사에는 프로젝트가 여러 개이고 개발 환경도 하나가 아닌데, 에이전트 설정과 규칙은 특정 제품의 개발
서버 한 곳에 몰려 있었습니다. 다른 프로젝트를 맡거나 그 개발 환경이 사라졌을 때 이전 환경을 손쉽게
다시 구성하려고 이 킷을 만들었습니다.

**설치(1단계)와 구성(2단계)을 나눴습니다.** 두 단계는 필요한 것이 다릅니다. 1단계는 네트워크와
패키지 설치 권한이 필요하지만 비밀값은 쓰지 않고, 저장된 `secrets.env` 도 읽지 않습니다. 2단계는 토큰이 필요하지만 홈 디렉터리의 설정
파일만 고칩니다. 그래서 `deps` 는 이미지 빌드처럼 토큰이 없는 곳에서 돌릴 수 있고, `setup` 은 토큰을
바꾸거나 규칙을 고친 뒤 설치를 반복하지 않고 다시 돌릴 수 있습니다. 2단계가 쓰는 도구(jq, 두 CLI)는
전부 1단계가 설치하므로 순서는 고정입니다.

**규칙을 전역과 프로젝트 모듈로 나눴습니다.** 전역 규칙(`rules/global/`)은 어떤 저장소에서든 맞는
행동 규칙입니다(응답 언어, 승인 범위, 검증, git 기본). 모든 세션에 실리므로 짧게 유지합니다. 프로젝트
모듈(`rules/modules/`)은 그 도구나 구조가 있을 때만 의미가 있습니다(Jenkins, MR 워크플로, submodule).
Jenkins 가 없는 프로젝트에 Jenkins 절차를 싣지 않도록 `--modules` 나 프로필로 고릅니다.

**규칙 파일을 통째로 덮어쓰지 않고 관리 블록만 교체합니다.** `CLAUDE.md` 와 `AGENTS.md` 는 사용자가
직접 쓰는 파일이고 다른 도구도 여기에 줄을 추가합니다. 킷은 `<!-- agent-kit:begin … -->` 과
`<!-- agent-kit:end … -->` 사이만 자기 것으로 보고 그 자리에서 바꿉니다. 그래서 몇 번을 다시 실행해도
블록 밖 내용과 블록 위치가 그대로입니다. 마커 짝이 맞지 않으면 어디까지가 킷의 것인지 알 수 없으므로
고치지 않고 경고만 합니다.

**서브에이전트 결과를 파일로 주고받게 했습니다.** `rules/global/subagents.md` 는 오케스트레이터가
결과 경로를 지정하고, 서브에이전트는 근거와 상세를 그 파일에 쓰고, 답으로는 경로와 한 줄 요약만
돌려주게 합니다. 경로가 돌아오지 않으면 결과를 믿지 않고 다시 요청합니다. API 통신이 끊기거나
네트워크 문제가 생기면, 서브에이전트는 작업을 마쳤다고 보고하는데 메인 세션이 받은 결과는 없는 경우가
많았기 때문입니다. 결과가 파일에 있으면 전달이 끊겨도 메인 세션이 그 파일을 읽으면 됩니다.

**Claude Code 에는 hook 으로 강제하고, Codex 에는 규칙 문장으로만 적용됩니다.** `code-review` 모듈의
"리뷰 ref 를 공유 작업 트리에 checkout 하지 않는다" 는 규칙은 두 도구의 `AGENTS.md` 에 똑같이 들어갑니다.
Claude Code 에서는 여기에 더해 PreToolUse hook(`.claude/hooks/agent-kit-git-guard.sh`)이 그 명령을 실행
전에 거부합니다. 킷은 Codex 쪽에는 같은 장치를 설치하지 않으므로, Codex 에서는 모델이 규칙을 따르는
것에 의존합니다. 지켜지지 않으면 곤란한 규칙일수록 이 차이를 알고 써야 합니다.

별도 worktree 와 원격 기준을 규칙으로 둔 이유는 두 가지입니다. 리뷰든 특정 이슈 처리든 별도 worktree
에서 해야 메인 작업 트리에서 진행하던 흐름이 깨지지 않습니다. 그리고 로컬 사본이 아니라 원격 기준으로
읽어야 정확하고 최신인 내용으로 작업할 수 있습니다. 그래서 전역 규칙도 작업마다 별도 worktree 를 쓰고,
브랜치·worktree 를 만들기 전에 `git fetch` 해서 `origin/<base>` 를 기준으로 삼게 합니다
(`rules/global/git.md`, `rules/global/evidence.md`). 이 전역 규칙은 hook 없이 문장으로만 적용됩니다.

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

## 재실행과 백업

다시 실행해도 안전합니다.

- 규칙 파일(`CLAUDE.md`, `AGENTS.md`)은 `<!-- agent-kit:begin … -->` 블록 안쪽만 그 자리에서 교체합니다.
  마커 짝이 맞지 않으면 건드리지 않고 경고합니다.
- `project` 는 이미 있는 파일을 덮어쓰지 않습니다. 예외는 킷이 관리하는 세 가지입니다: `AGENTS.md` 의
  규칙 블록, `.claude/settings.json` 에 항목 추가, `.claude/hooks/agent-kit-git-guard.sh`.
  기존 `CLAUDE.md` 에 `@AGENTS.md` 가 없으면 끝에 한 줄을 붙입니다. 프로젝트에 복사된 Jenkins 헬퍼가
  킷의 것과 달라졌으면 덮어쓰지 않고 경고만 합니다.
- Claude 쪽 MCP 는 정의가 같으면 다시 등록하지 않고, 정의가 바뀌었는데 새 등록이 거부되면 이전 등록을
  되돌려 놓습니다. Codex 쪽은 매번 같은 정의로 덮어쓰며, 실패해도 기존 등록을 먼저 지우지 않으므로
  그대로 남습니다.
- root 가 아닌 계정에서 npm 전역 경로에 쓸 수 없으면 prefix 를 `~/.local` 로 바꾸고(`~/.npmrc`),
  셸 rc 파일에 PATH 한 줄을 추가합니다. 사설 레지스트리를 쓰는 MCP 는 `~/.npmrc` 에 scope 설정을 추가합니다.
- 킷이 파일을 고치기 전의 내용은 `~/.local/share/agent-kit/backups/<시각>/<원래 절대 경로>` 에 남습니다.
  이 폴더는 소유자만 읽을 수 있습니다(700).

### 백업에서 복원

```bash
ls ~/.local/share/agent-kit/backups/                  # 실행 시각별 폴더
B=~/.local/share/agent-kit/backups/<시각>
find "$B" -type f                                      # 그 실행에서 바뀌기 전 파일들
cp -p "$B$HOME/.claude/CLAUDE.md" ~/.claude/CLAUDE.md  # 원래 경로가 폴더 구조로 들어 있음
```

`~/.claude` 같은 폴더가 심볼릭 링크이면 백업은 링크가 가리키는 실제 경로 아래에 들어갑니다. 그럴 때는
`find` 가 보여 주는 경로를 그대로 쓰세요.

백업 대상은 킷이 직접 고친 파일입니다. MCP 등록은 각 CLI 가 자기 설정 파일(`~/.claude.json`,
`~/.codex/config.toml`)에 쓰므로 백업에 없고, 되돌릴 때는 CLI 로 지웁니다.

```bash
claude mcp remove -s user <이름>
codex mcp remove <이름>
```

규칙만 걷어내려면 `CLAUDE.md` / `AGENTS.md` 에서 두 마커와 그 사이를 지우면 됩니다.

## 구성

```text
install.sh          진입점
lib/                deps(1단계) · setup(2단계) · project · 공통 함수
profiles/           default.env, minimal.env, local/(gitignore — 공개하지 않을 주소·사설 레지스트리)
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
| `git`, `git-signoff` | fetch 후 `origin` 기준 브랜치, 작업별 worktree, root 커밋 금지, 세션 링크 금지, `-s` |
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
규칙을 봅니다.

## 내 환경에 맞추기

**프로필** — `profiles/default.env` 를 복사해 고칩니다. 공개해도 되는 건 `profiles/<name>.env`,
공개하지 않을 주소가 들어가는 건 `profiles/local/<name>.env` (커밋되지 않음).

**버전 고정** — 기본은 최신 버전을 설치합니다. 고정하려면:

| 대상 | 방법 |
|---|---|
| Node.js | 프로필의 `NODE_MAJOR` |
| Claude Code, Codex | 프로필의 `CLAUDE_CODE_VERSION`, `CODEX_VERSION` |
| git 으로 설치하는 MCP | 카탈로그 항목의 `install.ref` (태그 또는 커밋) |
| npx / npm 으로 설치하는 MCP | 카탈로그 항목의 패키지 이름을 `@scope/name@1.2.3` 으로 (`npx` 는 `args` 에도 같은 이름) |

`CLAUDE_CODE_VERSION`, `CODEX_VERSION` 에 `2.1.300` 같은 정확한 버전을 적으면, CLI 가 없을 때는 그
버전을 설치하고 이미 있는데 버전이 다르면 그 버전으로 다시 설치합니다. 같은 프로필로 다시 실행하면
버전이 이미 맞으므로 아무것도 하지 않습니다. 비워 두면 없을 때만 최신을 설치하고 설치된 CLI 는 건드리지
않습니다. `latest` 같은 태그는 비교할 수 없어서 새로 설치할 때만 쓰입니다. 설치는 npm 전역으로 하므로,
같은 CLI 가 다른 방식으로도 설치돼 있어 PATH 에서 앞서면 버전이 바뀌지 않고 경고가 나옵니다.

NodeSource 설치 스크립트 자체와 플러그인 마켓플레이스는 고정하지 않습니다.

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

`install.type` 은 `npx` · `npm` · `git`(`repo`, `build`, 선택 `ref`) · `none`. `${VAR}` 는 환경변수 또는
`secrets.env` 값으로 치환되고, `${MCP_HOME}` 은 git 설치 경로(`~/.local/share/agent-kit/mcp`)입니다.
카탈로그의 `build` 는 설치 중에 셸 명령으로 실행됩니다. 카탈로그 파일은 설치 스크립트와 같은 수준으로
신뢰하는 입력이므로, 출처를 모르는 카탈로그는 내용을 읽어 본 뒤에 쓰세요.

**규칙 추가** — `rules/global/` 나 `rules/modules/` 에 `.md` 를 만들고 프로필 목록에 이름을 넣습니다.
`{{AGENT_LANG}}` 같은 `{{이름}}` 은 같은 이름의 export 된 변수로 치환됩니다.

**자동 설치 (CI·이미지 빌드)** — 값을 환경변수로 넘기고 `-y`:

```bash
GITLAB_TOKEN=… JENKINS_BASE_URL=https://jenkins.example.com JENKINS_USER=… JENKINS_TOKEN=… \
  ./install.sh -y --mcp "gitlab jenkins"
```

환경변수로 넘긴 값은 그 실행에만 쓰이고 `secrets.env` 에 저장되지 않습니다.

**secrets.env 형식** — 한 줄에 하나씩 `export KEY='값'` 입니다. `export` 가 없는 줄도 킷은 읽지만,
Jenkins 헬퍼처럼 이 파일을 셸에서 불러 쓰는 경우에는 `export` 가 있어야 값이 전달됩니다. 킷은 이 파일을
셸로 실행하지 않고 글자 그대로 읽으므로 값 안의 `$(…)` 나 백틱은 실행되지 않습니다. 작은따옴표로
감싸 두면 셸에서 `. ~/.config/agent-kit/secrets.env` 로 읽을 때도 같은 값이 됩니다.

**git guard hook** — `code-review` 모듈은 Claude Code 에 `git show/diff/log/grep/status`,
`git fetch origin …`, `git worktree add --detach …` 를 사전 허용하고, hook 으로 두 가지를 막습니다:
리뷰 ref(`mr/12`, `pull/3` 등) 를 `checkout`/`switch` 하는 것, 그리고 조회 명령을 쓰기·명령 실행으로
바꾸는 옵션(`--output`, `--upload-pack`, `--ext-diff`, `git grep -O`).

**Jenkins 헬퍼** — `ci-jenkins` 모듈이 `agents/jenkins/scripts/` 에 복사합니다. `JENKINS_BASE_URL`,
`JENKINS_USER`, `JENKINS_TOKEN` 환경변수가 필요합니다(`. ~/.config/agent-kit/secrets.env && <헬퍼>`).

| 스크립트 | 동작 | 종료 코드 |
|---|---|---|
| `jenkins_wait_build.sh <job> <build>` | 빌드가 끝날 때까지 대기. 폴더 안의 잡은 `folder/job` | 0 성공, 1 실패·중단, 124 시간 초과, 64 사용법 오류 |
| `jenkins_wait_build.sh` | `…_register.sh` 로 등록한 빌드를 모두 대기 | 위와 같음 (하나라도 실패하면 1) |
| `jenkins_node_online.sh [node]` | "임시 오프라인" 표시가 있는 노드만 온라인으로 되돌림 | 0 온라인, 1 그 외, 64 사용법 오류 |

124 는 시간 안에 상태를 한 번도 읽지 못한 경우(잡 이름 오타, Jenkins 접속 불가)에도 나옵니다. 그래서
1 은 항상 "빌드가 끝났고 성공이 아니다" 를 뜻합니다. 등록 대기에서 빌드마다 시간이 다르면 가장 짧은
확인 간격과 가장 긴 제한 시간을 씁니다.

노드 상태를 읽지 못했거나 에이전트 연결이 끊긴 노드에는 아무 요청도 보내지 않습니다. 토큰은 curl 의
인자가 아니라 표준 입력으로 전달합니다. 이 헬퍼들은 모의 서버로만 확인했고 실제 Jenkins 에서는
확인하지 않았습니다.

## 알아둘 점

- 카탈로그의 `build` 명령은 설치 중에 셸에서 그대로 실행됩니다. `npm`·`npx` 로 설치하는 MCP 도 패키지의
  설치 스크립트를 실행합니다. 킷과 함께 온 `mcp/catalog.json` 이나 직접 작성한 카탈로그처럼 신뢰할 수
  있는 것만 쓰고, 받은 카탈로그는 `build`, `repo`, `package` 를 읽어 본 뒤에 쓰세요.
- `claude` / `codex` 로그인은 설치 후 직접 해야 합니다.
- Codex 에 MCP 를 등록할 때는 CLI 특성상 토큰이 잠깐 프로세스 인자로 전달됩니다. Claude 는 stdin 으로
  넘기지만, 에이전트 세션 안에서 설치를 돌리면 같은 방식으로 대체됩니다.
- 토큰은 `~/.claude.json`, `~/.codex/config.toml`, `secrets.env` 에 평문으로 저장됩니다 (각 도구의 기본 방식).
- `--dry-run` 은 jq 가 없는 장비에서는 CLI 설치 단계까지만 미리 보여줍니다.

## 라이선스

[MIT](LICENSE)
