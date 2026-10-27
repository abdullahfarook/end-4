#!/usr/bin/env python3
"""Local notes for the Gist widget: plain files in a folder, shown and edited like gists (never sent to GitHub unless uploaded).
A file directly in DIR is a one-file note; a subfolder is a multi-file note (its regular, non-hidden files). Descriptions and
creation times live in DIR/.gist-widget.json. Hidden files are ignored.
  index DIR             JSON list in the shape of the widget's gist index (ids "local:<name>"), newest first
  save DIR [ID] < p     apply p = {description, files: {name: {content} | {filename, content} | null}} (GitHub PATCH semantics);
                        no ID creates a note (one file: a file in DIR, more: a folder). Prints "ID\tPATH\tUPDATED_AT"
  delete DIR ID         move the note to the trash (gio trash; removed if that fails)
  payload DIR ID PUB    the POST /gists payload for uploading the note (PUB: public|secret)
"""
import json, os, re, shutil, subprocess, sys, time
from datetime import datetime, timezone

CLIP = 200000
META = ".gist-widget.json"
LANG = {"md": "Markdown", "markdown": "Markdown", "txt": "Text", "py": "Python", "sh": "Shell", "bash": "Shell", "fish": "fish",
        "zsh": "Shell", "ps1": "PowerShell", "js": "JavaScript", "mjs": "JavaScript", "ts": "TypeScript", "tsx": "TSX", "jsx": "JSX",
        "json": "JSON", "qml": "QML", "yml": "YAML", "yaml": "YAML", "toml": "TOML", "ini": "INI", "conf": "INI", "cs": "C#",
        "html": "HTML", "css": "CSS", "scss": "SCSS", "sql": "SQL", "lua": "Lua", "go": "Go", "rs": "Rust", "c": "C", "h": "C",
        "cpp": "C++", "hpp": "C++", "java": "Java", "kt": "Kotlin", "rb": "Ruby", "php": "PHP", "xml": "XML", "csv": "CSV",
        "dockerfile": "Dockerfile", "nix": "Nix", "vim": "Vim Script", "diff": "Diff", "patch": "Diff"}


def die(msg):
    print(msg, file=sys.stderr); sys.exit(1)


def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def lang(name):
    base = name.lower()
    return LANG.get(base.rsplit(".", 1)[-1] if "." in base else base, "")


def valid(name):
    return name not in ("", ".", "..") and "/" not in name and "\0" not in name and not name.startswith(".")


def load_meta(d):
    try:
        with open(os.path.join(d, META)) as f:
            m = json.load(f)
        return m if isinstance(m, dict) else {}
    except (OSError, ValueError):
        return {}


def write(path, text):
    tmp = os.path.join(os.path.dirname(path), f".{os.path.basename(path)}.part")
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)


def save_meta(d, m):
    write(os.path.join(d, META), json.dumps(m, indent=1, sort_keys=True))


def note_files(path):
    """[(filename, fullpath)] of a note (a file or a folder)."""
    if os.path.isfile(path):
        return [(os.path.basename(path), path)]
    out = []
    for n in sorted(os.listdir(path)):
        p = os.path.join(path, n)
        if valid(n) and os.path.isfile(p):
            out.append((n, p))
    return out


def updated(path):
    ts = [os.stat(p).st_mtime for _, p in note_files(path)] or [os.stat(path).st_mtime]
    return iso(max(ts))


def note(d, name, meta):
    path = os.path.join(d, name)
    m = meta.get(name, {})
    files = []
    for fn, p in note_files(path):
        try:
            with open(p, "rb") as f:
                raw = f.read(CLIP * 4 + 1)
            text = raw.decode("utf-8", "replace")
        except OSError:
            continue
        size = os.stat(p).st_size
        files.append({"filename": fn, "language": lang(fn), "size": size, "raw_url": p, "truncated": False,
                      "clipped": len(text) > CLIP or size > len(raw), "content": text[:CLIP]})
    up = updated(path)
    return {"id": "local:" + name, "local": True, "description": m.get("description", ""), "public": False, "html_url": path,
            "created_at": m.get("created_at") or up, "updated_at": up, "comments": 0, "owner": "", "files": files}


def index(d):
    os.makedirs(d, exist_ok=True)
    meta = load_meta(d)
    out = []
    for n in os.listdir(d):
        p = os.path.join(d, n)
        if valid(n) and (os.path.isfile(p) or os.path.isdir(p)):
            g = note(d, n, meta)
            if g["files"]:
                out.append(g)
    out.sort(key=lambda g: g["updated_at"], reverse=True)
    return out


def resolve(d, nid):
    name = nid[6:] if nid.startswith("local:") else nid
    if not valid(name):
        die(f"bad note id: {nid}")
    path = os.path.join(d, name)
    if not os.path.exists(path):
        die("this note no longer exists")
    return name, path


