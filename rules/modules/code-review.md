## Code Review

### Working tree

Never `git checkout` or `git switch` a review ref (MR/PR) in a shared working
tree or a submodule's main working tree. Working trees are not per-session: a
second review replaces the first reviewer's files with no error, and a parent
repository records the wrong submodule head. Use a throwaway worktree:

```bash
git fetch -q origin "refs/merge-requests/<iid>/head:refs/remotes/mr/<iid>"   # GitLab
git fetch -q origin "pull/<n>/head:refs/remotes/pr/<n>"                       # GitHub
git worktree add --detach <scratch>/mr-<iid> refs/remotes/mr/<iid>
# read, grep, lint and syntax-check inside the worktree
git worktree remove --force <scratch>/mr-<iid>
```

If a working tree was changed anyway, restore the original branch at once,
confirm `git status --porcelain --untracked-files=no` is empty, and say so.

### Reading

Judge the code at the request's head commit (`diff_refs.head_sha` on GitLab).
On a re-review, fetch the new head first.

### Publishing

Publish findings as inline diff comments on the request — one resolvable thread
per line that needs a change. No separate review document, no summary thread.

- Body: {{REVIEW_TAG_MUST}} (must fix) or {{REVIEW_TAG_SHOULD}} (should fix) and
  a one-line title, then the evidence (`file:line` it depends on), the impact,
  and a concrete recommendation.
- One finding per thread, anchored on the line to change. If a fix spans two
  files, post on each and cross-reference.
- If nothing needs a change, post nothing and tell the user.
- Report in chat: the verdict, the posted threads (`file:line` + one line each),
  and what was verified (tests run / not run).

Re-review after new commits: go through each existing thread, reply in it, and
resolve it once the fix is confirmed. Open new threads only for new issues.
