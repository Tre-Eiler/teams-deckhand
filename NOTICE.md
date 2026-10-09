# Third-party notices

Teams Deckhand is MIT-licensed (see [LICENSE](LICENSE)). It builds on:

| Component | Used for | License |
|---|---|---|
| [Swifter](https://github.com/httpswift/swifter) (compiled into the macOS app) | HTTP + WebSocket server | BSD 3-Clause, © 2014 Damian Kołakowski |
| [@elgato/streamdeck](https://github.com/elgatosf/streamdeck) | Stream Deck plugin SDK | MIT |
| [ws](https://github.com/websockets/ws) | WebSocket client in the plugin and Homey app | MIT |
| [sdpi-components](https://sdpi-components.dev) v4 (vendored as `streamdeck-plugin/com.teams-bridge.streamdeck.sdPlugin/ui/sdpi-components.js`) | Stream Deck settings UI | Licensed by Corsair Memory Inc. and contributors (and Lit, BSD-3-Clause); the license header is kept at the top of the file |
| [aiohttp](https://github.com/aio-libs/aiohttp) (provided by Home Assistant) | Home Assistant integration | Apache 2.0 |

## Apple SF Symbols and SF Pro

The Stream Deck key icons and the images the app draws on your keys use
Apple's SF Symbols and SF Pro, drawn through the system's own APIs
(`NSImage(systemSymbolName:)`, system fonts) on your Mac. **The rendered
icon images are not included in this repository**, because Apple's licenses
don't permit redistributing them: `npm run icons` (or `./package.sh`) draws
them locally. Anything you build that way is for your own use.

## Trademarks

Microsoft Teams is a trademark of Microsoft Corporation. Stream Deck is a
trademark of Corsair Memory, Inc. Homey is a trademark of Athom B.V. Home
Assistant is a trademark of the Open Home Foundation. Apple, macOS, SF Symbols
and SF Pro are trademarks of Apple Inc.

This is an independent hobby project. It is **not affiliated with, endorsed by,
or supported by** any of them.
