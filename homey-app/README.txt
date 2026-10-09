Deckhand reports your Microsoft Teams call status to Homey, so your home can react when you're on a call: light up a busy sign, mute the speakers, dim the lights, switch on Do Not Disturb.

The device shows:
- In a call
- Microphone on
- Camera on
- Hand raised
- Auto-mute on

Every one of them can start a Flow when it changes, for example "Call started" or "Microphone muted", and can be used as a condition.

REQUIRES THE DECKHAND MAC APP
Deckhand runs on the Mac you take your calls on. It's a free, open-source menu bar app that reads Teams' own mute and camera buttons through macOS Accessibility, and it also lets you control Teams from a Stream Deck. Get it at https://github.com/Tre-Eiler/teams-deckhand and install it on that Mac first.

SETUP
1. Install and start the Deckhand app on your Mac (it appears in the menu bar).
2. In Homey, add a device and choose Deckhand.
3. Enter the Mac's IP address (the port is 8942). Homey checks that it can reach Deckhand.

The device shows as unavailable while the Mac is asleep or Deckhand isn't running.

PRIVACY
Only the call, microphone, camera, hand and auto-mute states are shared, over your local network. Homey can't control Teams or see meeting names, chats or audio.

Deckhand is an independent project and isn't affiliated with or endorsed by Microsoft. Microsoft Teams is a trademark of Microsoft Corporation.
