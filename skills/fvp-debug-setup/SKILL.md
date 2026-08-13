---
name: fvp-debug-setup
description: Wire the CMSIS Solution extension's Run/Debug buttons to an Arm FVP running in the FVPs-on-Mac Docker wrapper, using the model's built-in GDBServer plugin (Fast Models 11.32.23+). Covers the csolution `debugger: name: Arm-FVP` node, the AVH_FVP_PLUGINS handover into the container, the launch-config readiness handshake that otherwise makes GDB connect before the model is listening, and UART port publishing. Use when someone wants to debug firmware on a Corstone FVP from VS Code on macOS, migrate off fvp-gdb/Iris, or map the CMSIS view buttons to an FVP in a csolution project.
---

# FVP debugging via the model's own GDBServer plugin

Goal: make the CMSIS Solution view's **Load & Debug** and **Run** buttons work
end-to-end against an FVP, with no external GDB bridge, on a macOS host where
the model runs inside the FVPs-on-Mac Docker wrapper.

Since **Fast Models 11.32.23** the release ships `plugins/GDBServer.so`
(`.dll` on Windows), so the model *is* the GDB server. `fvp-gdb`, Iris and the
whole `--iris-server` detour are obsolete — do not reintroduce them. If the
project still has `start-fvp-gdb.sh` / `stop-fvp-gdb.sh` / `tail-fvp-log.sh`
and a `.vscode.d/tasks.json` overriding `CMSIS Load` / `CMSIS Run`, delete them
as part of this migration.

This document assumes the wrapper from this repository. Everything in §2, §3
and §5 is host-independent and applies equally to a native Linux or Windows
model; §1, §4 and §6 are where the wrapper shows through.

## 1. Verify prerequisites

**The wrapper is built.** `./build.sh` has run, `bin/` contains the model
symlinks, and `bin/` is on `PATH`. Check with:

```sh
FVP_Corstone_SSE-320 --version
```

**Docker is running** (`docker info`), because Arm publishes no macOS build of
the model — the wrapper is not a convenience, it is the only way to run it here.

**GDB.** `arm-none-eabi-gdb` must resolve on the host. It runs natively on
macOS; only the model lives in the container.

**Arm license.** The FVP needs an activated user-based license in `~/.armlm`.
That directory is mounted into the container and `ARMLM_CACHED_LICENSES_LOCATION`
points at it, so the license activated on the host is reused. The container also
runs as the host user name and uid — the license is bound to the account that
activated it, otherwise the model aborts with
`Fatal: license error: The license found is assigned to another user.`

**The plugin path handover.** Export, in the environment VS Code inherits:

```sh
export AVH_FVP_PLUGINS=/opt/avh-fvp/plugins
```

That is a path *inside the container*, deliberately. VS Code expands
`${env:AVH_FVP_PLUGINS}` in the macOS process, and the expanded string is
forwarded verbatim as an FVP argument, where it becomes valid. The image's own
`ENV AVH_FVP_PLUGINS` cannot help — it is not visible to the macOS process doing
the expansion. If the variable is unset, VS Code expands it to the empty string
and the model is asked for `/GDBServer.so`.

Note VS Code launched from Finder, the Dock or Spotlight does **not** inherit
your shell profile. Either launch it from a terminal that has the export, or set
the variable through `launchctl setenv`.

**Disable any Fast Models artifact in the project's `vcpkg-configuration.json`.**
`arm:models/arm/avh-fvp` has demands for `windows and x64`, `linux and x64`,
`linux and arm64` — **no darwin** — so on macOS `vcpkg activate` silently
installs nothing (the artifact dir ends up containing only `artifact.json`), but
it does overwrite `AVH_FVP_PLUGINS` with a path that does not exist.

## 2. The plugin's contract (verified against 11.32.23)

`FVP_<model> --plugin <path>/GDBServer.so --list-params` gives exactly six
parameters:

