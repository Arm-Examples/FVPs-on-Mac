#!/usr/bin/env python3
"""Replay cdt-gdb-adapter's launch path against a project's launch.json.

Run from the workspace folder of the csolution project:

    python3 <path-to>/FVPs-on-Mac/skills/fvp-debug-setup/verify-launch.py \
        [--config "Arm-FVP@GDB (launch)"] [--gdb arm-none-eabi-gdb]

This is the only verification that proves the setup works, because it exercises
the readiness handshake -- starting the model and attaching GDB by hand skips
exactly the part that breaks (see SKILL.md section 5).

It reproduces the adapter's own rule: with `target.port` set alongside
`serverParameters` the adapter waits `serverStartupDelay` (default 0 ms!) and
connects blind; with `port` blank it waits for `serverPortRegExp` on the
server's stdout. Both are accepted here -- the first is what the FVPs-on-Mac
wrapper needs, the second only works if the model is line-buffered.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("--launch-json", default=".vscode/launch.json")
ap.add_argument("--config", default="Arm-FVP@GDB (launch)")
ap.add_argument("--gdb", default="arm-none-eabi-gdb")
ap.add_argument("--break", dest="breakpoint", default="main",
                help="temporary breakpoint to set if initCommands sets none")
ap.add_argument("--timeout", type=int, default=300, help="seconds to allow gdb")
args = ap.parse_args()

# launch.json is JSONC; strip whole-line // comments, which is all VS Code's own
# generated files and the annotations recommended in SKILL.md use.
raw = re.sub(r"^\s*//.*$", "", open(args.launch_json).read(), flags=re.M)
configs = json.loads(raw)["configurations"]
try:
    cfg = next(c for c in configs if c["name"] == args.config)
except StopIteration:
    sys.exit(f"no launch config named {args.config!r} in {args.launch_json}")

target = cfg["target"]


def expand(s):
    s = s.replace("${workspaceFolder}", os.getcwd())
    return re.sub(
        r"\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}", lambda m: os.environ.get(m.group(1), ""), s
    )


server = expand(target["server"])
params = [expand(str(p)) for p in target.get("serverParameters", [])]
print("spawn:", server, " ".join(params))

if "GDBServer.allow_remote=1" not in params and sys.platform == "darwin":
    print("!! GDBServer.allow_remote=1 is not in serverParameters -- through the runtime's")
    print("   port forwarder the plugin will reset GDB's connection (SKILL.md section 6)")

proc = subprocess.Popen(
    [server] + params, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1
)

port = target.get("port") or None
regexp = target.get("serverPortRegExp")
t0 = time.time()

if port and params:
    delay = target.get("serverStartupDelay", 0) / 1000.0
    print(f"readiness: fixed serverStartupDelay {delay}s (target.port={port})")
    if delay == 0:
        print("!! no serverStartupDelay -- the adapter connects after 0 ms and races the model")
    threading.Thread(
        target=lambda: [sys.stdout.write("  server| " + l) for l in proc.stdout], daemon=True
    ).start()
    time.sleep(delay)
elif regexp:
    print(f"readiness: waiting for {regexp!r} on the server's stdout")
    rx, acc = re.compile(regexp), ""
    timeout = target.get("portDetectionTimeout", 10000) / 1000.0
    for line in proc.stdout:
        sys.stdout.write("  server| " + line)
        acc += line
        m = rx.search(acc)
        if m:
            port = m.group(1)
            break
        if time.time() - t0 > timeout:
            proc.terminate()
            sys.exit(f"serverPortRegExp never matched within {timeout}s")
    else:
        proc.terminate()
        sys.exit("server exited before serverPortRegExp matched")
    print(f"port detected: {port} after {time.time() - t0:.1f}s")
    # Keep draining, so the model never blocks on a full pipe and late output shows.
    threading.Thread(
        target=lambda: [sys.stdout.write("  server| " + l) for l in proc.stdout], daemon=True
    ).start()
else:
    proc.terminate()
    sys.exit("config has neither a usable port nor serverPortRegExp")

cmds = []
if cfg.get("program"):
    cmds += ["-ex", "file " + expand(cfg["program"])]
cmds += ["-ex", f"target remote localhost:{port}"]
init = [ic for ic in cfg.get("initCommands", []) if ic.strip()]
for ic in init:
    cmds += ["-ex", expand(ic)]
# Without a breakpoint `continue` free-runs to the gdb timeout: the model starts
# halted at the reset vector only because of -D, and nothing else stops it.
if not any(re.match(r"\s*(t?break|b)\b", ic) for ic in init):
    cmds += ["-ex", f"tbreak {args.breakpoint}"]
cmds += ["-ex", "continue", "-ex", "bt", "-ex", "detach"]

try:
    r = subprocess.run([cfg.get("gdb", args.gdb), "-q", "-batch"] + cmds,
                       capture_output=True, text=True, timeout=args.timeout)
    gdb_out = (r.stdout + r.stderr).strip()
except subprocess.TimeoutExpired as e:
    gdb_out = (e.stdout or "") + (e.stderr or "")
    gdb_out = (gdb_out.decode() if isinstance(gdb_out, bytes) else gdb_out).strip()
    gdb_out += f"\n!! gdb did not finish within {args.timeout}s"

print("--- gdb ---")
print(gdb_out)

# SIGTERM reaches the wrapper, whose traps stop and remove the container it made.
proc.terminate()
try:
    proc.wait(timeout=30)
except subprocess.TimeoutExpired:
    proc.kill()

runtime = os.environ.get("FVP_RUNTIME")
if not runtime:
    choice_file = Path(__file__).resolve().parents[2] / ".fvp-runtime"
    if choice_file.exists():
        runtime = choice_file.read_text().strip()
    else:
        available = [name for name in ("docker", "container") if shutil.which(name)]
        if len(available) == 1:
            runtime = available[0]
if runtime == "docker":
    ps_cmd = ["docker", "ps", "--format", "{{.Names}} {{.Image}}"]
elif runtime == "container":
    ps_cmd = ["container", "list"]
else:
    sys.exit("set FVP_RUNTIME or run ./build.sh to select Docker or Apple Container")
ps = subprocess.run(ps_cmd, capture_output=True, text=True, check=True).stdout.splitlines()
left = []
for line in ps:
    parts = line.split()
    if len(parts) > 1 and (parts[1].startswith("fvp:") or "/fvp:" in parts[1]):
        left.append(parts[0])
print("containers left after teardown:", ", ".join(left) or "none")

hit = "Temporary breakpoint" in gdb_out or re.search(r"^#0\s", gdb_out, re.M)
print("RESULT:", "pass" if hit and not left else "FAIL")
sys.exit(0 if hit and not left else 1)
