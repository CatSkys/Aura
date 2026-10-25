#!/usr/bin/env python3
"""The block list Aura hands WebKit, made out of the lists everyone else uses.

A hand-written list of a few dozen domains catches the ad networks that were
big in 2010. EasyList and EasyPrivacy are what a real blocker ships: tens of
thousands of rules, each one a site somebody watched an advert appear on.
Turning them into something WebKit can enforce is work for the build, not for
the app — the app is handed JSON and nothing else.

    ./Tools/filters.py --fetch      download the lists, then convert
    ./Tools/filters.py              convert the copies already downloaded
    ./Tools/filters.py --lists DIR  convert lists found in DIR instead

What comes out, in Resources/Shield, one file per question WebKit is asked:

    network.json    requests not to make
    extra.json      the same, for the rules needing a regular expression, the
                    ones that take a page away instead of an advert (a filter
                    that says `$document`), and their exceptions
    cosmetic.json   things not to show
    scriptlets.json the small scripts a list asks a page to run — the part of
                    a blocker that answers a site's own check for one
    sources.json    which lists, as of when, under what licence, and how many
                    rules survived — read by no code, written for whoever
                    wonders where the block list came from

WebKit compiles each file once and caches the compiled form under a name that
includes a hash of the JSON, so an unchanged list is not compiled twice and a
new one is noticed. Nothing here runs at launch, and the app never downloads a
list: only this script goes to the internet, and only when told to.
"""

import argparse
import hashlib
import json
import re
import struct
import sys
import urllib.request
import zlib
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Resources" / "Shield"
CACHE = ROOT / ".filters-cache"

# The two lists that between them are the ad blocking everyone compares to.
# Both are CC BY-SA 3.0; the credit they ask for is kept in sources.json.
LISTS = (
    ("EasyList", "https://easylist.to/easylist/easylist.txt", "CC BY-SA 3.0"),
    ("EasyPrivacy", "https://easylist.to/easylist/easyprivacy.txt", "CC BY-SA 3.0"),
)

# What a rule blocks when it does not say. `document` is left out on purpose:
# in a filter list a rule without `$document` never touches a page you
# navigate to, and a blocked page is blank with no way back but turning the
# blocker off. The same rule as a subresource is a missing advert.
SUBRESOURCES = ("image", "style-sheet", "script", "font", "raw", "svg-document", "media")

# A filter's word for a kind of request, and WebKit's for the same.
TYPES = {
    "image": "image",
    "stylesheet": "style-sheet",
    "css": "style-sheet",
    "script": "script",
    "font": "font",
    "media": "media",
    "object": "raw",
    "object-subrequest": "raw",
    "xmlhttprequest": "raw",
    "xhr": "raw",
    "ping": "raw",
    "beacon": "raw",
    "other": "raw",
    "document": "document",
    "doc": "document",
    # WebKit cannot tell a frame's document from the page's own, so both of
    # these mean "a document went missing".
    "subdocument": "document",
}

# Options that ask for something a content blocker cannot do. The rule is
# dropped whole rather than stripped of the option: dropping only the option
# turns "hide this element" or "take this parameter off" into "block
# everything", which is worse than not blocking at all.
UNSUPPORTED = (
    "csp", "permissions", "removeparam", "queryprune", "rewrite", "urltransform",
    "replace", "redirect", "redirect-rule", "empty", "mp4", "inline-script",
    "inline-font", "genericblock", "popup", "popunder", "websocket", "webrtc",
    "method", "to", "from", "all", "strict1p", "strict3p", "header", "denyallow",
    "urlskip", "network", "jsonprune", "xmlprune", "hls", "application",
)

# The regular expressions WebKit's matcher reads are a small language of their
# own: literal characters, `.`, character classes of plain characters, `? * +`,
# parentheses, a `^` first and a `$` last. No alternatives, no backreferences,
# no `\d`/`\w`/`\s`, no `\b`, no counted repetitions, no lookaround. A single
# construct it refuses takes the whole file down with it, so a filter reaching
# for one is left out here, before it can.
REFUSED_REGEX = re.compile(r"[|]|\\[1-9]|\\[dDwWsSbB]|\(\?(?:P|[<>=!]|\{)|\{|[^\x00-\x7f]")

