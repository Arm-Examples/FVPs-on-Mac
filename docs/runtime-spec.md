# Docker and Apple Container runtime specification

## Scope and decision

Run the Arm Virtual Hardware Linux package through Docker Desktop or Apple's
`container` CLI. Keep the model command names under `bin/` so callers, including
CMSIS-Debugger, invoke them as before.
The default package is **11.32.23**. Release 11.33.13 is excluded because the
user reported a critical bug in it.

`build.sh` detects installed CLIs. When both are installed it asks once in the
terminal and saves the choice in `.fvp-runtime`. Model and license wrappers read
that choice without prompting. `FVP_RUNTIME` overrides it for one model or
license command; on `./build.sh` it saves the new choice.
Both runtimes use the image recipe in `Containerfile` and maintain separate
image stores.

## Runtime contract

| Concern | Required behavior |
| --- | --- |
| Host | Docker Desktop on Intel or Apple silicon macOS, or Apple Container on Apple silicon macOS 26+; selected service running |
| Selection | `build.sh` prompts only when both CLIs are installed and no saved choice exists; wrappers never prompt |
| Build | `build.sh` builds `fvp:<FVP_VERSION>` in the selected runtime with the architecture-matched archive and SHA-256, then creates `bin/` links |
| Model call | `bin/FVP_*` starts that model through the selected runtime, preserves model arguments and exit status, and mounts the selected project directory at the same absolute path |
| License | The image user has the host user name and UID; `~/.armlm` is mounted at the same path and `ARMLM_CACHED_LICENSES_LOCATION` points to it |
| Debug and UART | Whole-token `GDBServer.port=<n>` and `telnetterminal<n>.start_port=<n>` arguments publish matching ports on host `127.0.0.1` |
| VIO keyboard | A model launched from an interactive terminal receives stdin through a TTY; a headless launch remains usable without stdin |
| Lifecycle | Each invocation has a unique name and ID file; signals stop and delete only that instance, and normal completion leaves no FVP container |
| GUI | `--display-ip <host-ip>` or `FVP_DISPLAY_IP` sets `DISPLAY=<host-ip>:0` for XQuartz over TCP; optional `FVP_XAUTHORITY` forwards a mounted cookie file for authenticated access |
| DNS | `FVP_CONTAINER_DNS` is passed only to Apple Container builds and runs; an empty value uses its default |

`FVP_VERSION`, `FVP_ARCHIVE`, and `FVP_SHA256` must refer to the same release.
Changing only the version selects an image that is already built; building a
different release also requires the matching archive and checksum.

## Implementation map

- `Containerfile`: Ubuntu and FVP installation; its build arguments and
  checksum verification retain the existing image contract. The legacy
  `dockerfile` path links to it for Docker callers.
- `runtime.sh`: one-time runtime selection and service preflight.
- `build.sh`: selected runtime build and model discovery.
- `fvp.sh`: argument parsing, mounts, port publishing, model execution, cleanup.
- `armlm.sh`: license cache mount and utility execution.
- `fvprc`: release and architecture selection, plus Container DNS setting.
- `README.md` and `skills/fvp-debug-setup/`: setup and CMSIS-Debugger guidance.
- `.github/workflows/build.yml`: script and Containerfile lint, plus a Docker
  image build and smoke check. Apple Container runtime checks require an Apple
  silicon Mac.

## Acceptance checks

0. With both CLIs installed and no saved choice, `./build.sh` prompts in a
   terminal and saves `docker` or `container`; model and license wrappers never
   prompt. With one CLI installed, selection is automatic.
1. `./build.sh` succeeds and `container image inspect fvp:11.32.23` reports a
   Linux Arm64 image.
2. `./bin/FVP_MPS2_Cortex-M3 --version` reports Fast Models `11.32+23`.
3. `./bin/armlm --help` starts with the host license cache mounted.
4. `container list` shows no FVP container after either command completes.
5. In an interactive terminal, a VIO model receives keyboard button presses and
   the firmware responds.
6. With a CMSIS Solution project, debug and UART clients reach the published
   loopback ports, and interrupting the launcher releases those ports.
7. On a host with XQuartz, a GUI model displays through an explicitly selected
   host IPv4 address.

Checks 1–4 passed on Apple container 1.7.1 on macOS 27.2.1. Check 5 passed
with the VIO_Blinky CMSIS Run task: the user observed successive `BTN:` output
and `LED: 00000001` in its terminal.

Check 6 passed with the VIO_Blinky CMSIS debug configuration: GDB connected on
`localhost:3333` and stopped at `main`, the user connected a Serial Monitor TCP
client to UART port 5000, and stopping the debug session removed its FVP
container and released port 3333. A second debug launch connected and was left
running. The earlier standalone CMSIS Run terminal needed a separate manual
`container stop` after the CMSIS stop action ended its task record.

Check 7 passed: the user opened `xeyes` from the FVP image and then opened the
bare Corstone SSE-300 MPS3 visualization window through XQuartz, using a host
IPv4 address and an Xauthority cookie. The 11.32.23 image exposes the bundled
SDL2 library under its soname. In the VIO_Blinky project,
`mps3_board.v_path=Python` alone suppresses the MPS3 window; omitting it makes
the firmware fail at VIO access. Keep VIO_Blinky's normal Python VIO run
headless and use a separate bare MPS3 launch to verify the GUI path.

The Docker branch has passed local command-path checks with a fake Docker CLI;
the Docker image build is configured as a CI gate. A live Docker Desktop run remains to
be checked on a Mac with Docker running. The shared `Containerfile` is used by
both builders.

## Primary references

- [Apple container requirements and setup](https://github.com/apple/container#initial-install)
- [Apple container command reference](https://github.com/apple/container/blob/main/docs/command-reference.md)
- [Apple container networking and loopback port publishing](https://github.com/apple/container/blob/main/docs/networking.md)
- [Apple container bind mounts](https://github.com/apple/container/blob/main/docs/volumes.md)
