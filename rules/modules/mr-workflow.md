## Merge Request Workflow

- Build the description from `agents/workflow-templates.md`, filled with facts
  from the actual diff, issue IDs and test results. Keep it short: what and why,
  per-file changes in a line or two, what is out of scope, test evidence.
- Before updating a description, read the current one and keep lines the user
  added.
- Tick a test checkbox only for something you verified yourself, on a build that
  ran on top of the current target branch. If the target moved ahead, rebase and
  re-run before ticking.
- Order: create the request → wait for review (human or bot) on the current
  head → address every finding → only then trigger CI revalidation. A new push
  restarts the sequence.
- Addressing a finding: check its evidence against the code. If valid, fix it,
  add the regression test it implies, push, and reply in the thread with the
  commit hash and what changed. If not valid, reply with the counter-evidence.
  Do not resolve a reviewer's thread yourself — the reviewer resolves it.
- Squash before merge to the fewest meaningful commits (typically one product
  change and one test change).
