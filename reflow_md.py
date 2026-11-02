#!/usr/bin/env python3
"""reflow_md.py — unwrap hard-wrapped markdown prose so it flows to the reader's width.

    reflow_md.py FILE...            rewrite, but only if provably lossless
    reflow_md.py --check FILE...    show what would change, write nothing
    reflow_md.py --dir PATH         every .md under PATH

WHAT IT DOES AND WHY YOU ASKED FOR IT.

These documents are hard-wrapped at about 105 characters. In a window narrower than
that, every source line soft-wraps into one long line plus a short remainder, which is
the alternating ragged pattern you saw. Nothing is broken — markdown ignores single
newlines, so the RENDERED output was always correct — but reading the raw file in a
narrow window looks bad, and you read these raw.

So: one line per paragraph, and one line per list item. It then flows to whatever width
the window is, at any width, forever, and it renders exactly as it did before.

⛔ THE HAZARD, AND IT IS NOT HYPOTHETICAL.

Jeremy unwrapped a paragraph by hand and produced *"notes every filein it"* — two
wrapped lines joined with no space between them. A word had been silently destroyed
in the middle of a sentence that still looked plausible. That is the whole risk of
this operation: it fails quietly and it fails in the middle of prose, where nobody
proofreads because nothing looks wrong.

⭐ SO THIS TOOL PROVES ITS WORK RATHER THAN ASSERTING IT. Before writing, it reduces
both the old and new text to a canonical form — every run of whitespace collapsed to
one space — and refuses to write unless they are IDENTICAL. Reflowing may only ever
change whitespace. If a single character of actual text differs, the file is left
exactly as it was and the difference is reported. `filein` would be caught by this,
because "file in" and "filein" are not the same string.

⛔ WHAT IT REFUSES TO TOUCH, because in these the line break IS the meaning:

    fenced code (``` and ~~~)      any indented line outside a list item
    tables (any line with |)       nested list items
    an unindented line under a     a quoted message keeps its own line breaks
      list item (lazy continuation)
    headings, --- rules, blank     blockquotes (>)
    YAML front matter              HTML blocks (< at column 0)
    a line ending in two spaces    ← markdown's own hard-break syntax
    a leading header block         To: / Subject: / Date: lines before the first blank line
    a `Key: value` field           anywhere a wrapped line would otherwise start
    a === setext underline         joining it would turn the heading into prose

Added 2026-10-18, from an email draft: `To:` and `Subject:` were joined into one line, and a
two-space-indented attachment list was folded into the "Attachments:" line above it. Both
passed the whitespace proof, because both are whitespace changes. The proof guards the
text; these two rules guard the layout the writer meant.

A paragraph adjacent to any of those is still reflowed; only the special block is
left alone. When in doubt it does nothing, because a silent corruption in a case
document costs incomparably more than a ragged line.
"""
import argparse, re, sys
from pathlib import Path

FENCE = re.compile(r"^\s*(```|~~~)")
HEADING = re.compile(r"^\s{0,3}#{1,6}\s")
RULE = re.compile(r"^\s{0,3}([-*_])\s*(\1\s*){2,}$")
LIST = re.compile(r"^\s*([-*+]|\d{1,9}[.)])\s+")
QUOTE = re.compile(r"^\s*>")
HTML = re.compile(r"^<")
SETEXT = re.compile(r"^\s{0,3}=+\s*$")   # the === under a setext heading
INDENT = re.compile(r"^\s")                # any leading whitespace
HEADER = re.compile(r"^[A-Za-z][A-Za-z-]{0,30}:(\s|$)")   # To: / Subject: / Date:


def canonical(s: str) -> str:
    """Everything that is not whitespace, in order. The proof lives here."""
    return " ".join(s.split())


def special(line: str) -> bool:
    """True if this line's break carries meaning and must survive untouched."""
    if not line.strip():
        return True
    if (HEADING.match(line) or RULE.match(line) or LIST.match(line)
            or QUOTE.match(line) or HTML.match(line) or INDENT.match(line)
            or SETEXT.match(line)):
        return True
    if "|" in line:                       # a table row, or something table-like
        return True
    if line.endswith("  "):               # markdown's explicit hard line break
        return True
    return False


def list_continuation(line: str, content_col: int) -> bool:
    """True if `line` is the wrapped remainder of the list item above it.

    A wrapped line inside a list item is indented under the item's text, and that
    indentation is what marks it as belonging to the item. A line at column 0 is a
    "lazy" continuation: markdown renders it as part of the item, but it is also what a
    verbatim quoted message looks like when it carries its own line breaks, and one of
    those is an iMessage transcript in the case tree. So column 0 is left alone — the
    same conservatism `special()` already applies to indented prose outside a list.

    What is NOT a continuation is anything whose break carries meaning: a nested item,
    a fence, a table, a heading, a rule, a quote, an HTML element on its own line, a
    `Key: value` field, an explicit two-space break, or an indent deep enough to be a
    code block inside the item.
    """
    if not line.strip():
        return False
    if (LIST.match(line) or FENCE.match(line) or HEADING.match(line) or RULE.match(line)
            or QUOTE.match(line) or HTML.match(line) or SETEXT.match(line)):
        return False
    if line.strip().startswith("<"):            # an HTML element on a line of its own
        return False
    if "|" in line:
        return False
    if line.endswith("  "):
        return False
    if HEADER.match(line.strip()):              # a field, not a sentence
        return False
    indent = len(line) - len(line.lstrip())
    if indent == 0:                             # a lazy continuation, or anything at all
        return False
    if indent >= content_col + 4:               # indented code inside the item
        return False
    return True


