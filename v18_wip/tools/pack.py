#!/usr/bin/env python3
"""Build the Ronin's Edge release zips and prove Godot's "Import .zip" accepts the play zip.

    python3 tools/pack.py [--out DIR] [--name RoninsEdge_v11] [--extract-to DIR]

Writes two files into DIR (default: the folder above the repo):
  <name>_play.zip       the Godot project only, inside ONE top-level folder (RoninsEdge/) that holds
                        project.godot, with an explicit directory entry for every folder.
                        Works with Project Manager > Import > (pick the .zip) and with a normal
                        unzip + Import project.godot.
  <name>_dev_tools.zip  v2/ v3/ v4/ tools/ generator scripts and logs (need Blender; not for Godot).

Why this exists: Godot 4.3 treats the folder that holds project.godot as the project root, strips
that prefix from every entry and writes what is left below the install path WITHOUT creating parent
folders. Entries outside the project folder, or inside folders that have no directory entry, land in
"The following files failed extraction from package" and the import is aborted. godot_import_check()
is a line-by-line port of that code (editor/project_manager/project_dialog.cpp, 4.3-stable).
"""
import argparse, hashlib, os, re, sys, tempfile, time, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOP = "RoninsEdge"
SKIP_DIRS = {".godot", "__pycache__", ".git"}
SKIP_SUFFIX = (".bak", ".blend1", ".tmp")
# local render-test settings (software Vulkan): never ship
SKIP_NAMES = {"override.cfg"}
RESERVED = {"con", "prn", "aux", "nul", *(f"com{i}" for i in range(1, 10)), *(f"lpt{i}" for i in range(1, 10))}


def collect(base, only=None):
    """(absolute path, posix path relative to base) for every shippable file below base."""
    out = []
    for p in sorted(base.rglob("*")):
        rel = p.relative_to(base)
        if not p.is_file() or any(part in SKIP_DIRS for part in rel.parts) or p.name.endswith(SKIP_SUFFIX) \
                or p.name in SKIP_NAMES:
            continue
        if only and not only(rel):
            continue
        out.append((p, rel.as_posix()))
    return out


def tools_files():
    files = [(ROOT / "README.txt", "README.txt")]
    files += [(p, "v2/" + p.name) for p in sorted((ROOT / "v2").glob("*.py"))]
    files += [(p, "v2/logs/" + rel) for p, rel in collect(ROOT / "v2" / "logs")]
    files += [(p, "v3/" + rel) for p, rel in collect(ROOT / "v3", only=lambda r: r.suffix == ".py" and len(r.parts) == 1)]
    if (ROOT / "v4").is_dir():  # v0.12+ character / weapon builders (their CC0 source packs are not shipped)
        files += [(p, "v4/" + rel) for p, rel in collect(ROOT / "v4", only=lambda r: r.suffix in (".py", ".sh") and len(r.parts) == 1)]
    files += [(p, "tools/" + rel) for p, rel in collect(ROOT / "tools")]
    return files


def write_zip(out, files, prefix=""):
    names = [prefix + arc for _, arc in files]
    dirs = sorted({"/".join(n.split("/")[:k]) + "/" for n in names for k in range(1, len(n.split("/")))})
    now = time.localtime()[:6]
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=6, strict_timestamps=False) as z:
        for d in dirs:  # a parent folder always sorts before its children
            zi = zipfile.ZipInfo(d, now)
            zi.external_attr = (0o40755 << 16) | 0x10
            z.writestr(zi, b"")
        for src, arc in files:
            z.write(src, prefix + arc)
    return names, dirs


def godot_import_check(zip_path, dest):
    """Port of ProjectDialog MODE_INSTALL (4.3). Returns (zip_root, failed_files)."""
    def base_dir(n):
        i = n.rfind("/")
        return n[:i] if i >= 0 else ""

    def path_join(a, b):
        return a + b if (a.endswith("/") or b.startswith("/")) else a + "/" + b

    z = zipfile.ZipFile(zip_path)
    root = next((base_dir(i.filename) for i in z.infolist() if i.filename.rsplit("/", 1)[-1] == "project.godot"), None)
    if root is None:
        raise SystemExit("FAIL: zip has no project.godot")
    os.makedirs(dest, exist_ok=True)
    failed = []
    for info in z.infolist():
        name = info.filename
        rel = name[len(root):] if name.startswith(root) else name  # String::trim_prefix
        if rel == "":
            continue
        full = path_join(dest, rel)
        if rel.endswith("/"):
            try:
                os.mkdir(full)  # DirAccess::make_dir is NOT recursive
            except OSError:
                pass
        else:
            try:
                with open(full, "wb") as f:
                    f.write(z.read(info))
            except OSError:
                failed.append(rel)
    return root, failed


def windows_problems(names):
    bad, seen = [], {}
    for n in names:
        for part in n.rstrip("/").split("/"):
            if re.search(r'[<>:"|?*\x00-\x1f]', part) or part.endswith((".", " ")) or part.split(".")[0].lower() in RESERVED:
                bad.append(n)
                break
        k = n.lower()
        if k in seen and seen[k] != n:
            bad.append(f"{n} collides with {seen[k]}")
        seen[k] = n
    return bad


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT.parent))
    ap.add_argument("--name", default="RoninsEdge_v11")
    ap.add_argument("--extract-to", default=None, help="keep the simulated Godot extraction here")
    a = ap.parse_args()
    out = Path(a.out)
    play, dev = out / f"{a.name}_play.zip", out / f"{a.name}_dev_tools.zip"

    game = collect(ROOT / "game")
    if not any(rel == "project.godot" for _, rel in game):
        sys.exit("FAIL: game/project.godot missing")
    names, dirs = write_zip(play, game, TOP + "/")
    dnames, ddirs = write_zip(dev, tools_files())

    dest = a.extract_to or tempfile.mkdtemp(prefix="godot_zip_check_")
    if a.extract_to and os.path.exists(dest):
        sys.exit(f"FAIL: --extract-to {dest} already exists; pass an empty/new path")
    root, failed = godot_import_check(play, dest)
    missing = [rel for _, rel in game if not os.path.isfile(os.path.join(dest, rel)) or
               os.path.getsize(os.path.join(dest, rel)) != os.path.getsize(ROOT / "game" / rel)]
    bad = windows_problems(names + dnames)
    print(f"play zip : {play.name}  {play.stat().st_size:,} bytes  {len(names)} files + {len(dirs)} dir entries  sha256 {sha(play)[:16]}")
    print(f"dev zip  : {dev.name}  {dev.stat().st_size:,} bytes  {len(dnames)} files + {len(ddirs)} dir entries")
    print(f"Godot import simulation: zip_root={root!r}  failed extractions={len(failed)}  missing/short after extract={len(missing)}")
    print(f"Windows-safe names: {'OK' if not bad else bad[:5]}  (longest play path {max(map(len, names))} chars)")
    if failed or missing or bad:
        for f in (failed + missing)[:16]:
            print("  !!", f)
        sys.exit("FAIL")
    print("PASS  extracted copy:", dest)


if __name__ == "__main__":
    main()