# uBlock Origin's own selector syntax, which a content blocker's stylesheet
# cannot be written in. The plain CSS WebKit does read — `:has()`, `:not()`,
# attribute selectors — passes through.
PROCEDURAL = (
    ":has-text(", ":contains(", ":upward(", ":matches-css", ":matches-attr(",
    ":matches-path(", ":matches-prop(", ":min-text-length(", ":xpath(",
    ":nth-ancestor(", ":remove(", ":style(", ":watch-attr(", ":others(",
    ":shadow(", ":-abp-", ":if(", ":if-not(", ":matches-media(",
)

# The names a filter list uses for a scriptlet, and the name it is written as
# here: a list says `acs` where the scriptlet is abort-current-script, and the
# runtime in Resources/Shield/scriptlets.js knows only the long name.
ALIASES = {
    "set": "set-constant",
    "acs": "abort-current-script",
    "aost": "abort-on-stack-trace",
    "aeld": "addEventListener-defuser",
    "rmnt": "remove-node-text",
    "nostif": "no-setTimeout-if",
    "nano-sib": "nano-something",
}

# What the runtime carries. A rule naming a scriptlet that is not here is left
# out and counted, rather than sent to a page to do nothing at all.
SCRIPTLETS = (
    "set-constant", "abort-current-script", "abort-on-stack-trace",
    "addEventListener-defuser", "remove-node-text", "set-local-storage-item",
    "set-cookie", "cookie-remover", "no-xhr-if", "no-fetch-if",
)

# How many selectors go into one rule. A selector WebKit refuses takes its
# rule with it, so a rule is small enough to be worth losing.
CHUNK = 400


def pack(text: str) -> bytes:
    """The rules, as the bundle holds them.

    Four bytes saying how big the text was, then a deflate stream. Every rule
    in the JSON repeats the same keys, the same kinds of request and the same
    protocol-and-subdomain prefix, so the file is a twentieth of what it reads
    as — and WebKit wants the JSON, which is unpacked once per launch from
    Shield.swift. The four bytes are there because deflate keeps no record of
    what it grew from, and reading the whole stream to find out is worse than
    saying.
    """
    raw = text.encode("utf-8")
    squeeze = zlib.compressobj(9, zlib.DEFLATED, -15)
    return struct.pack(">I", len(raw)) + squeeze.compress(raw) + squeeze.flush()


def fetch(force: bool) -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    for name, url, _ in LISTS:
        path = CACHE / f"{name}.txt"
        if path.exists() and not force:
            print(f"{name}: already here ({path.stat().st_size} bytes)")
            continue
        print(f"{name}: downloading {url}")
        request = urllib.request.Request(url, headers={"User-Agent": "Aura/filters"})
        with urllib.request.urlopen(request, timeout=180) as answer:
            body = answer.read()
        path.write_bytes(body)
        print(f"{name}: {len(body)} bytes")


# MARK: - a filter, as a regex


def literal(character: str) -> str:
    """One character of a filter, as the part of a regular expression matching
    only it. Quotes what a regular expression would otherwise read as syntax
    and nothing else: a `-` or a `/` is the URL's own business."""
    return "\\" + character if character in ".+*?()[]{}|\\^$" else character


def as_regex(pattern: str) -> str:
    """A filter's URL pattern, as the regular expression WebKit matches URLs
    with. This is the whole of the filter language: `||` says the match starts
    at the host, `*` is anything, `^` is where a URL stops being a word, and a
    `|` at either end pins that end down."""
    out = []
    if pattern.startswith("||"):
        # Any protocol, then any subdomain, then what the filter wrote.
        out.append(r"^[a-z][a-z0-9+.\-]*://([^/]+\.)?")
        pattern = pattern[2:]
    elif pattern.startswith("|"):
        out.append("^")
        pattern = pattern[1:]
    for index, character in enumerate(pattern):
        if character == "*":
            out.append(".*")
        elif character == "^":
            # Where the URL stops being a word. The "or the URL ends here" half
            # of a filter's separator cannot be said: WebKit's matcher reads a
            # regular expression with no alternatives in it, so the choice
            # would be the one construct it refuses.
            out.append(r"[^a-z0-9_.%-]")
        elif character == "|" and index == len(pattern) - 1:
            out.append("$")
        else:
            out.append(literal(character))
    return "".join(out)


def split_options(text: str):
    """A filter split into what matches a URL and the options after it. The
    last `$` starts the options; a `$` in the URL part is the URL's own
    character and stays put."""
    if "$" not in text:
        return text, ""
    body, options = text.rsplit("$", 1)
    if not options or not re.fullmatch(r"[a-z0-9~=,.|*_\-]+", options):
        return text, ""
    return body, options


