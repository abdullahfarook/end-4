//@ pragma UseQApplication
// Small shell add-ons that live outside the ii shell, sharing one quickshell process (one Qt/QML runtime):
// CloseButton.qml (window buttons for apps without their own) and TypeSearch.qml (type-to-search on empty workspaces).
import Quickshell

ShellRoot {
    CloseButton {}
    TypeSearch {}
}
