# Deckhand

Run your Microsoft Teams calls from a Stream Deck, and let your smart home know
when you're on one.

- **Stream Deck keys** for mute, camera, raise hand and hang up, whose icons
  follow what Teams is really doing (also if you click in Teams instead). On a
  **Stream Deck Neo**, an info panel shows the time, date and live mic/camera
  badges.
- **Auto-mute**: mutes your mic after a stretch of silence, with preset timeout
  keys, a live countdown ring, and an "add time" key.
- **Homey** and **Home Assistant** integrations that report *In a call*,
  *Microphone enabled*, *Camera enabled* (and more) so you can drive lights,
  signs and Do-Not-Disturb automations.

```
Teams  <-- Accessibility API -->  Deckhand (macOS menu bar app)
                                    |-- Stream Deck plugin    (this Mac only, controls)
                                    |-- Homey app             (LAN, read-only status)
                                    '-- Home Assistant        (LAN, read-only status)
```

The macOS app is the only thing that talks to Teams. Everything else is a thin
client of it.

> **Why Accessibility automation?** Teams' official local API
> (`ws://localhost:8124`) was retired by Microsoft on 2026-06-30. The only way
> left to press Teams' own mute/camera buttons is the macOS Accessibility API,
> the same mechanism screen readers use. That means a Teams UI update can break
> detection (see [Known limitations](#known-limitations)).
>
> Not affiliated with Microsoft, Corsair/Elgato, Athom, the Open Home
> Foundation or Apple. See [NOTICE.md](NOTICE.md).

## Requirements

- macOS 13 or later (works on macOS 27), Apple silicon or Intel
- New Microsoft Teams (`com.microsoft.teams2`)
- Stream Deck app 7.6+ (for the Neo panel; other devices work with the keys)
- Only to build from source: Xcode (or the Command Line Tools) and Node 20+

## Install

**Download** the installer, `Deckhand.<version>.pkg`, from the
[latest release](https://github.com/Tre-Eiler/teams-deckhand/releases/latest) (currently
[1.5.1](https://github.com/Tre-Eiler/teams-deckhand/releases/download/v1.5.1/Deckhand.1.5.1.pkg)),
or build it yourself (needs Xcode or the Command Line Tools, and Node 20+):

```bash
git clone https://github.com/Tre-Eiler/teams-deckhand.git
cd teams-deckhand
(cd streamdeck-plugin && npm install)
./package.sh        # builds dist/Deckhand <version>.pkg
```

Double-click the `.pkg` (it needs an admin password). It installs
`/Applications/Deckhand.app` (with the Stream Deck plugin inside) and a
login agent, starts it, and hands the plugin to Stream Deck, which asks you to
confirm. The package is **unsigned**, so if Gatekeeper blocks it, approve it in
**System Settings → Privacy & Security → Open Anyway** (a file you built
yourself or copied over USB/`scp` isn't quarantined and opens normally).

Then:

1. Allow **Deckhand** in **System Settings → Privacy & Security →
   Accessibility** (called **Device Control and Data Access** on macOS 27).
2. Drag actions from the **Deckhand** category onto your Stream Deck keys.

Microphone access is requested the first time you switch auto-mute on; the app
only measures loudness, it never records or sends audio.

To use it on another Mac, copy the `.pkg` you built. Installing a newer package
over an old one upgrades in place and keeps your settings.

Uninstall:

```bash
launchctl bootout "gui/$(id -u)/com.teams-bridge.daemon"
sudo rm -rf "/Applications/Deckhand.app" /Library/LaunchAgents/com.teams-bridge.daemon.plist
rm -rf ~/Library/Application\ Support/TeamsBridge ~/Library/Logs/TeamsBridge   # settings and logs (optional)
```

then remove the plugin in Stream Deck's preferences.

## Stream Deck

Actions, under the **Deckhand** category:

- **Mic Toggle**, **Camera Toggle** — icon follows the real Teams state.
- **Raise Hand** — raises your hand and lowers it again after 5 seconds (or press
  again to lower now). A plain timed action, because Teams only exposes real
  hand state deep in the People panel.
- **Hang Up** — leaves the call. **Hold** the key (default 1 s; set 0–5 in the
  key's settings) so a stray tap can't drop you; a quick tap flashes an alert.
  It only *leaves*, never "End meeting for everyone". If Teams asks "are you
  sure?" with a second **Leave** button, Deckhand presses that one too. If the
  call still hasn't ended after about two seconds (or the Leave button can't be
  found), it falls back to Teams' own hang-up shortcut, **⌘⇧H**, which briefly
  brings the Teams call window to the front.
- **Auto-Mute Toggle / Timeout / Add Time** — see [Auto-mute](#auto-mute).
- **Status Panel** — drag onto the Neo's info strip. Shows the time and date, with
  mic and camera badges during a call, and takes over the whole panel for the last
  seconds of an auto-mute countdown. Its settings (select the panel in the Stream
  Deck app) let you:
  - hide the **mic** or **camera** badge,
  - switch to a **24-hour clock**,
  - turn the **countdown** off, and choose how long it shows (last 10, 20 or 30
    seconds) and its style: **Fill** (the panel drains from green to amber to red,
    and the text flips light/dark as the fill passes under it) or **Tint** (a dim
    drain behind text that takes the state color). If auto-mute can't hear your
    mic it shows **Paused**.

## Auto-mute

While you're in a call with your mic live, the app counts down from the last
time it heard you speak and, at zero, presses Teams' mute button — only if the
mic is still live, so it can never flip you *back* to unmuted.

- **Auto-Mute Toggle** — turns the feature on/off.
- **Auto-Mute Timeout** — a preset: set **Seconds** in the key's settings and
  press it to make that the active timeout. Place several (5, 15, 30, 60…). The
  active key shows a ring that drains green → amber → red.
- **Auto-Mute Add Time** — like +30 on a microwave: each press adds the
  configured seconds to the running countdown, until you mute or turn the
  feature off. With no countdown running it flashes an alert.

Settings persist in `~/Library/Application Support/TeamsBridge/settings.json`.

**Which mic?** By default it listens to the macOS default input. If Teams uses a
different one (say a USB mic that isn't the default), name it, or auto-mute would
hear silence while you talk:

```bash
curl "http://127.0.0.1:8943/automute"                    # lists availableInputs
curl "http://127.0.0.1:8943/automute/input?name=Wave"    # part of the name; empty = default
curl "http://127.0.0.1:8943/automute/listen?seconds=20"  # open the mic outside a call, to watch levels
curl "http://127.0.0.1:8943/automute/margin?db=18"       # sensitivity margin (default 12)
```

**Safety:** if it can't actually hear the mic (permission missing, device gone,
or pure silence), the countdown **holds** instead of running, so it never mutes
you blind. The key shows an amber face and the menu says why. Voices from your
speakers reaching the mic count as speech; headphones avoid that.

## Homey

[`homey-app/`](homey-app) is a Homey Apps SDK v3 app. Its **Teams call status**
device shows *In a call*, *Microphone on*, *Camera on*, *Hand raised* and
*Auto-mute on*, each with its own Flow triggers ("Call started", "Microphone
muted"…) and conditions. It shows as unavailable while the Mac is asleep or
Deckhand isn't running.

Install it on your Homey from source (an App Store listing is pending):

```bash
cd homey-app
npm install
npx homey login
npx homey app install     # or `npx homey app run` to develop with live logs
```

Then **Add device → Deckhand** and enter your Mac's address (`ipconfig getifaddr
en0` shows it). Pairing checks that Deckhand answers before it adds anything,
and you can add one device per Mac. If the Mac's address changes, edit it in the
device's settings.

**Publishing it yourself** (needs an Athom developer account): run `npx homey app
validate --level publish`, then `npx homey app publish`, and submit the draft for
certification in the [Homey developer tools](https://tools.developer.homey.app).
The store images are drawn by `tools/render-homey-images.swift`.

## Home Assistant

[`custom_components/teams_bridge/`](custom_components/teams_bridge) is a custom
integration that keeps a WebSocket open to the app and pushes state instantly
(no polling).

**Install** — with [HACS](https://hacs.xyz): *Integrations → ⋮ → Custom
repositories*, add this repository as type *Integration*, install **Teams
Bridge**, restart Home Assistant. Or copy `custom_components/teams_bridge` into
your config's `custom_components` folder and restart.

**Set up** — *Settings → Devices & services → Add integration → Deckhand*,
then enter the Mac's address and port (`8942`).

Entities:

| Entity | Type | Meaning |
|---|---|---|
| In a call | binary sensor | Teams is in a meeting |
| Microphone enabled | binary sensor | mic is live in Teams |
| Camera enabled | binary sensor | camera is on in Teams |
| Hand raised | binary sensor | Raise Hand pressed within the last 5 s |
| Auto-mute enabled | binary sensor | auto-mute is on |
| Auto-mute can't hear microphone | binary sensor (diagnostic) | countdown is on hold |
| Auto-mute countdown | sensor (s) | seconds left; unknown when not counting |
| Auto-mute timeout | sensor (s, diagnostic) | the active timeout |

Entities go **unavailable** (not off) when the Mac is asleep or the app isn't
running, so an automation doesn't mistake "unknown" for "not in a call".

Example — a busy light:

```yaml
automation:
  - alias: On-air light
    triggers:
      - trigger: state
        entity_id: binary_sensor.deckhand_in_a_call   # check your entity ID
        to: "on"
    actions:
      - action: light.turn_on
        target: { entity_id: light.office_sign }
```

(Entity IDs include the device name, which contains the Mac's address, so check
yours under *Settings → Entities*.) The integration is **read-only**: controls aren't reachable over the network, by design.

## Security model

The app runs two small servers:

| Address | Serves | Reachable from |
|---|---|---|
| `0.0.0.0:8942` | `GET /status`, `/ws` — in-call, mic, camera, hand, auto-mute state | your network |
| `127.0.0.1:8943` | everything that acts or exposes activity: mic/camera/hang-up controls, key images, diagnostics, logs | this Mac only |

So anyone on your network can see whether you're in a call and whether your mic
and camera are on, and **nothing else**; they can't mute you, hang up, or read
logs. If even that is too much, block port 8942 in your firewall and use only the
Stream Deck. There's no authentication on the status feed; don't expose the port
to the internet.

## Troubleshooting and logs

Click the **menu bar icon**: it says what's blocking things — Accessibility
access not granted, Teams not running, no call detected, or "can't hear the
microphone".

If "Deckhand" is switched on in Settings but the menu still shows ⚠, the
entry is **stale**: macOS ties the grant to the app's code signature, and
ad-hoc-signed builds get a new one every build. Use **Reset Permission & Ask
Again…** in the menu (the installer also clears old entries on every upgrade).
By hand:

```bash
tccutil reset Accessibility com.teams-bridge.daemon
tccutil reset Microphone com.teams-bridge.daemon
```

Logs are in `~/Library/Logs/TeamsBridge/` (1 MB × 3, also in Console.app under
`com.teams-bridge.daemon`). They record events only — startup, permissions, call
started/ended, mic/camera changes, every command, auto-mute decisions — and
**no meeting names, window titles or audio**. **Export Logs…** in the menu saves
a zip with the logs and a diagnostics report; that report *does* include Teams
window titles and button labels (needed to debug "it can't find my call"), which
is why it's only made when you ask. The same data is on the loopback port:

```bash
curl "http://127.0.0.1:8943/logs?lines=200"
curl "http://127.0.0.1:8943/diagnostics"
```

## Development

```text
daemon/             macOS app (Swift package): AX automation, audio, servers, menu bar
streamdeck-plugin/  Stream Deck plugin (TypeScript, @elgato/streamdeck v3)
homey-app/          Homey Apps SDK v3 app (store listing text in README.txt)
custom_components/  Home Assistant integration
tools/              render-icons.swift (Stream Deck icons from SF Symbols), render-homey-images.swift
package/, package.sh  the macOS installer
spike/              throwaway Accessibility explorer for diagnosing Teams UI changes
```

Internal identifiers keep the project's original name, so existing installs and
permissions carry over: bundle ID `com.teams-bridge.daemon`, the `TeamsBridge`
settings and log folders, and the Home Assistant domain `teams_bridge`.

Run the app from source beside an installed one (different ports, no permission
prompt):

```bash
cd daemon && swift build && TEAMS_BRIDGE_DEV_PORT=9942 .build/debug/teams-bridge-daemon
```

Per-user dev install without the package: `daemon/install.sh`.

Stream Deck plugin:

```bash
cd streamdeck-plugin
npm install
npm run icons     # optional: re-draws the icons from SF Symbols (the rendered ones are committed)
npm run build
npx @elgato/cli link com.teams-bridge.streamdeck.sdPlugin
npm run watch
```

If Teams changes its UI and buttons stop being found, dump what it exposes
while in a call and update the identifiers in
`daemon/Sources/teams-bridge-daemon/TeamsAutomationEngine.swift`:

```bash
cd spike && swiftc spike.swift -o spike && ./spike dump
```

## Known limitations

- Detection relies on Teams' internal accessibility identifiers
  (`microphone-button`, `video-button`, …) and button labels; a Teams update can
  change them.
- Teams **presence** (Available/Busy/DND) isn't implemented; it needs a separate
  Microsoft Graph sign-in.
- Hand-raised is "pressed in the last 5 seconds", not read back from Teams.
- Builds are ad-hoc signed and the installer is unsigned and not notarized, so
  permissions must be re-granted after upgrading (the installer resets them so
  macOS asks again).

## License

[MIT](LICENSE). Third-party components and trademarks: [NOTICE.md](NOTICE.md).
