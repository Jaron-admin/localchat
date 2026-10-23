# LocalChat licensing

The LocalChat derivative application, as a whole, and the original LocalChat modifications owned by Jaron-admin are distributed under the GNU General Public License, version 3 only (SPDX: `GPL-3.0-only`). The full license is in [LICENSE](LICENSE). This policy applies from the commit that introduces this file; licenses granted for earlier revisions are not revoked.

LocalChat-specific modifications: Copyright (c) 2026 Jaron-admin. These include LAN chat, invitations, persisted conversations, file cards, and the LocalChat application identity introduced in commits `c806a497ee6c9d4d904400f060822005ac81806b` and `d6651a0556b8a928304ca20d93424c153ab919f7`. Their authorship and modification dates remain recorded in Git history. The license policy was updated on 2026-10-23.

## Upstream and third-party material

LocalChat is derived from [LocalSend](https://github.com/localsend/localsend). The upstream code remains under Apache License 2.0, with its copyright notices and attribution intact. The previous root license, including `Copyright 2022-2026 Tien Do Nam`, is preserved verbatim in [LICENSES/Apache-2.0.txt](LICENSES/Apache-2.0.txt). Original author, contributor, translator, and packager credits remain in the application and repository. LocalChat is not an official LocalSend release.

Apache-2.0 permits inclusion in a GPLv3 derivative; it does not make the GPL-covered LocalChat additions available under Apache-2.0. See the [Apache Software Foundation compatibility explanation](https://www.apache.org/licenses/GPL-compatibility.html). Where package metadata describes mixed LocalChat and upstream code, `GPL-3.0-only AND Apache-2.0` records the applicable obligations; it is not a choice of either license.

Unmodified upstream components, including `packages/typed_isolates`, keep their own licenses. Vendored Cargokit and other dependencies, assets, and separately licensed files keep their original license and notice files. This document does not relicense third-party material or grant trademark rights. Upstream README translations under `support/readme/` describe LocalSend; the LocalChat policy is this document.

## Redistribution

Private use or modification does not require public publication. When conveying this GPL-covered derivative, comply with GPLv3, preserve the applicable upstream and third-party notices, and supply the Corresponding Source using a GPL-compliant method. Distributed binaries must identify the matching source revision and include the applicable license and notice files; a link to a moving branch alone may not identify their source. The software is provided without warranty as specified by the licenses.
