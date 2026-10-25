# The lists this block list is made of

Aura's own code is MIT (see `LICENSE` at the top of the repository). The filter
lists are other people's work, converted by `Tools/filters.py` into the files
beside this one — `network.json.z`, `extra.json.z`, `cosmetic.json.z` and
`scriptlets.json.z`. Each list keeps its own licence, and `sources.json` records
which lists were read and on what day.

| List | Kept by | Licence |
|---|---|---|
| EasyList | [easylist.to](https://easylist.to/) | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) |
| EasyPrivacy | [easylist.to](https://easylist.to/) | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) |
| uBlock filters, quick fixes, unbreak, privacy, Lite extras | [uBlock Origin / uAssets](https://github.com/uBlockOrigin/uAssets) | [GPL-3.0](GPL-3.0.txt) |
| AdGuard Chinese | [AdGuard](https://github.com/AdguardTeam/AdguardFilters) | [GPL-3.0](GPL-3.0.txt) |
| EasyList China | [easylist.to](https://easylist.to/) | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) |

EasyList and EasyPrivacy are used under CC BY-SA 3.0: attribution is this file
and `sources.json`, and the converted rules that come from them stay under the
same licence. uBlock Origin's lists and AdGuard's are GPL-3.0; the full text is in
`GPL-3.0.txt`, and the rules converted from them are under it too.

Nothing here is a fork of uBlock Origin's code. The names of the scriptlets and
the shape of their arguments come from the filter lists; the runtime that runs
them, `scriptlets.js`, was written for Aura.
