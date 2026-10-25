#!/usr/bin/env python3
"""A swipe back with nothing to go back to can close the tab, as ⌘W does.

Build first (`./build.sh`), then `python3 Tests/swipe_close.py`. Same harness
as the split suite: a probe started hidden, in a world of its own, driven
through the bench, nothing made or shown, everything removed afterwards.

Settings › Keyboard & Mouse › Close a tab with a swipe back is off unless asked
for, and
while it is off a swipe back on a tab's first page must go on doing what it
did — nothing — and a tab with a page behind it must go back as it always has.
Turned on, back from the first page closes the tab and the neighbour on the
right comes forward, which is what ⌘W does; a pin keeps its page, since its
first page is the page it was pinned at.

The swipe is the bench's `wheel`: two fingers, with a trackpad's phases, which
is the only kind PageView reads. `ui swipepages` stands in for the Mac's own
Swipe between pages setting, and `ui swipeclose` for the switch.
"""
import json
import sys
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("swipe-close")

PAGE = """<!doctype html><meta charset=utf-8><title>{name}</title>
<style>body{{margin:0;font:14px system-ui}} main{{width:600px;margin:0 auto}}</style>
<main><h1>{name}</h1><p>{name}<div style="height:2400px"></div></main>"""


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        name = self.path.strip("/").split("?")[0] or "start"
        body = PAGE.format(name=name).encode()
        self.send_response(200); self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

    def log_message(self, *a): pass


srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://localhost:{srv.server_port}"

t = sv.T()


def ui(**what): sv.cmd({"do": "ui", **what}); time.sleep(0.3)
def tabs(): return sv.cmd({"do": "tabs"})["tabs"]
def names(): return [x["url"].rsplit("/", 1)[-1] for x in tabs()]
def where(id): return next((x["url"].rsplit("/", 1)[-1] for x in tabs() if x["id"] == id), None)
def active(): return next((x["url"].rsplit("/", 1)[-1] for x in tabs() if x["active"]), None)
def listing(id): return next((i for i, x in enumerate(tabs()) if x["id"] == id), -1)


def open_tab(name):
    tab = sv.cmd({"do": "open", "url": f"{BASE}/{name}"})["id"]
    sv.cmd({"do": "wait", "id": tab, "seconds": 5})
    return tab


def wheel(id, dx, steps=10, ms=150):
    """Two fingers across the page, with a trackpad's phases. Positive dx is
    the way back, as in zoom_swipe.py."""
    sv.cmd({"do": "wheel", "id": id, "dx": dx, "dy": 0, "steps": steps, "ms": ms})
    time.sleep(1.2)


def main():
    try:
        sv.setup(); sv.launch()
        ui(swipepages=True)

        # ---- off, which is how it ships ----
        a = open_tab("a"); b = open_tab("b"); c = open_tab("c")
        sv.cmd({"do": "select", "id": a}); time.sleep(0.5)
        wheel(a, 300)
        t.ok("off: back from a tab's first page closes nothing", where(a) == "a", names())
        t.ok("off: and leaves you on that tab", active() == "a", active())

        # ---- on ----
        ui(swipeclose=True)
        was_right = names()[listing(a) + 1]
        wheel(a, 300)
        t.ok("on: back from the first page closes the tab", where(a) is None, names())
        t.ok("on: and the neighbour on the right comes forward", active() == was_right, (active(), was_right))

        # ---- a tab with a page behind it still goes back ----
        d = open_tab("d1")
        sv.cmd({"do": "go", "id": d, "url": f"{BASE}/d2"})
        sv.cmd({"do": "wait", "id": d, "seconds": 5}); time.sleep(0.5)
        sv.cmd({"do": "select", "id": d}); time.sleep(0.4)
        wheel(d, 300)
        t.ok("on: a tab with history goes back, and is still there", where(d) == "d1", names())
        t.ok("on: back is the page before, not the tab before", active() == "d1", active())

        # ---- a pin keeps its page ----
        e = open_tab("e")
        sv.cmd({"do": "select", "id": e}); time.sleep(0.4)
        sv.cmd({"do": "pin", "id": e}); time.sleep(0.6)
        wheel(e, 300)
        t.ok("on: a swipe does not put a pin down", where(e) == "e", names())
        t.ok("on: a pin stays pinned", sv.cmd({"do": "pin", "id": e})["pin"] != "", names())

        # ---- and off again, the gesture is the one it always was ----
        ui(swipeclose=False)
        f = open_tab("f")
        sv.cmd({"do": "select", "id": f}); time.sleep(0.4)
        wheel(f, 300)
        t.ok("off again: nothing closes", where(f) == "f", names())
    finally:
        t.done(); sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