| Parameter | Default | Note |
|---|---|---|
| `GDBServer.port` | `10000` | the extension passes 3333 |
| `GDBServer.allow_remote` | `0` | **required behind Docker port forwarding** |
| `GDBServer.core_name` | `''` | empty = plugin picks a core |
| `GDBServer.list_cores` | `0` | |
| `GDBServer.shutdown_on_disconnect` | `0` | |
| `GDBServer.verbose_logging` | `0` | |

Two behaviours matter more than the parameters:

- **`-D` / `--allow-debug-plugin` is what makes the model start halted at the
  reset vector.** With the plugin but without `-D` the model opens the port *and
  free-runs to completion* — a `tbreak main` would never fire. With `-D` it
  waits, and GDB attaches at `Reset_Handler`.
- **RSP detach does not resume the target.** After `detach` the core stays
  halted wherever it was, and `monitor help` lists only logging commands — there
  is no resume. So a "Run" action cannot resume a halted debug instance; it must
  start its own free-running model (no plugin, no `-D`).

On startup the plugin prints, on the model's stdout:

```
GDBServer: Debug core: component.Corstone_SSE_320_Main.mps4_board.subsystem.cpu0
GDBServer: Listening address="0.0.0.0" port=3333
```

## 3. How the CMSIS Solution extension maps its buttons

Verified against `arm.cmsis-csolution` **1.70.0**; the debug adapter is
`gdbtarget` from `eclipse-cdt.cdt-gdb-vscode` (2.9.1).

- The **debug button** starts the launch config by **name**, rendered from the
  active adapter template. For `Arm-FVP` that is `Arm-FVP@GDB (launch)`; the
  attach button starts `Arm-FVP@GDB (attach)`.
- The **run button** runs the task `CMSIS Load+Run`; the standalone buttons run
  `CMSIS Load` / `CMSIS Run` / `CMSIS Erase`.
- On regeneration the extension rewrites every `CMSIS *` task and every launch
  config carrying `"cmsis": {"updateConfiguration": "auto"}`, and *removes* auto
  configs that are not in the generated set. `"manual"` survives both.
  Regeneration also fires on a plain file-watch of the csolution yml — useful
  for testing: `touch <name>.csolution.yml`, wait, re-read `.vscode/launch.json`.

**`templates/debug/FVP.adapter.json` in the extension already does most of the
right thing** — read it (`~/.vscode/extensions/arm.cmsis-csolution-*/templates/debug/`)
rather than reinventing it. It generates `Arm-FVP@GDB (launch)` as a
`request: "launch"` config whose `target.server` is the model and whose
`serverParameters` are
`-D --plugin ${env:AVH_FVP_PLUGINS}/GDBServer.so -C GDBServer.port=<port> <config-file> <args> -a <image>`,
plus `CMSIS Load` (echo no-op — the model loads the image at launch),
`CMSIS Run` (the bare model, free-running) and `CMSIS Load+Run`. That is why the
right move is to switch the adapter rather than hijack the pyOCD task names;
older notes claiming `Arm-FVP` generates no launch config are out of date.

What it does **not** do is set a startup delay, `GDBServer.allow_remote`, or the
UART port — §5 and §6.

## 4. Set the csolution debugger node

Under the FVP target-type's `target-set:`:

```yaml
debugger:
  name: Arm-FVP
  model: FVP_Corstone_SSE-320                 # resolved from this repo's bin/ on PATH
  config-file: board/Corstone-320/fvp_config.txt
```

If `bin/` is not on the `PATH` VS Code inherits, give an absolute path to the
wrapper instead — `model: /Users/<you>/FVPs-on-Mac/bin/FVP_Corstone_SSE-320`.
The symlinks resolve `fvprc` through the real script location, so they work from
any working directory.

The yml-node names come from `debug-adapters.yml` (`model`, `config-file`,
`args`) — the csolution JSON schema does not document `debugger:` at all, so do
not go looking there. `${workspaceFolder}` passes through csolution untouched
and is expanded by VS Code.

