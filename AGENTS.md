# Repository agent policy

## GitHub Actions and merge gates

- Use one-shot GitHub status queries by default (for example, `gh pr view` or `gh pr checks`). Do not use indefinite `--watch` commands or repeated polling loops.
- If a required check is still running, record the run ID, head SHA, and current status, then continue independent work. Recheck only when a merge decision requires fresh status, unless the owner explicitly requests otherwise.
- Never cancel a workflow just because it is taking time. Do not report a run as successful until GitHub reports completion and success.
- Before merging, verify the PR head, current base/up-to-date requirement, mergeability, and all required checks. Do not bypass branch protections or required checks.
- If checks are pending or failing, leave the PR open and report the blocker; do not merge early or restart CI merely to monitor it.