def site_of(pattern: str):
    """The site a filter is about, when the filter is `||site^` and nothing
    more. Used to say "this page, all of it" about an exception that has no
    URL of its own to match."""
    if not pattern.startswith("||"):
        return None
    host = re.split(r"[\^/|*$]", pattern[2:], 1)[0]
    return host if re.fullmatch(r"[a-z0-9][a-z0-9.\-]*\.[a-z]{2,}", host) else None


def is_expression(body: str) -> bool:
    """Whether a filter is written as a regular expression. A filter list says
    so by putting the whole thing between slashes; `/ad/*` is a path that
    starts that way, not an expression."""
    return len(body) > 2 and body.startswith("/") and body.endswith("/")


def scriptlet_args(text: str):
    """A scriptlet's arguments, as a `##+js(name, arg, arg)` line spells them.

    A comma ends an argument unless it was written `\\,`; quotes around a whole
    argument are the list's way of keeping the commas inside it, and are taken
    off here. An argument left empty at the end is simply not there.
    """
    found, current = [], []
    index = 0
    while index < len(text):
        character = text[index]
        if character == "\\" and index + 1 < len(text) and text[index + 1] in ",$":
            current.append(text[index + 1])
            index += 2
            continue
        if character == ",":
            found.append("".join(current).strip())
            current = []
            index += 1
            continue
        current.append(character)
        index += 1
    found.append("".join(current).strip())

    args = []
    for argument in found:
        if len(argument) > 1 and argument[0] == argument[-1] and argument[0] in "'\"":
            argument = argument[1:-1]
        args.append(argument)
    while args and args[-1] == "":
        args.pop()
    return args


def under(domain: str, parent: str) -> bool:
    return domain == parent or domain.endswith("." + parent)


class Refused(Exception):
    """A filter that cannot become a rule, and why, in a phrase fit to count."""


def translate(text: str) -> dict:
    """One line of a filter list, as the trigger half of a rule. Raises
    Refused when the line asks for something a content blocker has no way to
    do."""
    body, options = split_options(text)
    parts = [part for part in options.split(",") if part]

    kinds, negated = set(), set()
    load = None
    match_case = False
    for_sites, not_for = [], []

    for part in parts:
        if part in ("third-party", "3p", "~first-party", "~1p"):
            if load == "first":
                raise Refused("both third-party and first-party")
            load = "third"
        elif part in ("~third-party", "~3p", "first-party", "1p"):
            if load == "third":
                raise Refused("both third-party and first-party")
            load = "first"
        elif part in ("match-case", "matchcase"):
            match_case = True
        elif part in ("important", "strict1p", "strict3p"):
            continue
        elif part.startswith("domain="):
            for entry in part[len("domain="):].split("|"):
                entry = entry.strip().lower()
                if entry.startswith("~"):
                    not_for.append(entry[1:])
                elif entry:
                    for_sites.append(entry)
        elif part.startswith("~") and part[1:] in TYPES:
            negated.add(TYPES[part[1:]])
        elif part in TYPES:
            kinds.add(TYPES[part])
        else:
            raise Refused(part.split("=")[0] + " — an option a content blocker cannot honour")

    if len(body) < 2:
        raise Refused("nothing to match")

    if is_expression(body):
        expression = body[1:-1]
        if REFUSED_REGEX.search(expression):
            raise Refused("a regular expression WebKit may refuse")
        trigger = {"url-filter": expression}
    else:
        trigger = {"url-filter": as_regex(body)}

    if negated:
        if "document" in negated:
            raise Refused("everything but a document")
        # Being told what a rule is not is a list of the kinds it is, because
        # a trigger says what to match and never what to leave out.
        kinds = {kind for kind in SUBRESOURCES if kind not in negated} | kinds

    trigger["resource-type"] = sorted(kinds) if kinds else list(SUBRESOURCES)
    if load == "third":
        trigger["load-type"] = ["third-party"]
    elif load == "first":
        trigger["load-type"] = ["first-party"]
    if match_case:
        trigger["url-filter-is-case-sensitive"] = True

    # WebKit reads one condition list per rule, not two, so a rule narrowed to
    # some sites and widened away from others has to lose one of them. It
    # loses the narrowing, and what cannot be said is not said.
    if for_sites and not_for:
        kept = [d for d in for_sites if not any(under(d, e) for e in not_for)]
        if not kept or len(kept) != len(for_sites):
            raise Refused("narrowed to a site and excepted on it at once")
        trigger["if-domain"] = ["*" + d for d in kept]
    elif for_sites:
        trigger["if-domain"] = ["*" + d for d in for_sites]
    elif not_for:
        trigger["unless-domain"] = ["*" + d for d in not_for]
    return trigger


