#!/usr/bin/env python3
"""Generate docs/reference/api.html from the package interfaces.

`moon info` writes one `pkg.generated.mbti` per package: the interface the
compiler checks, and the thing `moon check` refuses to let the source drift
from. Reading those files rather than the source means the page cannot claim a
signature the code does not have.

The prose under each entry is the `///` block above the declaration in the
`.mbt` file beside it. An entry without one is rendered bare: a reference page
that invents a sentence for every parameter is a page that lies in a quieter
voice.

    python3 scripts/gen_api_reference.py           # write the page
    python3 scripts/gen_api_reference.py --check   # exit 1 if it is stale

No dependencies beyond the standard library, so CI can run it on the bare
runner image.
"""

import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "reference" / "api.html"


# --------------------------------------------------------------------------
# the interface files
# --------------------------------------------------------------------------

SECTION_RE = re.compile(r"^// (Values|Errors|Types and methods|Type aliases|Traits)$")
TYPE_OPEN_RE = re.compile(r"^pub(?:\(all\))?\s+(struct|enum|suberror)\s+(\w+)\s*\{")
NAME_RE = re.compile(r"^(pub\s+(?:fn|let)\s*(?:\[[^\]]*\])?\s*)(\w+(?:::\w+)?)(.*)$")
ALIAS_RE = re.compile(r"^pub\s+type\s+(\w+)\s*=")
USING_RE = re.compile(r"^pub\s+using\s+@(\w+)\s*\{\s*type\s+(\w+)\s*\}")
DECL_RE = re.compile(
    r"^pub(?:\(all\))?\s+(fn|let|struct|enum|suberror|type)\s*"
    r"(?:\[[^\]]*\])?\s*(\w+(?:::\w+)?)"
)


def split_sections(text):
    """The `.mbti` body, grouped by its `// Values` style headings."""
    out = {}
    current = None
    for line in text.splitlines():
        m = SECTION_RE.match(line)
        if m:
            current = m.group(1)
            out[current] = []
        elif current:
            out[current].append(line)
    return out


def blocks(lines):
    """Entries are separated by a blank line."""
    out, buf = [], []
    for line in lines:
        if line.strip() == "":
            if buf:
                out.append(buf)
                buf = []
        else:
            buf.append(line)
    if buf:
        out.append(buf)
    return out


def collect_docs(directory):
    """`name` -> prose, from the `///` block above each declaration."""
    docs = {}
    for path in sorted(directory.glob("*.mbt")):
        if path.name.endswith(("_test.mbt", "_wbtest.mbt")):
            continue
        pending = []
        in_doc = False
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.startswith("///|"):
                pending = []
                in_doc = False
                continue
            if line.startswith("///"):
                # Keep the indentation inside a fenced block: dropping it would
                # turn a readable example into a run-on line.
                content = line[3:]
                if content.startswith(" "):
                    content = content[1:]
                pending.append(content.rstrip())
                in_doc = True
                continue
            if in_doc and pending:
                m = DECL_RE.match(line)
                if m:
                    name = m.group(2)
                    prose = "\n".join(pending).strip()
                    # Keep the first doc block: a re-declaration in another file
                    # would otherwise overwrite the one readers see.
                    docs.setdefault(name, prose)
            pending = []
            in_doc = False
    return docs


def fn_parts(sig):
    """`(prefix, name, rest)` for a `pub fn` / `pub let` line."""
    m = NAME_RE.match(sig)
    if not m:
        return ("pub ", sig, "")
    return (m.group(1).strip(), m.group(2), m.group(3))


def parse_value(block):
    sig = " ".join(line.strip() for line in block)
    prefix, name, rest = fn_parts(sig)
    return {"kind": "value", "prefix": prefix, "name": name, "rest": rest, "sig": sig}


def parse_type(block):
    head = block[0]
    m = TYPE_OPEN_RE.match(head)
    if not m:
        return None
    kind, name = m.group(1), m.group(2)
    decl = head.split(name)[0].strip()
    close = None
    for i, line in enumerate(block):
        if line.startswith("}"):
            close = i
    body = block[1:close] if close else []
    tail = block[close:] if close else []
    derive = ""
    if tail and "derive(" in tail[0]:
        derive = tail[0].split("derive(", 1)[1].rstrip(")").strip()
    methods, impls = [], []
    for line in tail[1:]:
        if line.startswith("pub fn"):
            prefix, mname, rest = fn_parts(line)
            methods.append(
                {"kind": "value", "prefix": prefix, "name": mname, "rest": rest, "sig": line}
            )
        elif line.startswith("pub impl"):
            impls.append(line)
    fields, variants = [], []
    for line in body:
        text = line.strip()
        if not text:
            continue
        if kind == "struct":
            if " : " in text:
                fname, ftype = text.split(" : ", 1)
                fields.append((fname.strip(), ftype.strip()))
            else:
                fields.append((text, ""))
        else:
            variants.append(text)
    return {
        "kind": kind,
        "name": name,
        "decl": decl,
        "derive": derive,
        "fields": fields,
        "variants": variants,
        "methods": methods,
        "impls": impls,
    }


