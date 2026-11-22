"""Put the licence header from HEADER.txt at the top of every Ada source in src/.

FILE_DESCRIPTION in the template is replaced by "<project> - <Ada unit name>".
Re-runnable: an existing header (the block between the two '-- ****' lines at the
top of a file) is replaced, never duplicated.
"""
import pathlib, re, sys

PROJECT = "PAVÉ"
root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
template = (root / "HEADER.txt").read_text(encoding="utf-8").rstrip("\n") + "\n"
RULE = "-- " + "*" * 10

def unit_name(text):
    m = re.search(r"^\s*(?:private\s+)?(?:package\s+body|package|procedure|function)\s+([\w.]+)",
                  text, re.M | re.I)
    return m.group(1) if m else None

def strip_header(lines):
    if lines and lines[0].startswith(RULE):
        for i in range(1, len(lines)):
            if lines[i].startswith(RULE):
                rest = lines[i + 1:]
                while rest and rest[0].strip() == "":
                    rest = rest[1:]
                return rest
    return lines

for path in sorted((root / "src").glob("*.ad[sb]")):
    text = path.read_text(encoding="utf-8")
    body = strip_header(text.splitlines(keepends=True))
    unit = unit_name("".join(body))
    if not unit:
        print(f"skip {path.name}: no unit found"); continue
    header = template.replace("FILE_DESCRIPTION", f"{PROJECT} - {unit}")
    new = header + "\n" + "".join(body)
    if new != text:
        path.write_text(new, encoding="utf-8")
        print(f"{path.name:20s} {unit}")
