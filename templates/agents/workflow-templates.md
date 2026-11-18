# Workflow Templates

Defaults for merge requests and issues in {{PROJECT_NAME}}. Fill every section
with concrete facts; do not leave placeholders unless a draft was requested.

## Merge Request Defaults

- Project: `<group/project>` (`project_id=<id>`)
- Default target branch: `<branch>`
- Title: `<[TYPE][#issue] one-line symptom>`

### Description Template

```markdown
# 1. 개요

* <이슈 링크 또는 번호> 처리.
  * <핵심 변경 요약>

# 2. 수정 사항

* <파일 또는 범위>
  * <구체 수정 내용>

범위 밖: <이번에 다루지 않는 것>

# 3. 테스트 결과

테스트 환경 : <CI 빌드 링크 / 장비>

- [ ] <검증 항목>
```

## Issue Defaults

- Tracker project: `<project>`
- Priority: `<default>`

### Defect Template

```text
결함 내용 / 테스트 환경(버전·구성) / 재현 방법 / 실제 결과 / 기대 결과 / 참고 자료
```

### Improvement Template

```text
개요 / 현상 / 개선 방향 / 확인 방법 / 기대 결과 / 참고 자료
```
