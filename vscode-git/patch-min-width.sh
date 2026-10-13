#!/bin/sh
# Lowers VS Code's minimum window width (400 -> 215) so the Git panel can shrink to the sidebar. Run as root (pkexec). Idempotent.
# Two copies of the constant: main process (mainImpl.js) and the workbench, which calls setMinimumSize at runtime.
# Undo: reinstall visual-studio-code-bin, or restore the backups from ~/backups/vscode-minwidth/.
set -eu
python3 - <<'PY'
import sys, re
out = "/usr/share/code/resources/app/out/"
W = "vs/workbench/workbench.desktop.main.js"
# (file, regex, replacement, regex that matches when already patched). Minified identifiers change between releases, so they are wildcards.
for f, old, new, done in [
        ("mainImpl.js", r"(=\{WIDTH:)400(,)", r"\g<1>215\2", r"=\{WIDTH:215,"),
        # sidebar minimum width 170 -> 392 (the Git panel's width) and maximum 392 too: extra window width always goes to the editor, and an opening editor cannot squeeze the sidebar
        (W, r"(SidebarTitle,e,t,i,n,r,a,c,l,u,p,m,f,g\);this\.minimumWidth=)170;this\.maximumWidth=Number\.POSITIVE_INFINITY;", r"\g<1>392;this.maximumWidth=392;", r"SidebarTitle,e,t,i,n,r,a,c,l,u,p,m,f,g\);this\.minimumWidth=392;this\.maximumWidth=392;"),
        # minimum editor width 220 -> 1: opening a file must not squeeze the sidebar before the window widens
        (W, r"(var [\w$]+=new [\w$]+\()220(,70\),)", r"\g<1>1\2", r"var [\w$]+=new [\w$]+\(1,70\),"),
        # hiding the editor area must not force the bottom panel open (sidebar-only Git panel)
        (W, r'e&&!this\.isVisible\("workbench\.parts\.panel"\)&&!this\.isAuxiliaryBarMaximized\(\)&&this\.setPanelHidden\(!1,!0\)\)\}getLayoutClasses', "0)}getLayoutClasses", r"0\)\}getLayoutClasses"),
        (W, r"(=\{WIDTH:)400(,WIDTH_WITH_VERTICAL_PANEL:600,)", r"\g<1>215\2", r"=\{WIDTH:215,WIDTH_WITH_VERTICAL_PANEL:600,")]:
    s = open(out + f, encoding="utf-8").read()
    if re.search(done, s): continue
    s, n = re.subn(old, new, s)
    if n != 1: sys.exit(f"patch-min-width: pattern {old[:40]!r} matched {n} times in {f} (VS Code changed?)")
    open(out + f, "w", encoding="utf-8").write(s)
import base64, hashlib, re
# VS Code warns "installation appears to be corrupt" when a checksummed file changes: refresh the stored checksum.
pj = "/usr/share/code/resources/app/product.json"
rel = "vs/workbench/workbench.desktop.main.js"
digest = base64.b64encode(hashlib.sha256(open(out + rel, "rb").read()).digest()).decode().rstrip("=")
t = open(pj, encoding="utf-8").read()
t2 = re.sub(r'("%s"\s*:\s*")[^"]*(")' % re.escape(rel), lambda m: m.group(1) + digest + m.group(2), t)
if t2 != t: open(pj, "w", encoding="utf-8").write(t2)
PY
