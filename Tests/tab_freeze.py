#!/usr/bin/env python3
"""A tab that sleeps keeps its page, and comes back without loading it.

Build first (`AURA_OUT=build/debug ./build.sh debug`), then
`AURA_APP=build/debug/Aura.app python3 Tests/tab_freeze.py`.

A page is left scrolled, with a variable of its own, and the tab is put to
sleep and gone back to. Kept in memory (see Freeze.swift) it must come back
with both — a reload is the thing this is not — and no more than five pages
may be kept at once, the one kept longest being the one let go of. With
`sleep.freeze` off, the same tab must come back by loading, which is what
every sleeping tab did before.
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

# Its own world, apart from the split suite's in this checkout (see use()).
sv.use("tab-freeze")


def ev(tab, js):
    return sv.cmd({"do": "eval", "id": tab, "js": js}).get("value")


def row(tab):
    """This tab as the app describes it: `frozen` is the page still in memory."""
    return next(t for t in sv.cmd({"do": "tabs"})["tabs"] if t["id"] == tab)


def open_real(path, within=15):
    """A tab opened the way a bookmark opens one — a real tab, not the bench's,
    since a bench tab never sleeps. Answers its id, once its page is in."""
    tab = sv.cmd({"do": "openmark", "url": f"{sv.BASE}/{path}"})["active"][:8].lower()
    until = time.time() + within
    while time.time() < until:
        if ev(tab, "document.readyState") == "complete": break
        time.sleep(0.2)
    time.sleep(0.3)
    return tab


def sleep(tab):
    return sv.cmd({"do": "sleep", "id": tab})


def away():
    """Something else in front, so the tab in question is one nobody is looking
    at: a tab on screen never sleeps."""
    other = sv.cmd({"do": "open", "url": "about:blank"})["id"]
    sv.cmd({"do": "select", "id": other})
    time.sleep(0.6)
    return other


def kept(t):
    """A page kept in memory comes back as it was, without a load."""
    sv.setup()
    sv.launch()
    tab = open_real("long")
    ev(tab, "window.__mark = 'alive'; window.scrollTo(0, 600); 1")
    time.sleep(0.3)
    away()
    said = sleep(tab)
    t.ok("a tab put to sleep is kept, not unloaded", said.get("frozen") is True, said)
    t.ok("…and its row says so", row(tab).get("frozen") is True, row(tab))
    time.sleep(1.5)
    t.ok("…a second and a half later too, with nothing waking it", row(tab).get("frozen") is True, row(tab))
    sv.cmd({"do": "select", "id": tab})
    time.sleep(0.6)
    t.ok("waking it does not load the page again", ev(tab, "String(window.__mark)") == "alive",
         ev(tab, "String(window.__mark)"))
    t.ok("…and it is where it was left", ev(tab, "Math.round(window.scrollY)") == 600,
         ev(tab, "window.scrollY"))


def budget(t):
    """Five pages are kept at once; the sixth sleep lets the oldest go."""
    sv.setup()
    sv.launch()
    tabs = [open_real(f"kept-{n}") for n in range(6)]
    away()
    for tab in tabs:
        sleep(tab)
    frozen = [tab for tab in tabs if row(tab).get("frozen")]
    t.ok("six tabs slept: five pages kept", len(frozen) == 5, frozen)
    t.ok("the page kept longest is let go of", not row(tabs[0]).get("frozen"), row(tabs[0]))
    t.ok("…still asleep, and the last one is among those kept",
         row(tabs[0]).get("asleep") is True and row(tabs[-1]).get("frozen") is True,
         (row(tabs[0]), row(tabs[-1])))


def unloaded(t):
    """With `sleep.freeze` off, a sleeping tab comes back by loading, as before."""
    # The key is the app's own — `sleep.freeze`, a dotted name no Python
    # keyword can carry, so it goes in as a mapping.
    sv.setup(**{"sleep.freeze": False})
    sv.launch()
    tab = open_real("plain")
    ev(tab, "window.__mark = 'alive'; 1")
    away()
    said = sleep(tab)
    t.ok("nothing is kept when the switch is off", said.get("frozen") is False, said)
    sv.cmd({"do": "select", "id": tab})
    until = time.time() + 10
    while time.time() < until:
        if ev(tab, "document.readyState") == "complete": break
        time.sleep(0.2)
    t.ok("waking it loads the page again", ev(tab, "String(window.__mark)") == "undefined",
         ev(tab, "String(window.__mark)"))


def main():
    t = sv.T()
    for case in [kept, budget, unloaded]:
        print(f"— {case.__doc__}")
        try:
            case(t)
        except Exception as error:
            t.ok(f"{case.__name__} ran to the end", False, error)
        finally:
            sv.finish()
    t.done()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
