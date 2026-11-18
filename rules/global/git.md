## Git

- Run `git fetch` before creating a branch or worktree, and base it on
  `origin/<base>`, not on the local copy of the base branch.
- Commit with the identity configured in the repository. Never author or commit
  as `root` or a machine account; if `user.name`/`user.email` are missing, stop
  and ask.
- Never revert or overwrite changes you did not make.
- Do not put agent session links or session trailers in commit messages,
  merge/pull request descriptions, or comments.
- Commit or push only when asked.
