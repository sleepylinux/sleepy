# Sleepy shell runtime integrations

Each feature has one state owner and one mutation path. “Direct” means a reviewed Quickshell API or fixed argument vector, never interpreted shell text.

| Feature | State source | Mutation path | Executable/API | Why | Secret handling | Failure behavior |
|---|---|---|---|---|---|---|
<!-- provider:region-selection -->
| `region-selection`; owner: sleepy-shell | interactive Wayland region selection | bounded geometry sent to typed Sleepy recording IPC | `slurp` with fixed argv | Selection is shell UI; recording remains daemon-owned. | no credentials accepted | successful selection exit and validated integer geometry; cancellation sends no recording request. |
<!-- provider:hyprland -->
| `hyprland`; owner: sleepy-shell | Quickshell.Hyprland socket model | Quickshell.Hyprland dispatch | `hyprctl`, `xmllint` | Native compositor authority. | no credentials accepted | native Hyprland events followed by targeted refresh; controls disable on disconnect. |
<!-- provider:network -->
| `network`; owner: sleepy-shell | nmcli terse reads | nmcli fixed argv | `nmcli`, `cat` | NetworkManager owns activation. | secrets are passed only by stdin or a NetworkManager secret agent, never argv | refresh all NetworkManager observations after completion; errors stay local. |
<!-- provider:audio -->
| `audio`; owner: sleepy-shell | PipeWire registry | PipeWire node bindings | Quickshell.Services.Pipewire | Native objects are lossless. | no credentials accepted | native PipeWire object changes; missing nodes disable locally. |
<!-- provider:brightness -->
| `brightness`; owner: sleepy-shell | brightnessctl, ddcutil, or asdbctl readback | the same selected hardware provider | `brightnessctl`, `ddcutil`, optional `asdbctl` | One backend owns read/write. | no credentials accepted | read back the selected provider after completion; unsupported displays degrade. |
<!-- provider:media -->
| `media`; owner: sleepy-shell | session D-Bus MPRIS | MPRIS player methods | Quickshell.Services.Mpris | Standard player authority. | no credentials accepted | native MPRIS property changes; vanished players disappear. |
<!-- provider:notifications -->
| `notifications`; owner: sleepy-shell | freedesktop notification server | tracked notification objects | Quickshell.Services.Notifications, `notify-send` | Shell owns lifecycle. | notification content is never copied to process argv by the provider | notification lifecycle signals and persisted history; malformed items isolate. |
<!-- provider:tray -->
| `tray`; owner: sleepy-shell | StatusNotifierItem D-Bus | DBusMenu item activation | Quickshell.Services.SystemTray | Preserves native identity. | no credentials accepted | native tray and menu signals; disappearing items close. |
<!-- provider:power -->
| `power`; owner: sleepy-shell for telemetry; sleepy-sessiond for session actions | UPower D-Bus | sleepy-sessiond confirmed session command | Quickshell.Services.UPower plus typed Sleepy session IPC | Protected transitions require sequencing. | authentication remains in the system/session authority | typed command acknowledgement followed by UPower/session observation; no fabricated transition. |
<!-- provider:clipboard -->
| `clipboard`; owner: sleepy-shell | Qt Wayland clipboard | QClipboard text/image setters | Qt clipboard | Avoids helper payload leakage. | clipboard payload never crosses process argv | Qt clipboard ownership change; invalid images reject locally. |
<!-- provider:screenshot -->
| `screenshot`; owner: sleepy-shell | Quickshell.Wayland ScreencopyView | bounded local image save and swappy | `hyprctl`, `swappy` | Native pixels plus fixed editor argv. | temporary paths only; no credentials accepted | completion callback from the captured image save; failures claim nothing. |
<!-- provider:appearance -->
| `appearance`; owner: sleepy-shell plus the modular sleepy-appearance-cli package | XDG Sleepy scheme/wallpaper state and wallpaper directory | sleepy scheme/wallpaper fixed argv | `sleepy` | Sleepy-owned durable helper. | no credentials accepted; optional wallpaper hook must be an argv array | watched atomic scheme and wallpaper state files; invalid candidates preserve prior state. |
<!-- provider:weather -->
| `weather`; owner: sleepy-shell | Open-Meteo, Nominatim, and opt-in IP geolocation responses | read-only provider refresh | Quickshell HTTP | Read-only public provider. | no credentials accepted; location is URL-encoded and never sent to a process | location changes and bounded refresh timers replace cached observations; stale cache is labelled. |
<!-- provider:vpn -->
| `vpn`; owner: sleepy-shell | provider status commands, nmcli monitor, and validated sysfs interface telemetry | configured argv arrays or built-in WireGuard, WARP, NetBird, and Tailscale adapters | `cat`, `ping`, `ip`, `pkexec`, `wg-quick`; optional `warp-cli`, `netbird`, `tailscale` | Provider CLI owns authentication. | the built-in adapters accept no secret text; authentication remains provider-owned | provider status readback after every connect or disconnect; missing tools are unavailable. |
<!-- provider:applications -->
| `applications`; owner: sleepy-shell | freedesktop desktop-entry index | DesktopEntry.execute or configured terminal argv | DesktopEntries, `ghostty` | Preserves argv semantics. | desktop entry fields are argv, never shell code | launch completion is intentionally fire-and-forget; invalid entries are hidden. |