# MARK: - the files WebKit is given


class File:
    """One file of rules: deduplicated, counted, and refused if it grows past
    what WebKit takes in one go."""

    def __init__(self, name: str, budget: int):
        self.name = name
        self.budget = budget
        self.rules: list = []
        self.kept: list = []
        self.by_trigger: dict = {}
        self.refused: dict = {}

    def add(self, rule: dict) -> None:
        """Two rules that differ only in which kinds of request they are about
        are one rule about all of them: a trigger reads a list of kinds as
        readily as one kind, and the file is smaller for the saying."""
        trigger = dict(rule["trigger"])
        kinds = set(trigger.pop("resource-type", ()))
        key = json.dumps([trigger, rule["action"]], sort_keys=True, separators=(",", ":"))
        found = self.by_trigger.get(key)
        if found is not None:
            found[2] |= kinds
            return
        self.by_trigger[key] = [trigger, rule["action"], kinds]
        self.kept.append(self.by_trigger[key])

    def extend(self, rules) -> None:
        for rule in rules:
            self.add(rule)

    def refuse(self, reason: str) -> None:
        self.refused[reason] = self.refused.get(reason, 0) + 1

    def write(self) -> dict:
        if len(self.kept) > self.budget:
            print(f"{self.name}: {len(self.kept)} rules is past the {self.budget} "
                  f"WebKit takes in one file", file=sys.stderr)
            raise SystemExit(1)
        rules = []
        for trigger, action, kinds in self.kept:
            trigger = dict(trigger)
            # Never left out, even when it is every kind a page is not: a
            # trigger saying nothing about kinds is a trigger about all of
            # them, the page itself included, and a blocked page is blank.
            if kinds:
                trigger["resource-type"] = sorted(kinds)
            rules.append({"trigger": trigger, "action": action})
        text = json.dumps(rules, ensure_ascii=False, separators=(",", ":"))
        packed = pack(text)
        (OUT / f"{self.name}.json.z").write_bytes(packed)
        digest = hashlib.sha256(packed).hexdigest()
        print(f"{self.name}: {len(rules)} rules, {len(text)} bytes read as, "
              f"{len(packed)} as it is shipped, {digest[:12]}")
        for reason, count in sorted(self.refused.items(), key=lambda pair: -pair[1]):
            print(f"    left out: {count} {reason}")
        return {"rules": len(rules), "size": len(text), "bytes": len(packed),
                "hash": digest}


def rule(trigger: dict, action: str, selector: str = "") -> dict:
    action_object = {"type": action}
    if selector:
        action_object["selector"] = selector
    return {"trigger": trigger, "action": action_object}


def cosmetic(selector: str, condition: dict) -> dict:
    return rule({"url-filter": ".*", **condition}, "css-display-none", selector)


def hide_off(condition: dict) -> dict:
    """Everything matched before this point stops being hidden or blocked, on
    the sites the condition names."""
    return rule({"url-filter": ".*", **condition}, "ignore-previous-rules")


def selectable(selector: str) -> bool:
    return bool(selector) and not any(mark in selector for mark in PROCEDURAL) \
        and selector.count("(") == selector.count(")") \
        and selector.count("[") == selector.count("]")


