## Multi-Repository Workspace

- Each submodule is an independent repository. Commit product changes inside
  the submodule first; commit the updated pointer in the parent only after the
  submodule commit has been pushed.
- Never work directly on the parent's default branch. Start a topic branch
  named after the work area, tracking the matching submodule branches.
- Do not revert unrelated changes in the parent or in any submodule.
- Cross-repository notes live in the parent under `AGENTS.md` and `agents/`.

```bash
git status --short --branch
git submodule status
git submodule foreach 'git status --short --branch'
```