def unique(d, base):
    stem, ext = (base.rsplit(".", 1) + [""])[:2] if "." in base else (base, "")
    cand, i = base, 2
    while os.path.exists(os.path.join(d, cand)):
        cand = f"{stem}-{i}" + (f".{ext}" if ext else ""); i += 1
    return cand


def slug(s):
    s = re.sub(r"[^\w.\- ]+", "", s).strip().replace(" ", "-")[:60].lstrip(".")
    return s or "note-" + time.strftime("%Y%m%d-%H%M%S")


def save(d, nid, p):
    os.makedirs(d, exist_ok=True)
    files = p.get("files") or {}
    for k, v in files.items():
        if not valid(k) or (v and "filename" in v and not valid(v["filename"])):
            die(f"invalid file name: {v.get('filename') if v and 'filename' in v else k}")
    meta = load_meta(d)
    now = iso(time.time())
    if not nid:   # new note
        if not files:
            die("a note needs at least one file")
        if len(files) == 1:
            fn = next(iter(files))
            name = unique(d, fn)
            write(os.path.join(d, name), files[fn].get("content", ""))
        else:
            name = unique(d, slug(p.get("description") or next(iter(files)).rsplit(".", 1)[0]))
            os.makedirs(os.path.join(d, name))
            for fn, v in files.items():
                write(os.path.join(d, name, fn), v.get("content", ""))
        meta[name] = {"description": p.get("description", ""), "created_at": now}
    else:
        name, path = resolve(d, nid)
        m = meta.pop(name, {})
        if os.path.isfile(path):
            # a one-file note: stays a file while it has one file, else becomes a folder named after it
            cur = os.path.basename(path)
            names = {cur}
            for k, v in files.items():
                if v is None:
                    names.discard(k)
                elif k in names and "filename" in v:
                    names.discard(k); names.add(v["filename"])
                else:
                    names.add(v.get("filename", k))
            if not names:
                die("a note needs at least one file")
            if len(names) == 1:
                (new,) = names
                if new != cur and os.path.exists(os.path.join(d, new)):
                    die(f"\"{new}\" already exists in {d}")
                if cur in files and files[cur] is None:   # the file was replaced by a new one
                    os.remove(path)
                    content = files.get(new, {}).get("content", "")
                else:
                    content = (files.get(cur) or {}).get("content")
                    if new != cur:
                        os.replace(path, os.path.join(d, new))
                path, name = os.path.join(d, new), new
                if content is not None:
                    write(path, content)
            else:
                folder = unique(d, slug(p.get("description") or cur.rsplit(".", 1)[0]))
                os.makedirs(os.path.join(d, folder))
                os.replace(path, os.path.join(d, folder, cur))
                name, path = folder, os.path.join(d, folder)
        if os.path.isdir(path):
            have = {fn for fn, _ in note_files(path)}
            for k, v in files.items():   # removals and renames first, so a rename can reuse a removed name
                if v is None and k in have:
                    os.remove(os.path.join(path, k)); have.discard(k)
            for k, v in files.items():
                if v is None:
                    continue
                target = v.get("filename", k)
                if k in have and target != k:
                    if os.path.exists(os.path.join(path, target)):
                        die(f"two files are named \"{target}\"")
                    os.replace(os.path.join(path, k), os.path.join(path, target)); have.discard(k); have.add(target)
                if "content" in v:
                    write(os.path.join(path, target), v["content"]); have.add(target)
            if not have:
                die("a note needs at least one file")
        m["description"] = p.get("description", m.get("description", ""))
        m.setdefault("created_at", now)
        meta[name] = m
    save_meta(d, meta)
    path = os.path.join(d, name)
    print(f"local:{name}\t{path}\t{updated(path)}")


def delete(d, nid):
    name, path = resolve(d, nid)
    if subprocess.run(["gio", "trash", path], capture_output=True).returncode != 0:
        shutil.rmtree(path) if os.path.isdir(path) else os.remove(path)
    meta = load_meta(d)
    if meta.pop(name, None) is not None:
        save_meta(d, meta)


def payload(d, nid, pub):
    name, path = resolve(d, nid)
    files = {}
    for fn, p in note_files(path):
        with open(p, encoding="utf-8", errors="replace") as f:
            c = f.read()
        if c.strip():
            files[fn] = {"content": c}
    if not files:
        die("GitHub doesn't allow empty files; this note has nothing to upload")
    print(json.dumps({"description": load_meta(d).get(name, {}).get("description", ""), "public": pub == "public", "files": files}))


def main():
    a = sys.argv[1:]
    if len(a) < 2:
        die(__doc__)
    cmd, d = a[0], os.path.expanduser(a[1])
    if cmd == "index":
        print(json.dumps(index(d)))
    elif cmd == "save":
        save(d, a[2] if len(a) > 2 else "", json.load(sys.stdin))
    elif cmd == "delete" and len(a) > 2:
        delete(d, a[2])
    elif cmd == "payload" and len(a) > 3:
        payload(d, a[2], a[3])
    else:
        die(__doc__)


if __name__ == "__main__":
    os.umask(0o077)
    main()
