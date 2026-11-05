"""Move the versions generated projects import to the newest tags, in src/scaffold/manifest.mbt.

A pin left behind breaks generated projects when the compiler moves on, since an old release of a
dependency no longer builds. CI's scaffold job then fails here rather than in someone's first project.
Needs the GitHub CLI.

    python scripts/update_pins.py
"""
import json
import pathlib
import re
import subprocess

MANIFEST = pathlib.Path(__file__).resolve().parent.parent / "src/scaffold/manifest.mbt"
# Modules that live in another module's repository, and tag as `<module>-v<version>`.
HOMES = {"moondb": "moondb", "moonsqlite": "moondb", "moonpostgres": "moondb", "moonmysql": "moondb"}


def newest(module):
    home = HOMES.get(module, module)
    prefix = f"{module}-v" if module in HOMES else "v"
    out = subprocess.run(["gh", "api", "--paginate", f"repos/moonbitstack/{home}/tags", "-q", ".[].name"],
                         check=True, capture_output=True, text=True).stdout
    versions = [t[len(prefix):] for t in out.split() if t.startswith(prefix)]
    return max(versions, key=lambda v: [int(x) for x in v.split(".")])


text = MANIFEST.read_bytes().decode()
changed = {}


def bump(match):
    module, old = match.group(1), match.group(2)
    new = newest(module)
    if new != old:
        changed[module] = f"{old} -> {new}"
    return f'"moonbitstack/{module}": "{new}"'


text = re.sub(r'"moonbitstack/([\w-]+)": "([\d.]+)"', bump, text)
MANIFEST.write_bytes(text.encode())
print(json.dumps(changed, indent=2))
