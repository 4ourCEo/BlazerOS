#!/bin/sh
set -eu

# Supervisor adapter, not a second scheduler. 4our OS (or a human operator)
# invokes this worker for one bounded task. State is durable and task commands
# are allowlisted here rather than read from executable JSON. This worker only
# verifies registered work; it never treats a passing test as implementation.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
QUEUE="$ROOT/reports/AUTONOMOUS_TASK_QUEUE.json"
STATE="$ROOT/reports/AUTONOMOUS_WORKER_STATE.json"
LOG_DIR="$ROOT/reports/autonomous-worker"
mkdir -p "$LOG_DIR"

TASK_ID="${1:-next}"
export ROOT QUEUE STATE LOG_DIR TASK_ID

python3 <<'PY'
import json, os, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path

root = Path(os.environ["ROOT"])
queue_path = Path(os.environ["QUEUE"])
state_path = Path(os.environ["STATE"])
log_dir = Path(os.environ["LOG_DIR"])
requested = os.environ["TASK_ID"]

queue = json.loads(queue_path.read_text())
state = json.loads(state_path.read_text()) if state_path.exists() else {
    "schemaVersion": 1, "project": queue["project"], "runs": []
}

tasks = queue["tasks"]
if requested == "next":
    pending = [t for t in tasks if t["status"] == "QUEUED"]
    task = sorted(pending, key=lambda t: (t["priority"], t["id"]))[0] if pending else None
else:
    task = next((t for t in tasks if t["id"] == requested), None)

if task is None:
    print("AUTONOMOUS_WORKER complete no_pending_tasks")
    sys.exit(0)
if task["status"] == "COMPLETED":
    print(f"AUTONOMOUS_WORKER already_completed task={task['id']}")
    sys.exit(0)
if task["status"] == "RUNNING":
    print(f"AUTONOMOUS_WORKER refused_already_running task={task['id']}", file=sys.stderr)
    sys.exit(2)

task["status"] = "RUNNING"
started = datetime.now(timezone.utc).isoformat()
task["startedAt"] = started
queue_path.write_text(json.dumps(queue, indent=2) + "\n")

if task["kind"] != "swift-test":
    task["status"] = "BLOCKED"
    task["failureClassification"] = "unsupported_task_kind"
    queue_path.write_text(json.dumps(queue, indent=2) + "\n")
    sys.exit(2)

command = ["swift", "test"]
if task.get("filter"):
    command += ["--filter", task["filter"]]
log_path = log_dir / f"{task['id']}.log"
with log_path.open("w") as log:
    result = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT)

finished = datetime.now(timezone.utc).isoformat()
task["status"] = "VERIFYING"
task["verificationStartedAt"] = finished
verificationPassed = result.returncode == 0 and "Test run with" in log_path.read_text(errors="replace")
task["finishedAt"] = finished
task["evidence"] = str(log_path.relative_to(root))
task["exitCode"] = result.returncode
task["sourceIdentity"] = subprocess.check_output(
    ["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
task["filesChanged"] = subprocess.check_output(
    ["git", "status", "--short"], cwd=root, text=True).splitlines()
task["failureClassification"] = None if verificationPassed else (
    "verification_failed" if result.returncode == 0 else "command_failed")
task["status"] = "COMPLETED" if verificationPassed else "FAILED"
state["runs"].append({
    "taskID": task["id"], "startedAt": started, "finishedAt": finished,
    "status": task["status"], "exitCode": result.returncode,
    "evidence": task["evidence"], "sourceIdentity": task["sourceIdentity"]
})
queue_path.write_text(json.dumps(queue, indent=2) + "\n")
state_path.write_text(json.dumps(state, indent=2) + "\n")
print(f"AUTONOMOUS_WORKER task={task['id']} status={task['status']} next=invoke_worker_again evidence={task['evidence']}")
sys.exit(result.returncode)
PY