def parse_package(path):
    text = path.read_text(encoding="utf-8")
    pkg = re.search(r'^package "([^"]+)"', text, re.M).group(1)
    docs = collect_docs(path.parent)
    sections = split_sections(text)

    values = []
    for block in blocks(sections.get("Values", [])):
        if block and block[0].startswith("pub "):
            values.append(parse_value(block))

    errors = []
    for block in blocks(sections.get("Errors", [])):
        item = parse_type(block) if block else None
        if item:
            errors.append(item)

    types = []
    for block in blocks(sections.get("Types and methods", [])):
        if not block:
            continue
        if TYPE_OPEN_RE.match(block[0]):
            item = parse_type(block)
            if item:
                types.append(item)
        else:
            # A lone `pub fn Name::m(...)` with no type above it: keep it in
            # the package's value list rather than dropping it on the floor.
            for line in block:
                if line.startswith("pub fn"):
                    values.append(parse_value([line]))

    aliases, local_types = [], []
    for block in blocks(sections.get("Type aliases", [])):
        for line in block:
            if not line.startswith("pub "):
                continue
            u = USING_RE.match(line)
            if u:
                aliases.append((u.group(2), u.group(1)))
            elif line.startswith("pub type"):
                m = ALIAS_RE.match(line)
                if m:
                    name = m.group(1)
                    local_types.append(
                        {
                            "name": name,
                            "sig": line,
                            "prefix": "pub type",
                            "rest": line[len("pub type ") + len(name):],
                        }
                    )

    traits = [line for line in sections.get("Traits", []) if line.strip()]

    is_root = path.parent == ROOT / "src"
    return {
        "path": pkg,
        "dir": "moonctl" if is_root else path.parent.name,
        "slug": "root" if is_root else path.parent.name,
        "values": values,
        "errors": errors,
        "types": types,
        "aliases": aliases,
        "local_types": local_types,
        "traits": traits,
        "docs": docs,
        "count": len(values) + len(errors) + len(types) + len(local_types),
        "reexports": len(aliases),
    }


# --------------------------------------------------------------------------
# rendering
# --------------------------------------------------------------------------

def inline(text):
    """Escape, then turn `backticks` into code."""
    out = html.escape(text, quote=False)
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", out)


def doc_blocks(text):
    """Split doc prose into paragraphs, `-` lists and fenced code."""
    lines = text.split("\n")
    blocks = []
    i = 0
    while i < len(lines):
        raw = lines[i]
        stripped = raw.strip()
        if stripped.startswith("```"):
            i += 1
            code = []
            while i < len(lines) and not lines[i].strip().startswith("```"):
                code.append(lines[i])
                i += 1
            i += 1
            blocks.append(("code", "\n".join(code).strip("\n")))
        elif stripped.startswith(("- ", "* ")):
            items = []
            while i < len(lines):
                line = lines[i]
                text_ = line.strip()
                if text_.startswith(("- ", "* ")):
                    items.append(text_[2:].strip())
                elif text_ and line.startswith((" ", "\t")) and items:
                    items[-1] += " " + text_
                elif not text_:
                    pass
                else:
                    break
                i += 1
            blocks.append(("list", items))
        elif not stripped:
            i += 1
        else:
            para = []
            while i < len(lines) and lines[i].strip() and not lines[i].strip().startswith(
                ("```", "- ", "* ")
            ):
                para.append(lines[i].strip())
                i += 1
            blocks.append(("para", " ".join(para)))
    return blocks


def doc_html(text):
    if not text:
        return ""
    out = []
    for kind, value in doc_blocks(text):
        if kind == "para":
            out.append('<p class="api-doc">' + inline(value) + "</p>")
        elif kind == "list":
            items = "".join("<li>" + inline(item) + "</li>" for item in value)
            out.append('<ul class="api-doc api-bullets">' + items + "</ul>")
        elif kind == "code" and value.strip():
            out.append('<pre class="api-code">' + html.escape(value) + "</pre>")
    return "".join(out)


