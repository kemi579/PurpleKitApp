# PurpleKit sideloading status

This document distinguishes implemented behavior from planned behavior. A successful unsigned IPA build is not evidence that Apple authentication, signing, pairing, or installation works.

## Implemented in the current foundation PR

- Settings screen for a user-supplied HTTPS JSON catalog URL.
- Catalog parsing for a JSON array or a `{ "servers": [...] }` envelope, with `name` and `address` / `url` fields.
- Filtering of blank names, duplicate entries, non-HTTPS server URLs, and URLs containing embedded credentials.
- HTTPS-only catalog request validation, including rejection of a redirect whose final response URL is not HTTPS.
- Local caching of the last successfully loaded catalog.
- Removal of legacy locally-generated certificate placeholder state. Saving an Apple ID email is not authentication and does not create a certificate.
- Pull-request CI that generates the Xcode project, archives without signing, packages an IPA, and checks for `Payload/PurpleKit.app/Info.plist`.

## Not implemented yet

- Apple ID authentication and two-factor authentication.
- Real Anisette request generation or connection to an Anisette server.
- Developer certificate creation/renewal or provisioning profile management.
- IPA import, bundle inspection, code signing, and installation to a paired iOS device.
- Device pairing, Minimuxer integration, installed-app inventory, or automatic refresh.
- End-to-end device testing.

## Security and release notes

- Never ask users to paste Apple ID passwords, app-specific passwords, session cookies, or authentication tokens into issue reports.
- An HTTPS URL only protects transport; it does not prove that a server is trustworthy, available, or compatible with SideStore.
- Do not claim an IPA is installable just because it was packaged successfully. The current CI artifact is unsigned.
- Integrating SideStore/SideSign/Minimuxer requires reviewing upstream APIs, Swift toolchain requirements, transitive dependencies, and applicable licenses before copying or linking code.
- Any future signing or refresh action must report the actual operation result and must not update certificate expiry optimistically.
