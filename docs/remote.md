# iPhone and iPad

The aquarium on your phone: the same tank and fish, their cards with the last reply, and the buttons to answer them.
The sessions keep running on the Mac; the phone watches, answers permission requests and questions, replies, and can
start a session on the Mac.

## Pairing

1. On the Mac, turn on **Preferences → General → Other devices**. A QR code shows up.
2. Open the app on the phone and scan it (or paste the link).

Each phone that scans the code gets a key of its own and shows up in the list under that section, with its name and
when it was last seen. **Revoke** takes one device out (it can't connect anymore, and whatever it had open closes
right away); **Forget all** takes them all out.

## At home and away

On the same network the phone finds the Mac by itself (Bonjour). Away from home it goes through
[Tailscale](https://tailscale.com): install the Tailscale app on the Mac and on the phone, signed into the same
account, and pair once more so the QR code carries the Mac's tailnet name. Tailscale built into another app doesn't
count: it runs inside that app and gives the Mac no address. Preferences tells you which case you're in.

## Security

- Nothing is open until you turn it on, and only private networks get in (your LAN and Tailscale): a forwarded port
  or a public IPv6 address doesn't open it to the internet.
- The connection is TLS with a key only the paired devices have (no accounts, no certificates, no server of ours), and
  each connection gets a key of its own (forward secrecy). A device without a key, or with a revoked one, fails the
  handshake.
- Allowing a tool from the phone asks for Face ID first.

## What you can do on the phone

- See the tank live, with its theme (or keep a theme of your own on the phone, or hand yours to the Mac).
- Tap a fish for its card: its portrait, last reply, a reply field, Allow / Deny.
- The gestures of the Mac: tap to feed, double tap to knock, drag for a current, the eggs to start a session, the
  chest for the summary, the moray to talk to the assistant.
- Sound and the ambient music, the fish's names on or off.
- No Mac nearby? **See a demo** on the pairing screen.

## Notifications

When a session asks for something and the app isn't open, the Mac sends a notification straight to Apple's push
service, with Allow / Deny or a reply field on it. Its text is sealed with the device's key, so Apple only sees that
"a session needs you". It needs an Apple developer account: Preferences → General → Notifications on the iPhone takes
the account's push key.

## Building the app

```sh
brew install xcodegen
scripts/ios.sh sim                                 # the simulator
FISHBOTS_TEAM=<team id> scripts/ios.sh device      # a plugged-in iPhone
FISHBOTS_TEAM=<team id> FISHBOTS_PUSH=1 scripts/ios.sh device   # with notifications (paid account)
```

On the phone, deleting the app is enough to remove it: a reinstall starts unpaired.

How it's built (the routes, the stream, the keys, the push sealing): [extensions.md, point 13](extensions.md#13-other-devices-remoteswift).
