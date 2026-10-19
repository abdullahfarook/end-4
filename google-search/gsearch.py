#!/usr/bin/env python3
"""Embedded Google (QtWebEngine) window docked under the Google widget popup.

Usage: gsearch.py show <query> | hide | back | forward | reload | stop | open
Empty query = stays hidden. First `show` starts the single instance (persistent profile ~/.local/share/gsearch); `hide` quits it.
"""
import os, sys, time, subprocess
os.environ.setdefault("QT_QPA_PLATFORM", "wayland")
from urllib.parse import quote_plus
from PySide6.QtCore import QUrl, QLockFile, Qt
from PySide6.QtGui import QShortcut, QKeySequence, QColor
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from PySide6.QtWidgets import QApplication
from PySide6.QtWebEngineCore import QWebEngineProfile, QWebEnginePage, QWebEngineScript
from PySide6.QtWebEngineWidgets import QWebEngineView

NAME = "gsearch"
RUN = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
cmd = sys.argv[1] if len(sys.argv) > 1 else "show"
arg = " ".join(sys.argv[2:])

def send(msg):
    s = QLocalSocket(); s.connectToServer(NAME)
    if not s.waitForConnected(150):
        return False
    s.write(msg.encode()); s.waitForBytesWritten(500); s.disconnectFromServer()
    return True

app = QApplication([sys.argv[0]])
app.setQuitOnLastWindowClosed(False)
app.setDesktopFileName(NAME)  # Wayland app_id -> Hyprland rules match class "gsearch"

if send(f"{cmd}\t{arg}"):
    sys.exit(0)
if cmd != "show":  # only `show` starts a new instance
    sys.exit(0)

lock = QLockFile(os.path.join(RUN, "gsearch.lock")); lock.setStaleLockTime(10000)
deadline = time.time() + 4
while not lock.tryLock(50):  # another instance is starting: wait, then hand the query over
    if send(f"{cmd}\t{arg}"):
        sys.exit(0)
    if time.time() > deadline:
        sys.exit(1)

def external(url):
    subprocess.Popen(["xdg-open", url.toString()], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

class Page(QWebEnginePage):
    def acceptNavigationRequest(self, url, nav_type, is_main):
        # Alt+click on a link opens it in the default browser
        if nav_type == QWebEnginePage.NavigationType.NavigationTypeLinkClicked and \
           QApplication.queryKeyboardModifiers() & Qt.KeyboardModifier.AltModifier:
            external(url); return False
        return super().acceptNavigationRequest(url, nav_type, is_main)
    def createWindow(self, _type):  # target=_blank / window.open -> default browser
        tmp = QWebEnginePage(self.profile(), self)
        tmp.urlChanged.connect(lambda u: (external(u), tmp.deleteLater()))
        return tmp

profile = QWebEngineProfile(NAME)
view = QWebEngineView(Page(profile, app))
# Themed scrollbars (colors come from the shell via env): thin rounded thumb, transparent track
css = ("::-webkit-scrollbar{width:12px!important;height:12px!important;background:transparent!important}"
       "::-webkit-scrollbar-track{background:transparent!important}"
       "::-webkit-scrollbar-corner{background:transparent!important}"
       "::-webkit-scrollbar-thumb{background:%s!important;border-radius:8px!important;border:3px solid transparent!important;background-clip:padding-box!important;min-height:40px}"
       "::-webkit-scrollbar-thumb:hover{background:%s!important;background-clip:padding-box!important}"
       % (os.environ.get("GSEARCH_THUMB", "#6a6a6a"), os.environ.get("GSEARCH_THUMB_HOVER", "#9a9a9a")))
sc = QWebEngineScript(); sc.setName("scrollbar")
sc.setInjectionPoint(QWebEngineScript.InjectionPoint.DocumentReady)
sc.setWorldId(QWebEngineScript.ScriptWorldId.MainWorld); sc.setRunsOnSubFrames(True)
sc.setSourceCode("(function(){var s=document.createElement('style');s.textContent=%r;(document.head||document.documentElement).appendChild(s)})()" % css)
profile.scripts().insert(sc)
view.setWindowTitle("gsearch")
view.resize(900, 620)
view.settings().setAttribute(view.settings().WebAttribute.PlaybackRequiresUserGesture, True)
view.page().setBackgroundColor(QColor(os.environ.get("GSEARCH_BG", "#1f1f1f")))

QShortcut(QKeySequence("Esc"), view, activated=app.quit)  # the popup closes when this process exits

last = {"q": None}
def emit(m):  # status lines for the popup (QML) on stdout
    print(m, flush=True)
view.loadStarted.connect(lambda: last["q"] and emit("loading"))
view.loadProgress.connect(lambda p: last["q"] and emit(f"progress {p}"))
state = {"revealed": False}
def finished(ok):
    if not last["q"]:
        return
    if not state["revealed"]:  # first results: the window is already mapped (behind the card); tell the popup to reveal it in place
        state["revealed"] = True; emit("shown")
    emit("done" if ok else "failed")
view.loadFinished.connect(finished)
def nav(*_):
    h = view.history(); emit(f"nav {int(h.canGoBack())} {int(h.canGoForward())}")
view.urlChanged.connect(nav); view.loadFinished.connect(nav)

def show(q):
    if not q:  # back to the blank state: keep the (empty) window mapped, covered by the popup card
        if last["q"]:
            last["q"] = None; state["revealed"] = False
            view.load(QUrl("about:blank"))
        return
    if q != last["q"]:
        last["q"] = q
        view.load(QUrl("https://www.google.com/search?q=" + quote_plus(q)))
    elif not state["revealed"]:
        state["revealed"] = True; emit("shown"); emit("done")

server = QLocalServer(); QLocalServer.removeServer(NAME); server.listen(NAME)
def on_conn():
    s = server.nextPendingConnection()
    def rd():
        c, _, a = bytes(s.readAll()).decode().partition("\t")
        if c == "hide": app.quit()
        elif c == "back": view.back()
        elif c == "forward": view.forward()
        elif c == "reload": view.reload()
        elif c == "stop": view.stop()
        elif c == "open": external(view.url())
        else: show(a)
    s.readyRead.connect(rd)
server.newConnection.connect(on_conn)

view.show()  # mapped right away (slides in with the popup header), hidden behind the popup card until results are ready
show(arg)
lock.unlock()
sys.exit(app.exec())