def item_id(pkg, kind, name):
    clean = name.replace("::", "-")
    return f'{pkg["slug"]}-{kind}-{clean}'


def sig_html(prefix, name, rest):
    return (
        '<code class="api-sig"><span class="k">' + html.escape(prefix) + "</span> "
        '<span class="n">' + html.escape(name) + "</span>"
        + html.escape(rest) + "</code>"
    )


def value_html(pkg, item):
    doc = doc_html(pkg["docs"].get(item["name"]))
    return (
        f'<div class="api-item" id="{item_id(pkg, "fn", item["name"])}">'
        + sig_html(item["prefix"], item["name"], item["rest"])
        + doc
        + "</div>"
    )


def variants_html(variants):
    if not variants:
        return ""
    rows = "".join("<li><code>" + html.escape(v) + "</code></li>" for v in variants)
    return '<ul class="api-variants">' + rows + "</ul>"


def fields_html(fields):
    if not fields:
        return ""
    rows = "".join(
        "<tr><td><code>" + html.escape(n) + "</code></td><td><code>"
        + html.escape(t) + "</code></td></tr>"
        for n, t in fields
    )
    return (
        '<div class="table-wrap"><table class="api-table">'
        "<thead><tr><th>Field</th><th>Type</th></tr></thead>"
        "<tbody>" + rows + "</tbody></table></div>"
    )


def type_html(pkg, item):
    name = item["name"]
    doc = doc_html(pkg["docs"].get(name))
    head = (
        '<p class="api-sig"><span class="k">'
        + html.escape(item["decl"])
        + '</span> <span class="n">'
        + html.escape(name)
        + "</span>"
        + (' <span class="api-tag">derive(' + html.escape(item["derive"]) + ")</span>" if item["derive"] else "")
        + "</p>"
    )
    body = fields_html(item["fields"]) + variants_html(item["variants"])
    methods = ""
    if item["methods"]:
        rows = "".join(value_html(pkg, m) for m in item["methods"])
        methods = '<h4 class="api-sub">Methods</h4><div class="api-list">' + rows + "</div>"
    impls = ""
    if item["impls"]:
        rows = "".join(
            "<li><code>" + html.escape(i) + "</code></li>" for i in item["impls"]
        )
        impls = '<ul class="api-variants">' + rows + "</ul>"
    return (
        f'<div class="api-type" id="{item_id(pkg, "type", name)}">'
        + head
        + doc
        + body
        + impls
        + methods
        + "</div>"
    )


def plural(n, word):
    return f"{n} {word}" + ("" if n == 1 else "s")


def package_html(pkg):
    out = []
    out.append(
        f'<h2 id="pkg-{pkg["slug"]}">{html.escape(pkg["dir"])}'
        f' <a class="anchor" href="#pkg-{pkg["slug"]}">#</a></h2>'
    )
    surface = plural(pkg["count"], "public item")
    if pkg["reexports"]:
        surface += f", {pkg['reexports']} re-exported type" + (
            "" if pkg["reexports"] == 1 else "s"
        )
    out.append(
        '<p class="api-meta"><code>' + html.escape(pkg["path"]) + "</code>"
        f"<span>{surface}</span></p>"
    )

    if pkg["values"]:
        out.append('<h3 id="pkg-%s-values">Values</h3>' % pkg["slug"])
        out.append('<div class="api-list">')
        out.extend(value_html(pkg, v) for v in pkg["values"])
        out.append("</div>")

    if pkg["errors"]:
        out.append('<h3 id="pkg-%s-errors">Errors</h3>' % pkg["slug"])
        out.append('<div class="api-list">')
        out.extend(type_html(pkg, e) for e in pkg["errors"])
        out.append("</div>")

    if pkg["types"]:
        out.append('<h3 id="pkg-%s-types">Types</h3>' % pkg["slug"])
        out.extend(type_html(pkg, t) for t in pkg["types"])

    if pkg["local_types"]:
        out.append('<h3 id="pkg-%s-aliases">Aliases</h3>' % pkg["slug"])
        out.append('<div class="api-list">')
        for t in pkg["local_types"]:
            doc = doc_html(pkg["docs"].get(t["name"]))
            out.append(
                f'<div class="api-item" id="{item_id(pkg, "alias", t["name"])}">'
                + sig_html(t["prefix"], t["name"], t["rest"])
                + doc
                + "</div>"
            )
        out.append("</div>")

    if pkg["aliases"]:
        out.append(
            '<h3 id="pkg-%s-reexports">Re-exported types</h3>' % pkg["slug"]
        )
        out.append('<div class="table-wrap"><table class="api-table">')
        out.append("<thead><tr><th>Type</th><th>Comes from</th></tr></thead><tbody>")
        for name, source in pkg["aliases"]:
            out.append(
                "<tr><td><code>"
                + html.escape(name)
                + '</code></td><td><a href="#pkg-'
                + source
                + '"><code>'
                + html.escape(source)
                + "</code></a></td></tr>"
            )
        out.append("</tbody></table></div>")

    if pkg["traits"]:
        out.append('<h3 id="pkg-%s-traits">Traits</h3>' % pkg["slug"])
        out.append('<div class="api-list"><div class="api-item">')
        out.append("<ul class=\"api-variants\">")
        out.extend("<li><code>" + html.escape(t) + "</code></li>" for t in pkg["traits"])
        out.append("</ul></div></div>")

    return "\n".join(out)