**Do not set `args: ""`.** The template does
`config.args?.trim().split(/\s+/) ?? []`, and an empty string splits to `['']`,
injecting an empty argv entry into the model command line. Omit the node
entirely instead.

Regenerate and confirm the node landed: the `debugger:` block in
`out/<solution>+<target>.cbuild-run.yml` should show `name: Arm-FVP`, `model:`,
`config-file:`.

## 5. Fix the launch config's readiness handshake

The generated launch config does **not** work as shipped, on any host — macOS
just loses the race every time.

From `cdt-gdb-adapter`'s `startGDBServer`:

```js
if (target.port && target.serverParameters) {
    setTimeout(() => resolveStartup(), target.serverStartupDelay ?? 0);   // 0 ms!
} else {
    // wait for target.serverPortRegExp on the server's stdout, take the port from the match
}
```

The template sets both `port` and `serverParameters` and no delay, so GDB
connects immediately while the model still needs a second or more to build the
platform — plus a container start on macOS. The symptom is a session that tears
itself down and only *then* prints the banner:

```
gdb connection lost
GDBServer: Listening address="0.0.0.0" port=3333    ← too late
Info: <model>: Stopping simulation...
```

**With this wrapper, fix it with a fixed delay:**

```jsonc
"port": "3333",
"serverStartupDelay": 1000
```

The event-driven alternative — blanking `port` so the adapter takes the
`serverPortRegExp` branch and reads the banner — is the better mechanism in
principle, but it does not work through the wrapper as shipped: the model
block-buffers its own stdout whenever it is not a TTY, which it never is under
VS Code, so the banner (and every semihosting `printf`) sits in a 4KB buffer
until the model exits. The adapter would give up waiting for a line that is
already written but not yet flushed. If you run the model under `stdbuf -oL -eL`
yourself, you can switch to:

```jsonc
"port": "",
"serverPortRegExp": "GDBServer: Listening .*port=([0-9]+)",
"portDetectionTimeout": 300000
```

Note this buffering is separate from `uart0.unbuffered_output`, which only
covers the UART model.

**Either fix forces `"updateConfiguration": "manual"` on the launch config.** A
`.vscode.d/launch.json` drop-in does *not* work as a lighter alternative:
`LaunchJsonFile.addConfig` calls `fromObject`, which **replaces** the config
rather than merging fields — it drops `server`, `serverParameters` and the
`cmsis` node. And `ConfigurationSchema` requires `name`, `type` **and**
`request`; without all three the drop-in fails validation and is discarded with
no message. So a drop-in would have to restate the whole config anyway. Take
`manual`, and leave a comment in the config saying how to re-sync it (flip to
`auto`, run "Update Debug Tasks and Launch Configurations", re-apply the hand-
edited `target` fields).

Leave `Arm-FVP@GDB (attach)` on `auto` — it has no `serverParameters`, so it is
unaffected.

## 6. What the launch config's `target` must contain

```jsonc
"target": {
    "server": "FVP_Corstone_SSE-320",
    "serverParameters": [
        "-D",
        "--plugin", "${env:AVH_FVP_PLUGINS}/GDBServer.so",
        "-C", "GDBServer.port=3333",
        "-C", "GDBServer.allow_remote=1",
        "-C", "GDBServer.shutdown_on_disconnect=1",
        "-C", "mps4_board.telnetterminal0.start_port=5000",
        "-C", "mps4_board.telnetterminal0.mode=raw",
        "-f", "board/Corstone-320/fvp_config.txt",
        "-a", "out/.../image.elf"
    ],
    "port": "3333",
    "serverStartupDelay": 1000,
    "uart": { "socketPort": "5000", "eolCharacter": "CRLF" }
}
```

Each line that is not in Arm's template earns its place:

- **`GDBServer.allow_remote=1` is mandatory here.** Through Docker's port
  forwarder the debugger is not a localhost client, and the plugin resets the
  connection without it. The wrapper does not inject it — it has to be in the
  config.
