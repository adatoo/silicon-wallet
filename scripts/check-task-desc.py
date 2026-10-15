#!/usr/bin/env python3
"""Fail when a task's `desc:` would break `task --list` consumers.

go-task flattens a multi-line desc onto one line, and shell completions split
the task name from its description on "colon followed by two or more spaces".
Either shape turns a Tab completion into the whole description.
"""
import json
import re
import subprocess
import sys

listed = json.loads(
    subprocess.run(["task", "--list-all", "--json"], check=True, capture_output=True, text=True).stdout
)
bad = [
    t["name"]
    for t in listed["tasks"]
    if "\n" in t.get("desc", "") or re.search(r":\s{2,}", t.get("desc", ""))
]
for name in bad:
    print(f"Taskfile.yml: task '{name}' needs a one-line desc with no colon followed by two spaces")
sys.exit(1 if bad else 0)
