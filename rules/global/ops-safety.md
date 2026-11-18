## Operations

- On a live or shared machine, upload only the script that was agreed for the
  task. Never sync or overwrite installed product code on your own judgment; if
  something there looks broken, report it and leave it.
- A shared resource the user reserved (CI node, test cluster, lock) stays
  reserved until the user says to release it.
- Operational scripts you write act by default and simulate only under
  `--dry-run`. Do not design them the other way round (`--commit` opt-in).
- Keep credentials out of files that get committed and out of anything you
  publish; read them from the environment or a local secrets file.