- **`GDBServer.shutdown_on_disconnect=1`** asks the plugin to shut down
  gracefully when GDB detaches, so the model does not linger holding the port.
- **Use the separated `-C <param>=<value>` form, not `-C<param>=<value>`.** The
  wrapper scans its argv for `GDBServer.port=<n>` and
  `*telnetterminal<n>.start_port=<n>` as *whole* tokens to decide which ports to
  publish (`-p 127.0.0.1:<port>:<port>`). A glued `-CGDBServer.port=3333` is one
  token and matches neither, so nothing gets published and GDB cannot reach the
  model.
- **Put the telnet port on the command line, not only in `fvp_config.txt`.**
  Same reason: the wrapper only sees argv. A `telnetterminal0.start_port` that
  lives solely in the config file configures the model correctly but leaves the
  port unpublished, and the integrated UART client has nothing to connect to.
  Setting it in both places is fine; the command line wins.
- The `telnetterminal` prefix is model-specific (`mps4_board`, `mps3_board`,
  `fvp_mps2`, …). Read it out of the model's own `--list-params`.

`server` is resolved through `PATH`; use the absolute path to the wrapper if
VS Code's `PATH` does not include `bin/`.

Note the ELF and the config file are passed as **host** paths. They resolve
inside the container because the wrapper bind-mounts `$HOME` at the same path
and sets `--workdir` to the host `PWD`. A project outside `$HOME` needs
`FVP_MOUNT_DIR` (and possibly `FVP_WORKDIR`) set in the environment VS Code
inherits.

## 7. Verify

Do **not** verify by starting the model and then attaching GDB by hand — that
skips the adapter's readiness path, which is exactly what breaks.
Replay the adapter's own launch path against the committed `launch.json`: parse
the config, spawn `target.server` with `target.serverParameters` (expanding
`${workspaceFolder}` and `${env:AVH_FVP_PLUGINS}` as VS Code would), apply the
same readiness rule the adapter would, then run `arm-none-eabi-gdb -batch` with
the config's `initCommands` plus `continue`, `bt`, `detach`.

`verify-launch.py`, next to this document, does exactly that. Run it from the
workspace folder:

```sh
python3 <path-to>/FVPs-on-Mac/skills/fvp-debug-setup/verify-launch.py
```

It exits non-zero unless the breakpoint hit and no `fvp:*` container was left
behind. Success looks like:

```
readiness: fixed serverStartupDelay 1.0s (target.port=3333)
Temporary breakpoint 1, main () at board/.../main.c:31
[Inferior 1 (Remote target) detached]
containers left after teardown: none
```

Also run the free-running path — the wrapper with `-f <config> -a <elf>`, no
`-D` and no plugin — and check the firmware's own output appears. That is what
the `CMSIS Run` task does.

On the very first run warn that the container image gets built, which downloads
the ~100MB model archive.

## Caveats to tell the user

- **Run restarts the model, it does not resume a halted one** — RSP detach
  leaves the core halted and the plugin has no resume command (§2).
- Only one model can hold the GDB port at a time; a stale `fvp-gdb` or an older
  container will block it. `lsof -nP -iTCP:3333 -sTCP:LISTEN` finds the culprit
  on the host, and `docker ps --format 'container={{.Names}} image={{.Image}} ports={{.Ports}}'`
  shows which container holds it.
- The launch config is `manual`: after changing target-type or build-type, its
  `program` and `serverParameters` paths need re-syncing (§5).
- Linux and Windows: point `model:` straight at the real model executable
  (`FVP_Corstone_SSE-320`, `.exe` on Windows). The wrapper is a macOS detour.
  There `AVH_FVP_PLUGINS` must point at the real `plugins/` directory, and
  `GDBServer.allow_remote` is not needed.
- Worth reporting upstream: Arm's `FVP.adapter.json` sets neither
  `serverStartupDelay` nor `serverPortRegExp`, so the generated config races on
  every host.
