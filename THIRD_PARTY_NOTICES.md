# Third-party notices

PurpleKit includes the SideSign Swift package as a dependency.

## SideSign

- Project: https://github.com/SideStore/SideSign
- License stated by upstream: GNU General Public License v3.0 (GPL-3.0)
- Upstream license statement: https://github.com/SideStore/SideSign#license
- Dependency declaration: `project.yml`
- Changes made by PurpleKit: dependency integration and app-specific UI/wiring are maintained in this repository; upstream SideSign source remains maintained by its original authors.

SideSign's package manifest also depends on other projects, including:

- [swift-crypto](https://github.com/apple/swift-crypto)
- [CodeSignKit](https://github.com/mahee96/CodeSignKit)
- [GSACryptoKit](https://github.com/mahee96/GSACryptoKit)
- [libdeflate](https://github.com/SideStore/libdeflate)
- [AnisetteKit](https://github.com/mahee96/AnisetteKit)

Review each resolved package's license at the exact revision used when distributing a build. GSACryptoKit and AnisetteKit have been published under AGPL-3.0 in the upstream versions previously reviewed. The dependency graph can change because SideSign currently references some dependencies by branch, so distribution builds must retain the resolved package versions and corresponding license notices.

## Distribution and attribution

PurpleKit may be distributed under its own name and branding, but SideSign and other third-party components must not be represented as wholly original PurpleKit code. Preserve upstream copyright and license notices, mark modifications, provide the applicable license text, and provide the corresponding source code and other materials required by the applicable copyleft licenses when distributing binaries.

This file is a notice, not legal advice. Check the exact dependency revisions and all transitive licenses before publishing a release.
