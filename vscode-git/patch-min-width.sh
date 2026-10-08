#!/bin/sh
# Lowers VS Code's minimum window width (400 -> 215) so the Git panel can shrink to the sidebar. Run as root (pkexec). Idempotent.
# Two copies of the constant: main process (mainImpl.js) and the workbench, which calls setMinimumSize at runtime.
# Undo: reinstall visual-studio-code-bin, or restore the backups from ~/backups/vscode-minwidth/.
set -eu
python3 - <<'PY'
import sys
out = "/usr/share/code/resources/app/out/"
for f, old, new in [("mainImpl.js", "xw={WIDTH:400,", "xw={WIDTH:215,"),
                    # ...and maximum 392 too: the sidebar is exactly the Git panel's width, extra window width always goes to the editor
                    ("vs/workbench/workbench.desktop.main.js", "N.SidebarTitle,e,t,i,n,r,a,c,l,u,p,m,f,g);this.minimumWidth=392;this.maximumWidth=Number.POSITIVE_INFINITY;", "N.SidebarTitle,e,t,i,n,r,a,c,l,u,p,m,f,g);this.minimumWidth=392;this.maximumWidth=392;"),
                    # sidebar minimum width 170 -> 392 (the Git panel's width): an opening editor then cannot squeeze the sidebar; it only grows into the widened window
                    ("vs/workbench/workbench.desktop.main.js", "$q.Viewlets,N.SidebarTitle,e,t,i,n,r,a,c,l,u,p,m,f,g);this.minimumWidth=170;", "$q.Viewlets,N.SidebarTitle,e,t,i,n,r,a,c,l,u,p,m,f,g);this.minimumWidth=392;"),
                    # minimum editor width 220 -> 1: opening a file must not squeeze the sidebar before the window widens
                    ("vs/workbench/workbench.desktop.main.js", "var PM=new Li(220,70),", "var PM=new Li(1,70),"),
                    # hiding the editor area must not force the bottom panel open (sidebar-only Git panel)
                    ("vs/workbench/workbench.desktop.main.js", 'e&&!this.isVisible("workbench.parts.panel")&&!this.isAuxiliaryBarMaximized()&&this.setPanelHidden(!1,!0))}getLayoutClasses', '0)}getLayoutClasses'),
                    ("vs/workbench/workbench.desktop.main.js", "$0e={WIDTH:400,WIDTH_WITH_VERTICAL_PANEL:600,", "$0e={WIDTH:215,WIDTH_WITH_VERTICAL_PANEL:600,")]:
    s = open(out + f, encoding="utf-8").read()
    if new in s: continue
    if s.count(old) != 1: sys.exit(f"patch-min-width: pattern not found exactly once in {f} (VS Code changed?)")
    open(out + f, "w", encoding="utf-8").write(s.replace(old, new))
import base64, hashlib, re
# VS Code warns "installation appears to be corrupt" when a checksummed file changes: refresh the stored checksum.
pj = "/usr/share/code/resources/app/product.json"
rel = "vs/workbench/workbench.desktop.main.js"
digest = base64.b64encode(hashlib.sha256(open(out + rel, "rb").read()).digest()).decode().rstrip("=")
t = open(pj, encoding="utf-8").read()
t2 = re.sub(r'("%s"\s*:\s*")[^"]*(")' % re.escape(rel), lambda m: m.group(1) + digest + m.group(2), t)
if t2 != t: open(pj, "w", encoding="utf-8").write(t2)
PY