INTRO = """\
      <h1>Library API</h1>
      <p class="lede">
        Every public value, type and error in the library, package by package: what it
        takes, what it returns, and what it can raise.
      </p>

      <div class="prose">
        <div class="callout">
          <span class="t">Generated from the interfaces</span>
          <p>
            <code>scripts/gen_api_reference.py</code> reads each
            <code>src/*/pkg.generated.mbti</code> — the interface <code>moon info</code>
            writes and <code>moon check</code> holds the source to — and the
            <code>///</code> block above each declaration. Change a signature and this
            page changes with it; CI regenerates it and fails on a diff. An entry
            without prose has none in the source either, and is left bare rather than
            given a sentence invented to fill the space.
          </p>
        </div>

        <h2 id="using">Using it <a class="anchor" href="#using">#</a></h2>
        <p>
          The library is pure: a string in, a string out. Add the module, import the
          package, and call it from a build step, a test or a page.
        </p>
        <div class="code">
          <div class="code-head"><span class="file">main.mbt</span><button class="copy" type="button" data-copy>Copy</button></div>
<pre>let spec = @moonctl.parse(source)
let code = @moonctl.generate(spec)       // a moonapi scaffold, as text
let tree = @moonctl.generate_tree(spec)  // the layered project, file by file</pre>
        </div>
        <p>
          The root package re-exports the types the other packages declare, so a caller
          can name <code>@moonctl.Spec</code>, <code>@moonctl.Route</code> and
          <code>@moonctl.Template</code> without importing anything else. Each
          re-exported type is listed under the package that owns it.
        </p>

        <h2 id="packages">Packages <a class="anchor" href="#packages">#</a></h2>
        <p>
          Each package has one job. The table gives their weight, sorted by import
          path; the sections below give their surface.
        </p>
__PACKAGE_TABLE__
"""

