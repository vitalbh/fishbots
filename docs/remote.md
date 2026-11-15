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

When a session asks for something and the app isn't open, the phone gets a notification, with Allow / Deny or a
reply field on it, in under a second. It goes through your own iCloud: the Mac writes a note to the app's private
database and Apple rings the phone. There's nothing to set up and no server of ours, but the Mac and the iPhone need
the same Apple ID. Its text is sealed with the device's key, so not even Apple reads what the session said.
Preferences → General → Notifications on the iPhone turns them off.

If you build the iPhone app with your own developer account, the Mac can also send straight to Apple's push service
with that account's key (the same section, **Your own Apple key**).

## Building the app

The bundle id has to be one of your team's: `FISHBOTS_IOS_BUNDLE=<com.you.fishbots>` (the default belongs to this
project's account). With a free Apple ID the app lasts 7 days and has no notifications. With a paid account of your
own, notifications go through your own key (Preferences → **Your own Apple key**) rather than iCloud, whose container
belongs to this project: build with `FISHBOTS_PUSH=1 FISHBOTS_CLOUD=0`.

```sh
brew install xcodegen
scripts/ios.sh sim                                 # the simulator
FISHBOTS_TEAM=<team id> scripts/ios.sh device      # a plugged-in iPhone
FISHBOTS_TEAM=<team id> FISHBOTS_PUSH=1 scripts/ios.sh device   # with notifications (paid account)
FISHBOTS_TEAM=<team id> scripts/app.sh             # the Mac app signed for iCloud, which the notifications need
```

The first time a team is used, Apple takes a few minutes to let the apps into the iCloud container ("Invalid bundle ID
for container"); it sorts itself out. Before the App Store, the container's schema has to be deployed to production in
the CloudKit Console.

On the phone, deleting the app is enough to remove it: a reinstall starts unpaired.

How it's built (the routes, the stream, the keys, the push sealing): [extensions.md, point 13](extensions.md#13-other-devices-remoteswift).
