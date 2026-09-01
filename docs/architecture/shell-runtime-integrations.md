# Sleepy shell runtime integrations

Each feature has one state owner and one mutation path. “Direct” means a reviewed Quickshell API or fixed argument vector, never interpreted shell text.

| Feature | State source | Mutation path | Executable/API | Why | Secret handling | Failure behavior |
|---|---|---|---|---|---|---|
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

`sleepy-sessiond` owns recording start/pause/stop and confined deletion, idle inhibition, game mode, lock, suspend-after-confirmed-lock, logout, reboot and power-off. Requests are typed, generation-guarded and acknowledged over a private runtime socket. `sleepy-locker` alone owns ext-session-lock and PAM; the desktop protocol intentionally has no unlock operation.
