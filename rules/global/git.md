## Git

- Run `git fetch` before creating a branch or worktree, and base it on
  `origin/<base>`, not on the local copy of the base branch.
- Do each separate piece of work (an issue fix, a review, an investigation of
  another branch) in its own worktree: `git worktree add <path> -b <topic>
  origin/<base>`. Leave the main working tree on the branch it was on, so work
  already in progress there is not disturbed. Remove the worktree when the
  work is merged or dropped.
- Commit with the identity configured in the repository. Never author or commit
  as `root` or a machine account; if `user.name`/`user.email` are missing, stop
  and ask.
- Never revert or overwrite changes you did not make.
- Do not put agent session links or session trailers in commit messages,
  merge/pull request descriptions, or comments.
- Commit or push only when asked.
