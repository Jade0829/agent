## Knowledge Base

- `agents/` is the durable, repository-owned knowledge base. It mirrors the
  source layout: `agents/<repo>/AGENTS.md` and nested notes under it.
- Do not infer architecture from README files first. Read the code entry points
  and the matching notes under `agents/`.
- When you learn something that should survive the session (architecture, a
  trap, a workflow), add it under the matching `agents/<repo>/...` path instead
  of growing the root `AGENTS.md`.
- Session memory is for user preferences and feedback. Facts about the code
  belong in `agents/`.
