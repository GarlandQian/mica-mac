# Sparxie source reuse license boundary

- Date: 2026-07-18
- Mica license: MIT (`LICENSE`)
- Sparxie reference: commit `32bd802c546d14ebead1cd9e618c3bba4c484fc8`
- Sparxie license: GPLv3 (`tmp/codex/sparxie/LICENSE`)

## Confirmed facts

- The fixed Sparxie checkout is licensed under GNU GPL version 3.
- Mica is currently distributed under the MIT license.
- GNU lists the Expat/MIT-style license as GPL-compatible. This permits MIT code to be combined into a GPL work; it does not permit GPL-covered Sparxie code to remain governed only by Mica's MIT license.
- GPLv3 section 5 requires a conveyed modified/combined covered work to be licensed as a whole under GPLv3 when it is a single covered work rather than mere aggregation.
- Directly copying Sparxie source into Mica or tightly linking its Rust state engine through FFI would therefore create a material GPLv3 distribution obligation unless the copyright holders grant a separate license. Exact treatment can depend on distribution and integration facts, so this note is not legal advice.

## Primary sources

- Sparxie GPLv3 license at the audited commit: https://github.com/UruhaLushia/sparxie/blob/32bd802c546d14ebead1cd9e618c3bba4c484fc8/LICENSE
- GNU GPL-compatible licenses: https://www.gnu.org/licenses/license-list.html#GPLCompatibleLicenses
- GNU GPL FAQ on combining works and license compatibility: https://www.gnu.org/licenses/gpl-faq.html

## Decision

- Mica remains MIT and native Swift/SwiftUI.
- Sparxie is a behavior and protocol reference only. No Sparxie Flutter/Rust source is copied, adapted, or linked.
- Remote controller clients, session state, streams, models, actions, and sing-box gRPC support are implemented independently in Swift.
