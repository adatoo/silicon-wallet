# ADR-0009: Card scanning reads on the device and keeps no image

- **Status:** Accepted (2026-11-05; updated 2026-11-05 for the camera view and review)

## Context

Typing a card's number, expiry and name is slow and invites typos (issue #140). A camera can
read them, but a photo of a card is plaintext vault data: the security rules forbid writing it
to disk, caches, logs or anywhere off the device. The app also has to read cards on the Mac,
which has no live scanner and often no usable camera. Reading also needs to be checkable and
correctable (issue #148): the person should see where each value came from, and fix one that
was read into the wrong field.

## Decision

- **iPhone and iPad: the app's own camera view** (`AVCaptureSession` with a video data output),
  rather than VisionKit's `DataScannerViewController`, which can't find a card's edge, capture
  a frame by itself or hand over a frame to review. About three frames a second are read in
  memory; the card's edge and the text boxes are drawn over the preview, and a frame is
  captured automatically once the card's edge is in view and the same number (or, on the back,
  code) reads twice in a row. A shutter captures by hand. The session stops, and every frame is
  dropped, when the sheet closes.
- **Mac: Continuity Camera's Take Photo or Scan Documents from a nearby iPhone or iPad.** The
  photo arrives through the pasteboard AppKit gives the requesting button
  (`NSServicesMenuRequestor`), shown as a context menu, the only kind AppKit fills with its
  Continuity Camera items. The app holds it only in memory and drops it when the review sheet
  closes. This needs no camera entitlement. There's no webcam scanner: built-in webcams read
  small embossed digits poorly, and an iPhone serving as the webcam is better used this way.
- **Finding the card:** Vision's rectangle detection, limited to an ID-1 card's shape, then
  Core Image's perspective correction straightens it before the text is read carefully. Without
  a card edge the whole photo is read.
- **Review:** the straightened card is shown, in memory, with a box over each line read,
  labelled by the field it gave. Choosing a box uses it for another field; any value can be
  cleared. Nothing is filled until the person chooses Use.
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
- The camera view can't be tested on the simulator, and Continuity Camera needs a real iPhone.
  Both are manual tests. App-hosted tests check the analysis, from photo to card edge,
  straightening, Vision and parser, using a rendered fake card on a dark background.
- The camera view is the app's own code to maintain (rotation, focus, torch), where VisionKit's
  scanner was Apple's.
- A camera usage description is added (`NSCameraUsageDescription`); App Review sees camera use.
