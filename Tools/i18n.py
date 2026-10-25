#!/usr/bin/env python3
"""The keys a translation has to cover, read out of the source.

The app is written in English and the English is the key, so there is no
second list to keep in step: every sentence that is shown is in the code, and
this reads them out of it.

    ./Tools/i18n.py scan           every key, grouped by file, with its line
    ./Tools/i18n.py missing        the keys no language covers yet
    ./Tools/i18n.py check          the same, for a build to fail on
    ./Tools/i18n.py language zh-Hans   the keys one language covers

A sentence with a value in it — Localized("Search \\(v) is downloading…") — is
keyed by its shape, "Search {1} is downloading…", which is what the table has
to say. A sentence shown through one of the shared views (Line, Pill, Caption,
Nothing, Quick, Plate, Hunt) or through announce or an AppKit title is keyed
by the literal it was written with.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources" / "Aura"
RESOURCES = ROOT / "Resources"

# Where a sentence is shown as it is written: the first argument of one of
# these is the sentence. Views SwiftUI makes (Text, Button, Label, Toggle,
# Section, Picker) look literals up themselves, and so do the shared views
# here; announce and an AppKit title go through the same lookup.
SENTENCE_CALLS = (
    "Localized",
    "Text", "Button", "Label", "Toggle", "Section", "Picker", "TextField",
    "Link", "accessibilityLabel",
    "announce", "Line", "Pill", "Caption", "Nothing", "Quick", "Plate",
    "Command", "Menu", "Board", "Row", "Group",
    "heading", "Big", "list", "Quiet", "hint", "Banner", "Toast", "Note",
    "NSAlert",
)
# …and the same for a sentence written after a label, as in prompt: "Search".
SENTENCE_LABELS = ("prompt:", "help:", "title:", "message:", "detail:", "informativeText:",
                    "blurb:", "more:")

# AppKit assigns its own titles: item.title = "…", .label = "…".
ASSIGNMENT = re.compile(r"\.(title|label|message|informativeText|placeholderString)\s*=\s*$")

SKIP_FILES = {"ExtensionShims.swift", "Bench.swift"}


def literal_at(text, i):
    """The Swift string literal starting at text[i] == '"'.

    Returns (body, end) where body is the text between the quotes with the
    escapes left as they are, and end is the index just past the closing
    quote. `\\(…)` is walked through rather than stopped at, so a value inside
    a sentence can hold a quote of its own.
    """
    assert text[i] == '"'
    i += 1
    start = i
    depth = 0
    while i < len(text):
        c = text[i]
        if c == "\\":
            if i + 1 < len(text) and text[i + 1] == "(":
                depth += 1
                i += 2
                continue
            i += 2
            continue
        if depth:
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            elif c == '"':
                _, i = literal_at(text, i)
                continue
            i += 1
            continue
        if c == '"':
            return text[start:i], i + 1
        i += 1
    return text[start:], len(text)


def shape(body):
    """The key a sentence is looked up by: its values become {1}, {2}."""
    out = []
    i = 0
    n = 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            if body[i + 1] == "(":
                # A value: walk to its matching paren, nesting strings as we go.
                depth = 1
                j = i + 2
                while j < len(body) and depth:
                    if body[j] == "\\":
                        j += 2
                        continue
                    if body[j] == '"':
                        _, j = literal_at(body, j)
                        continue
                    if body[j] == "(":
                        depth += 1
                    elif body[j] == ")":
                        depth -= 1
                    j += 1
                n += 1
                out.append("{%d}" % n)
                i = j
                continue
            if body[i + 1] == "u" and i + 2 < len(body) and body[i + 2] == "{":
                close = body.find("}", i + 3)
                if close > 0:
                    out.append(chr(int(body[i + 3:close], 16)))
                    i = close + 1
                    continue
            if body[i + 1] == "n":
                out.append("\\n")
                i += 2
                continue
            out.append(body[i:i + 2])
            i += 2
            continue
        if c == "{":
            out.append("{{")
        else:
            out.append(c)
        i += 1
    return "".join(out)


def sentences(path):
    """Every sentence in one file that has to have a translation."""
    text = path.read_text(encoding="utf-8")
    found = []
    # A command is named by its second word: Command("tabs.search", "Search Tabs…").
    for m in re.finditer(r'Command\(\s*"[^"]*"\s*,\s*("(?:[^"\\]|\\.)*")', text):
        line = text.count("\n", 0, m.start(1)) + 1
        found.append((line, shape(m.group(1)[1:-1])))
    # An enum's own words: `case .never: return "Never"` under a property named
    # title, detail or blurb. Capitalised, so an icon's name (`sun.max`) and a
    # defaults key stay out of the table.
    for m in re.finditer(r'case [^:\n]*:\s*return\s+("(?:[^"\\]|\\.)*")', text):
        body = m.group(1)[1:-1]
        if not body[:1].isupper():
            continue
        # An identifier rather than a word: WebAutomaticTextReplacementEnabled.
        if " " not in body and re.search(r"[a-z][A-Z]", body):
            continue
        back = text[max(0, m.start() - 1200):m.start()]
        if not re.search(r"var (title|detail|blurb|words)\b", back):
            continue
        found.append((text.count("\n", 0, m.start(1)) + 1, shape(body)))
    # A sentence written on a line of its own — the notes of a version, the
    # things a welcome page lists — is one a panel shows as it is.
    for m in re.finditer(r'^[ \t]*("(?:[^"\\]|\\.)*")[,) \t]*$', text, re.M):
        body = m.group(1)[1:-1]
        if looks_like_prose(body):
            found.append((text.count("\n", 0, m.start(1)) + 1, shape(body)))
    i = 0
    while True:
        i = text.find('"', i)
        if i < 0:
            break
        # A raw or a multi-line string — #"…"#, """…""", #"""…"""# — is a
        # script or a pattern rather than a sentence shown to anybody, and its
        # quotes do not pair up the way a sentence's do: skipped whole, or a
        # single `#"\[\d+\]"#` leaves every literal after it read from the
        # wrong end, and the sentences of the file go missing in silence.
        hashes = 0
        while i - hashes - 1 >= 0 and text[i - hashes - 1] == "#":
            hashes += 1
        quote = '"""' if text.startswith('"""', i) else '"'
        if hashes or quote == '"""':
            close = text.find(quote + "#" * hashes, i + len(quote))
            i = len(text) if close < 0 else close + len(quote) + hashes
            continue
        if i and text[i - 1] == "\\":
            i += 1
            continue
        # What comes before the quote decides whether it is a sentence.
        before = text[max(0, i - 160):i]
        line = text.count("\n", 0, i) + 1
        body, end = literal_at(text, i)
        # A sentence inside a comment is an example, not something shown.
        if "//" in before.rsplit("\n", 1)[-1]:
            i = end
            continue
        stripped = before.rstrip()
        wanted = False
        # A sentence after an argument label, wherever it stands: the settings
        # index writes .init(…, title: "…", detail: "…") with commas between
        # fields and its last field without one, so a label is a label either
        # way. Titles and details that reached a view as a String were the one
        # kind of sentence this scan used to miss.
        label = re.search(r"([A-Za-z_][A-Za-z0-9_]*:)\s*$", stripped)
        if label and label.group(1) in SENTENCE_LABELS:
            wanted = True
        if stripped.endswith("("):
            name = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*\($", stripped)
            if name and name.group(1) in SENTENCE_CALLS:
                wanted = True
            if stripped.endswith("Localized("):
                wanted = True
        elif stripped.endswith(","):
            label = re.search(r"([A-Za-z_]+:)\s*$", stripped)
            if label and label.group(1) in SENTENCE_LABELS:
                wanted = True
            # Line("title", "detail") — the second argument is a sentence too.
            call = re.search(r"(Line|Plate)\(\s*\"", before)
            if call:
                wanted = True
        elif ASSIGNMENT.search(stripped):
            wanted = True
        # A sentence asked for where it is shown: "…".localized
        if text[end:end + 10] == ".localized":
            wanted = True
        if wanted and body and not body.startswith(("http", "/", "com.", "#")):
            body_key = shape(body)
            if not ID.match(body_key):
                found.append((line, body_key))
        i = end
    return found


ID = re.compile(r"^[a-z][a-z0-9]*(\.[a-z0-9]+)+$")


def looks_like_prose(text):
    """A sentence written as an array element or a tuple's word: enough words
    to be a sentence, and a capital and a full stop where a sentence has them."""
    words = text.split()
    if len(words) < 4 or len(text) < 20 or len(text) > 600:
        return False
    if not text[0].isupper():
        return False
    if "\\(" in text or "{" in text:
        return True
    return text.rstrip().endswith((".", "…", "?", "!", "”", ":"))


def keys_by_file():
    out = {}
    for path in sorted(SOURCES.glob("*.swift")):
        if path.name in SKIP_FILES:
            continue
        found = sentences(path)
        if found:
            out[path.name] = found
    return out


def table(language):
    """The keys one Localizable.strings covers."""
    path = RESOURCES / f"{language}.lproj" / "Localizable.strings"
    if not path.exists():
        return set()
    keys = set()
    text = path.read_text(encoding="utf-8")
    for m in re.finditer(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"', text, re.M):
        keys.add(m.group(1))
    return keys


def main(argv):
    command = argv[1] if len(argv) > 1 else "scan"
    found = keys_by_file()
    all_keys = {k for entries in found.values() for _, k in entries}

    if command == "scan":
        for name, entries in found.items():
            print(f"# {name}")
            for line, key in entries:
                print(f"{line}\t{key}")
        print(f"\n{len(all_keys)} keys in {len(found)} files", file=sys.stderr)
        return 0

    languages = [a for a in argv[2:] if not a.startswith("-")] or [
        p.stem for p in sorted(RESOURCES.glob("*.lproj"))
    ]
    bad = 0
    for language in languages:
        covered = table(language)
        missing = sorted(all_keys - covered)
        extra = sorted(covered - all_keys)
        print(f"{language}: {len(all_keys) - len(missing)}/{len(all_keys)} covered, "
              f"{len(missing)} missing, {len(extra)} not in the source")
        for key in missing:
            print(f"  missing  {key}")
        for key in extra:
            print(f"  unused   {key}")
        bad += len(missing)
    return 1 if bad and command == "check" else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
