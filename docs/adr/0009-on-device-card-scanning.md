# ADR-0009: Card scanning reads on the device and keeps no image

- **Status:** Accepted (2026-11-05)

## Context

Typing a card's number, expiry and name is slow and invites typos (issue #140). A camera can
read them, but a photo of a card is plaintext vault data: the security rules forbid writing it
to disk, caches, logs or anywhere off the device. The app also has to read cards on the Mac,
which has no live scanner and often no usable camera.

## Decision

- **iPhone and iPad: VisionKit's live scanner** (`DataScannerViewController`). Text is read
  from camera frames in memory. Nothing is captured or saved, and the scanner stops when its
  sheet closes.
- **Mac: Continuity Camera's Take Photo from a nearby iPhone or iPad.** The photo arrives
  through the pasteboard AppKit gives the requesting button (`NSServicesMenuRequestor`, a menu
  item with `NSMenuItem.importFromDeviceIdentifier`). The app holds it only in memory while
  Vision's `RecognizeTextRequest` reads it, and drops it when the review sheet closes. This
  needs no camera entitlement. There's no webcam scanner: built-in webcams read small embossed
  digits poorly, and an iPhone serving as the webcam is better used this way.
- **Recognition is Apple's, on the device**, with language correction off. Parsing
  (`CardTextParser`, SiliconWalletKit) is pure text work:
  - the number is accepted only if it passes the Luhn check and has a known scheme and length;
  - the expiry is the latest date on the card;
  - the cardholder is a line of capitals that isn't card wording.
- **The security code** is a suggestion read from the back, or from the front for American
  Express. It skips phone numbers and the card number's last four digits. It's filled only when
  the person, having seen it, chooses Use. PCI DSS limits on keeping security codes bind
  merchants, not a person's own vault, where it's a concealed field like any other.
- **Filling** never overwrites silently. Empty fields are filled; replacing a value that's
  already there needs confirmation. Fields are found by label (`CardField`), so a user's own
  card group works too.
- Recognised text is never logged. The privacy label stays "Data Not Collected", and the privacy
  policy says the camera is used only on the device.

## Consequences

- Cards that print the number on the back, or no number at all, give only what's on the front.
  The user types the rest.
- The live scanner can't be tested on the simulator, and Continuity Camera needs a real iPhone.
  Both are manual tests. An app-hosted test checks the Mac path, from photo to Vision to
  parser, using a rendered fake card.
- A camera usage description is added (`NSCameraUsageDescription`); App Review sees camera use.