PAGE = """<!doctype html>
<html lang="en" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Library API — moonctl</title>
<meta name="description" content="Every public value, type and error in the moonctl library, generated from the package interfaces.">
<meta name="theme-color" content="#08080d">
<link rel="icon" href="../assets/favicon.svg" type="image/svg+xml">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&family=Space+Grotesk:wght@500;600;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="../assets/site.css">
<script type="module" src="../assets/scrollbar.js"></script>
<script src="../assets/site.js" defer></script>
</head>
<body>
<a class="skip" href="#main">Skip to content</a>

<header class="site-header">
  <div class="container">
    <a class="brand" href="../index.html">
      <span class="mark" aria-hidden="true">
        <svg viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="currentColor" stroke-width="1.6">
          <rect x="2.6" y="2.6" width="18.8" height="18.8" rx="5.4"/>
          <path d="M9.4 8.6 6.8 12l2.6 3.4M14.6 8.6 17.2 12l-2.6 3.4" stroke-linecap="square"/>
        </svg>
      </span>
      moonctl
      <span class="sub">mctl</span>
    </a>
    <nav class="nav" aria-label="Main">
      <a href="../getting-started/installation.html">Docs</a>
      <a href="../guides/api-spec.html">Guides</a>
      <a href="../reference/commands.html" aria-current="true">Reference</a>
      <a href="../getting-started/quick-start.html">Quick start</a>
    </nav>
    <div class="nav-right">
      <button class="icon-btn" type="button" data-theme-toggle aria-label="Switch theme">
        <svg class="i-moon" viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
          <path d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5Z"/>
        </svg>
        <svg class="i-sun" viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round">
          <circle cx="12" cy="12" r="4.2"/>
          <path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M18.4 5.6 17 7M7 17l-1.4 1.4"/>
        </svg>
      </button>
      <a class="icon-btn" href="https://github.com/moonbitstack/moonctl" aria-label="Repository on GitHub">
        <svg viewBox="0 0 16 16" width="18" height="18" fill="currentColor" aria-hidden="true">
          <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/>
        </svg>
      </a>
      <button class="icon-btn nav-toggle" type="button" data-nav-toggle aria-label="Menu" aria-expanded="false">
        <svg viewBox="0 0 24 24" width="19" height="19" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round">
          <path d="M4 7h16M4 12h16M4 17h16"/>
        </svg>
      </button>
    </div>
  </div>
</header>

<div class="docs-wrap">
  <aside class="side" id="side">
    <div class="side-group">
      <span class="label">Getting started</span>
      <a href="../getting-started/installation.html">Installation</a>
      <a href="../getting-started/quick-start.html">Quick start</a>
    </div>
    <div class="side-group">
      <span class="label">Guides</span>
      <a href="../guides/api-spec.html">The .api spec</a>
      <a href="../guides/clients.html">Clients</a>
      <a href="../guides/models.html">Models</a>
      <a href="../guides/gateway.html">Gateway</a>
    </div>
    <div class="side-group">
      <span class="label">Reference</span>
      <a href="../reference/commands.html">Commands</a>
      <a href="../reference/api.html" aria-current="page">Library API</a>
    </div>
  </aside>

  <main class="doc" id="main">
    <button class="side-toggle" type="button" data-side-toggle aria-expanded="false">Contents</button>
__INTRO__
    </div>
__BODY__
    <nav class="pager" aria-label="Pages">
      <a href="../reference/commands.html">
        <span class="dir">Previous</span>
        Commands
      </a>
      <a class="next" href="../index.html">
        <span class="dir">Next</span>
        Home
      </a>
    </nav>
  </main>

  <nav class="toc" aria-label="On this page">
    <span class="label">On this page</span>
    <a href="#using">Using it</a>
    <a href="#packages">Packages</a>
__TOC__
  </nav>
</div>

<footer class="site-footer">
  <div class="container">
    <div class="footer-bottom" style="margin-top:0;border-top:0;padding-top:0">
      <span><a href="../index.html">moonctl</a></span>
      <span>Apache-2.0</span>
      <span>moonbitstack</span>
      <span class="right"><a href="https://github.com/moonbitstack/moonctl">Edit this page on GitHub</a></span>
    </div>
  </div>
</footer>

</body>
</html>
"""


def package_table(pkgs):
    rows = "".join(
        "<tr><td><code>"
        + html.escape(p["path"])
        + '</code></td><td><a href="#pkg-'
        + p["slug"]
        + '">'
        + html.escape(p["dir"])
        + "</a></td><td>"
        + str(p["count"])
        + "</td></tr>"
        for p in pkgs
    )
    return (
        '<div class="table-wrap"><table class="api-table">'
        "<thead><tr><th>Import path</th><th>Package</th><th>Items</th></tr></thead>"
        "<tbody>" + rows + "</tbody></table></div>"
    )


def main():
    check = "--check" in sys.argv

    interfaces = [ROOT / "src" / "pkg.generated.mbti"]
    interfaces += sorted((ROOT / "src").glob("*/pkg.generated.mbti"))
    pkgs = [parse_package(p) for p in interfaces if p.exists()]

    body = "\n".join(package_html(p) for p in pkgs)
    toc = "\n".join(
        '    <a href="#pkg-%s">%s</a>' % (p["slug"], html.escape(p["dir"])) for p in pkgs
    )
    intro = INTRO.replace("__PACKAGE_TABLE__", package_table(pkgs))

    page = (
        PAGE.replace("__INTRO__", intro.rstrip("\n"))
        .replace("__TOC__", toc)
        .replace("__BODY__", body)
    )

    if check:
        current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if current != page:
            rel = OUT.relative_to(ROOT)
            print(f"{rel} is stale: run python3 scripts/gen_api_reference.py", file=sys.stderr)
            return 1
        print(f"{OUT.relative_to(ROOT)} is up to date")
        return 0

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(page, encoding="utf-8", newline="\n")
    print(f"wrote {OUT.relative_to(ROOT)} ({len(pkgs)} packages, {len(page)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