## Protected Sleepy Session ownership

`sleepy-sessiond` owns recording start/pause/stop and confined deletion, idle inhibition, game mode, lock, guarded suspend/hibernate/suspend-then-hibernate, logout, reboot and power-off. Requests are typed, generation-guarded and acknowledged over a private runtime socket. `sleepy-locker` alone owns ext-session-lock and PAM; the desktop protocol intentionally has no unlock operation.

| Typed operation | Authoritative execution and confirmation | Failure behavior |
|---|---|---|
<!-- session-operation:set-idle-inhibited -->
| `setIdleInhibited` | `sleepy-sessiond` owns the inhibitor handle and publishes its readback state. | A failed handle transition preserves the last confirmed state. |
<!-- session-operation:start-recording -->
| `startRecording(outputId, target, audio, region?)` | Region selection uses fixed-argv `slurp` before IPC. SDK validates bounded integer geometry. The daemon validates the monitor and starts its own `sleepy-recording-helper`, which invokes `gpu-screen-recorder` with fixed arguments and acknowledges only after the live backend produces output. | Cancellation sends no request. Missing backend disables recording; failed startup removes its newly created file and claims no recording state. |
<!-- session-operation:pause-recording -->
| `pauseRecording` | The daemon sends SIGUSR1 to its helper, which forwards the recorder's SIGUSR2 toggle and acknowledges the requested state. This is signal acknowledgement, not independent video-frame readback. | Missing acknowledgement invalidates and stops the owned recording process. |
<!-- session-operation:stop-recording -->
| `stopRecording` | The daemon terminates and reaps the owned helper before publishing the final recording. | Timeout or helper failure is reported without fabricating a completed file. |
<!-- session-operation:delete-recording -->
| `deleteRecording(recordingId)` | The daemon accepts only a schema-valid recording ID, resolves it by directory file descriptor, and removes only a regular same-UID recording file. | Symlinks, foreign owners, non-regular files, path traversal and unknown IDs are rejected. |
<!-- session-operation:set-game-mode -->
| `setGameMode(enabled)` | The daemon invokes the typed game-mode backend and verifies backend status. | Missing or unconfirmed backends expose an unavailable/failure state. |
<!-- session-operation:lock -->
| `lock` | The daemon connects to the private locker socket; `sleepy-locker` acquires ext-session-lock and replies only after the lock is secure. | Bad, late or missing acknowledgement fails closed; shell state cannot unlock. |
<!-- session-operation:suspend -->
| `suspend` | The daemon holds the logind delay inhibitor, obtains confirmed secure lock, requests suspend, and retains the locker hold across the transition. | Suspend is not requested unless secure-lock confirmation succeeds. |
<!-- session-operation:hibernate -->
| `hibernate` | The daemon holds the logind delay inhibitor, obtains confirmed secure lock, requests hibernation, and retains the locker hold across the transition. | Hibernation is not requested unless secure-lock confirmation succeeds. |
<!-- session-operation:suspend-then-hibernate -->
| `suspendThenHibernate` | The same guarded sleep lifecycle invokes logind `SuspendThenHibernate`. Both the default launcher Sleep action and idle timeout use this typed command. | Unsupported sleep configuration or policy denial is reported by logind; there is no shell-command fallback. |
<!-- session-operation:logout -->
| `logout` | The daemon requests the supervised UWSM/session exit and lets the greeter become authoritative. | Failure is returned; QML never kills an arbitrary process tree. |
<!-- session-operation:reboot -->
| `reboot` | The daemon sends the typed logind reboot transition after user confirmation in the shell. | Denial or D-Bus failure is reported and no successful state is synthesized. |
<!-- session-operation:power-off -->
| `powerOff` | The daemon sends the typed logind power-off transition after user confirmation in the shell. | Denial or D-Bus failure is reported and the current session remains authoritative. |

Recordings and the shell history use `$XDG_STATE_HOME/sleepy/captures` (default
`~/.local/state/sleepy/captures`). The daemon allocates `recording_*.mp4` names;
the helper refuses existing files. The helper monitors daemon reparenting and
owns one recorder child; it never signals unrelated recordings by process name.
The package supplies `gpu-screen-recorder` and `slurp`; it does not invoke a
Caelestia executable. Real GPU encoding and exact visual parity remain separate
hardware/reference acceptance gates; subprocess fixtures verify lifecycle and
argument routing, not captured video quality.