def reflow(text: str) -> str:
    lines = text.split("\n")
    out, para, in_fence, i = [], [], False, 0
    # ⛔ LIST CONTINUATIONS, twice over.
    #
    # 2026-08-18, the first test that included a list: a list item may continue on the
    # next line with only two spaces of indent — or none at all, a lazy continuation.
    # Neither looks special to a line-by-line check, so both were being swept into the
    # surrounding paragraph and re-emitted stripped. It rendered identically, so the
    # whitespace-only proof passed it. Rendering the same is not the same as leaving
    # the source alone. The rule then became: once a list starts, everything up to the
    # next blank line is left exactly as it is.
    #
    # 2026-11-02, Athens talk prompt: that rule is why a file whose ONLY wrapping was
    # inside its bullets came back "already fine" while still ragged on screen. A
    # bullet's own wrapped remainder is prose and must be joined into the item. So the
    # item is now gathered and emitted as one line, and only a line that is genuinely
    # not its continuation (list_continuation says so) ends the item and goes through
    # untouched — along with everything after it up to the next blank line, which keeps
    # the 2026-08-18 protection for a table, a fence or a sub-block inside a list.
    item = []                  # the list item being gathered
    item_col = 0               # the column its text starts at
    in_list = False            # inside a list block, until the next blank line
    passthrough = False        # a non-prose block inside a list: leave it alone

    def flush():
        if para:
            out.append(" ".join(x.strip() for x in para))
            para.clear()

    def flush_item():
        if item:
            if len(item) == 1:
                out.append(item[0])
            else:
                out.append(item[0].rstrip() + " " + " ".join(x.strip() for x in item[1:]))
            item.clear()

    # YAML front matter is passed through verbatim
    if lines and lines[0].strip() == "---":
        for j in range(1, len(lines)):
            if lines[j].strip() in ("---", "..."):
                out.extend(lines[:j + 1])
                i = j + 1
                break
    # An email-style header block (every line up to the first blank one looks like
    # `Key: value`) is passed through verbatim: each line is its own field.
    j = i
    while j < len(lines) and lines[j].strip():
        j += 1
    if j > i and all(HEADER.match(lines[k]) for k in range(i, j)):
        out.extend(lines[i:j])
        i = j

    while i < len(lines):
        ln = lines[i]
        m = None if in_fence else LIST.match(ln)
        if FENCE.match(ln):
            flush(); flush_item()
            in_fence = not in_fence
            in_list = passthrough = False
            out.append(ln)
        elif in_fence:
            out.append(ln)
        elif not ln.strip():
            flush(); flush_item()
            in_list = passthrough = False
            out.append(ln)
        elif m:
            flush(); flush_item()
            item.append(ln)
            item_col = len(m.group(0))
            in_list, passthrough = True, False
            # An item line ending in two spaces is markdown's hard break: nothing may be
            # joined after it, and the rest of the block is left as it was typed.
            if ln.endswith("  "):
                flush_item()
                passthrough = True
        elif in_list and not passthrough and list_continuation(ln, item_col):
            if item:
                item.append(ln)
            else:
                out.append(ln)
        elif in_list:
            flush_item()
            passthrough = True
            out.append(ln)
        elif special(ln):
            flush()
            out.append(ln)
        else:
            para.append(ln)
        i += 1
    flush(); flush_item()
    return "\n".join(out)


def process(p: Path, check: bool, verbose=True):
    try:
        orig = p.read_text()
    except Exception as e:
        print(f"  skip  {p.name}: {type(e).__name__}")
        return None
    new = reflow(orig)
    if new == orig:
        return False
    # ⭐ THE PROOF. Reflowing may change whitespace and nothing else.
    if canonical(orig) != canonical(new):
        a, b = canonical(orig), canonical(new)
        k = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]),
                 min(len(a), len(b)))
        print(f"  ⛔ REFUSED  {p.name}: text would change, not just whitespace")
        print(f"       before: …{a[max(0,k-45):k+45]}…")
        print(f"       after : …{b[max(0,k-45):k+45]}…")
        return None
    joined = len(orig.split("\n")) - len(new.split("\n"))
    if verbose:
        print(f"  {'would join' if check else 'joined'} {joined:>4} line(s)  {p.name}")
    if not check:
        tmp = p.with_suffix(p.suffix + ".tmp")
        tmp.write_text(new)
        tmp.replace(p)
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("files", nargs="*")
    ap.add_argument("--dir")
    ap.add_argument("--check", action="store_true", help="write nothing")
    a = ap.parse_args()
    targets = [Path(f) for f in a.files]
    if a.dir:
        root = Path(a.dir).expanduser()
        targets = [p for p in sorted(root.rglob("*.md"))
                   if "_to_delete" not in str(p) and ".bak" not in p.name]
    if not targets:
        ap.error("give me files or --dir")
    changed = refused = same = 0
    for p in targets:
        r = process(p, a.check)
        if r is None:   refused += 1
        elif r:         changed += 1
        else:           same += 1
    verb = "would be reflowed" if a.check else "reflowed"
    print(f"\n  {changed} {verb} · {same} already fine · {refused} refused")
    if a.check and changed:
        print("  Nothing was written. Re-run without --check to apply.")
    if refused:
        print("  A refusal means the text itself would have changed. That file is "
              "untouched\n  and needs a human — it is exactly the 'filein' failure.")


if __name__ == "__main__":
    main()
