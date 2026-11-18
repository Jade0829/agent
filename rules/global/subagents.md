## Subagents

Results between an orchestrator and its subagents travel through files, never
through the in-memory return value or a transcript dump.

- Orchestrator: name the output path in the brief (default
  `{{RESEARCH_DIR}}/<task>.md`) and require "write the full result there as
  markdown; reply with the path and a one-line summary only". When the agent
  finishes, read that file. If no path came back, do not trust the result — ask
  again.
- Subagent: put evidence, details and code citations in the file. The reply is
  `Result file: <path>` plus one line.
- Use an agent type that can write files for any task that must produce one.