def main(argv) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--fetch", action="store_true", help="download the lists first")
    parser.add_argument("--force", action="store_true", help="download even if a copy is here")
    parser.add_argument("--lists", type=Path, help="a folder of filter list files to read")
    parser.add_argument("--budget", type=int, default=150000,
                        help="rules WebKit takes in one content rule list")
    options = parser.parse_args(argv[1:])

    if options.fetch:
        fetch(options.force)

    folder = options.lists or CACHE
    sources, lists = [], []
    for name, url, licence in LISTS:
        path = folder / f"{name}.txt"
        if not path.exists():
            print(f"{name}: not here ({path}); run with --fetch", file=sys.stderr)
            return 1
        body = path.read_text(encoding="utf-8", errors="replace").splitlines()
        lists.append(body)
        sources.append({"name": name, "url": url, "licence": licence, "lines": len(body)})

    OUT.mkdir(parents=True, exist_ok=True)
    network = File("network", options.budget)
    extra = File("extra", options.budget)
    cosmetic_file = File("cosmetic", options.budget)

    # A list takes its own rules back with `$badfilter`, and a rule cannot be
    # judged until every such line has been seen: hence a pass for those first.
    taken_back = set()
    for body in lists:
        for line in body:
            line = line.strip()
            if "$badfilter" not in line:
                continue
            text = line[2:] if line.startswith("@@") else line
            bare, opts = split_options(text)
            taken_back.add((line.startswith("@@"), bare,
                            ",".join(p for p in opts.split(",") if p != "badfilter")))

    def is_taken_back(exceptioned: bool, text: str) -> bool:
        bare, opts = split_options(text)
        return (exceptioned, bare,
                ",".join(p for p in opts.split(",") if p != "badfilter")) in taken_back

    # MARK: hiding

    everywhere: list = []              # selectors hidden on every site
    named: dict = {}                   # selector: the sites that want it, and don't
    generic_off: list = []             # sites that turn generic hiding off
    all_off: list = []                 # sites that turn hiding off altogether

    def named_for(selector: str) -> dict:
        return named.setdefault(selector, {"for": set(), "out": set()})

    for body in lists:
        for line in body:
            line = line.strip()
            if not line or line[0] in "![" or any(m in line for m in ("#?#", "#$#", "#%#", "$$")):
                continue
            if "#@" in line:
                domains, _, selector = line.partition("#@#")
                selector = selector.strip()
                if not selectable(selector) or selector.startswith("+js("):
                    continue
                if not domains.strip():
                    # "Never hide this anywhere": the selector is taken out of
                    # the everywhere rule rather than argued with.
                    named_for(selector)["out"].update(["*"])
                    continue
                for domain in (d.strip().lower() for d in domains.split(",")):
                    if domain:
                        named_for(selector)["out"].add(domain.lstrip("~"))
                        named_for(selector)["for"].discard(domain.lstrip("~"))
                continue
            if "##" not in line:
                continue
            domains, _, selector = line.partition("##")
            selector = selector.strip()
            if not selectable(selector) or selector.startswith("+js("):
                continue
            sites = [d.strip().lower() for d in domains.split(",") if d.strip()]
            for_sites = [d for d in sites if not d.startswith("~")]
            not_for = [d[1:] for d in sites if d.startswith("~")]
            if for_sites and not_for:
                # Narrowed and excepted at once: not said, rather than hidden
                # where the list said not to hide it.
                continue
            if not sites:
                everywhere.append(selector)
            elif for_sites:
                named_for(selector)["for"].update(for_sites)
            else:
                named_for(selector)["out"].update(not_for)

    hide_rules, site_rules = [], []
    named_everywhere = set(everywhere)
    common = [s for s in dict.fromkeys(everywhere) if "*" not in named.get(s, {}).get("out", ())]
    for start in range(0, len(common), CHUNK):
        hide_rules.append(cosmetic(", ".join(common[start:start + CHUNK]), {}))

    for selector, entry in named.items():
        not_for = sorted(entry["out"])
        if "*" in not_for:
            # A list said never to hide this anywhere: it is in no rule at all.
            continue
        if selector in named_everywhere:
            # Hidden everywhere already, so all that is left to say is where
            # not to hide it.
            if not_for:
                site_rules.append(cosmetic(selector, {"unless-domain": ["*" + d for d in not_for]}))
            continue
        for_sites = [d for d in sorted(entry["for"])
                     if not any(under(d, e) for e in not_for)]
        if for_sites:
            site_rules.append(cosmetic(selector, {"if-domain": ["*" + d for d in for_sites]}))

    # MARK: taking hiding back

    for body in lists:
        for line in body:
            line = line.strip()
            if not line.startswith("@@") or "#" in line:
                continue
            if not any(mark in line for mark in ("$elemhide", "$generichide")):
                continue
            try:
                trigger = translate(line[2:])
            except Refused:
                continue
            condition = {key: trigger[key] for key in ("if-domain", "unless-domain")
                         if key in trigger}
            if not condition:
                continue
            (generic_off if "$generichide" in line else all_off).append(hide_off(condition))

    cosmetic_file.extend(hide_rules)
    cosmetic_file.extend(generic_off)
    cosmetic_file.extend(sorted(site_rules, key=lambda r: json.dumps(r, sort_keys=True)))
    cosmetic_file.extend(all_off)

    # MARK: small scripts

    # A list asking a page to run one of a handful of named scripts, which is
    # how a blocker answers a site's own check for one: the check is a script,
    # and the script can be made to see what it wants to see.
    asked, canceled = [], []
    for body in lists:
        for line in body:
            line = line.strip()
            if "+js(" not in line:
                continue
            if "#@#" in line:
                domains, _, rest = line.partition("#@#")
                exceptioned = True
            elif "##" in line:
                domains, _, rest = line.partition("##")
                exceptioned = False
            else:
                continue
            inner = rest.split("+js(", 1)[1]
            if inner.endswith(")"):
                inner = inner[:-1]
            args = scriptlet_args(inner)
            if not args:
                continue
            call = [ALIASES.get(args[0], args[0]), args[1:]]
            sites = [d.strip().lower() for d in domains.split(",") if d.strip()]
            (canceled if exceptioned else asked).append((sites, call))

    scripts = []
    unseen = {}
    for sites, call in asked:
        if call[0] not in SCRIPTLETS:
            unseen[call[0]] = unseen.get(call[0], 0) + 1
            continue
        if any(sites == other and call == other_call for other, other_call in canceled):
            continue
        entry = {"sites": sites, "js": call}
        if entry not in scripts:
            scripts.append(entry)

    (OUT / "scriptlets.json").write_text(
        json.dumps(scripts, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8")
    sites_named = sum(1 for entry in scripts if entry["sites"])
    print(f"scriptlets: {len(scripts)} rules, {sites_named} for a named site, "
          f"{len(scripts) - sites_named} everywhere")
    for name, count in sorted(unseen.items(), key=lambda pair: -pair[1]):
        print(f"    left out: {count} {name} — no such scriptlet here")

    # MARK: requests

    blocks, exceptions, extra_exceptions = [], [], []
    for body in lists:
        for line in body:
            line = line.strip()
            if not line or line[0] in "![" or ("#" in line and not line.startswith("/")):
                continue
            # Asking for hiding to stop is said in the file that hides; here
            # it is neither a request to block nor one that cannot be made.
            if any(mark in line for mark in ("$elemhide", "$generichide")):
                continue
            exceptioned = line.startswith("@@")
            text = line[2:] if exceptioned else line
            if "$badfilter" in text or is_taken_back(exceptioned, text):
                continue
            try:
                trigger = translate(text)
            except Refused as reason:
                (extra if is_expression(split_options(text)[0]) else network).refuse(str(reason))
                continue

            expression = is_expression(split_options(text)[0])
            document = trigger["resource-type"] == ["document"]
            if exceptioned and document:
                # "This page and all of it": the blocks it answers live in
                # another file and match other URLs, so it is said as a site.
                site = site_of(split_options(text)[0])
                if site:
                    site_only = {"if-domain": ["*" + site]}
                    exceptions.append(hide_off(site_only))
                    cosmetic_file.add(hide_off(site_only))
                else:
                    extra_exceptions.append(rule(trigger, "ignore-previous-rules"))
            elif exceptioned:
                # An exception answers what was read before it, and only in the
                # file it is in: the one it answers is here.
                (extra_exceptions if expression else exceptions).append(
                    rule(trigger, "ignore-previous-rules"))
            elif expression or document:
                # A page taken away rather than an advert, or a rule that only
                # a regular expression could say: the full half of the blocker,
                # because off, a page taken away is a page that stays blank.
                extra.add(rule(trigger, "block"))
            else:
                blocks.append(rule(trigger, "block"))

    # Every exception sits after the rules it answers: it takes back what was
    # read before it, and nothing else.
    network.extend(blocks)
    network.extend(exceptions)
    extra.extend(extra_exceptions)

    print("writing")
    written = {file.name: file.write() for file in (network, extra, cosmetic_file)}
    (OUT / "sources.json").write_text(json.dumps({
        "made": date.today().isoformat(),
        "by": "Tools/filters.py",
        "lists": sources,
        "files": dict(written, scriptlets={
            "rules": len(scripts),
            "bytes": (OUT / "scriptlets.json").stat().st_size,
        }),
    }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{len(common)} selectors in the everywhere rule, {len(site_rules)} rules naming a site")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
