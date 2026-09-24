import json
import os
import subprocess
import sys

out = sys.argv[1]
version = sys.argv[2]

log = subprocess.run(
    ["git", "log", "-40", "--pretty=%s"], capture_output=True, text=True, check=True
).stdout.splitlines()
changes = [line for line in log if line.split(":")[0] in ("feat", "fix")]
changelog = "\n".join(f"- {line.split(':', 1)[1].strip()}" for line in changes[:15]) or "- First release"

path = os.path.join(out, "depiction", "sileo.json")
data = open(path).read().replace("@VERSION@", version)
data = data.replace('"@CHANGELOG@"', json.dumps(changelog))
json.loads(data)
open(path, "w").write(data)

path = os.path.join(out, "depiction", "index.html")
html = open(path).read().replace("@VERSION@", version)
open(path, "w").write(html)
