# Third-party notices

Deckhand is MIT-licensed (see [LICENSE](LICENSE)). It builds on:

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
(`NSImage(systemSymbolName:)`, system fonts). The key images are drawn on your
Mac at runtime and are never stored in this repository.

The static icons under `streamdeck-plugin/com.teams-bridge.streamdeck.sdPlugin/imgs/`
(and the copies inside the installer) are SF Symbols glyphs rendered to PNG by
`tools/render-icons.swift`. They are included for convenience. Apple's SF
Symbols license is aimed at use inside apps for Apple platforms and doesn't
clearly grant the right to redistribute the artwork on its own, so Apple (or
anyone with rights in them) can ask for them to be removed or replaced, and
they will be. Reusing them in your own projects is at your own risk; check the
[SF Symbols license](https://developer.apple.com/design/downloads/SF-Symbols/license.pdf) first.
The MIT license of this project does **not** extend to them.

## Trademarks

Microsoft Teams is a trademark of Microsoft Corporation. Stream Deck is a
trademark of Corsair Memory, Inc. Homey is a trademark of Athom B.V. Home
Assistant is a trademark of the Open Home Foundation. Apple, macOS, SF Symbols
and SF Pro are trademarks of Apple Inc.

This is an independent hobby project. It is **not affiliated with, endorsed by,
or supported by** any of them.
