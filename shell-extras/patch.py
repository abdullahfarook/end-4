import sys
p = sys.argv[1]
s = open(p).read()
if 'typedOpen' not in s:
    s = s.replace('''        function openWith(text: string) {
            overviewScope.dontAutoCancelSearch = true;
            panelWindow.setSearchingText(text);
            GlobalStates.overviewOpen = true;
        }
''', '', 1)
    s = s.replace("""        function close() {
            GlobalStates.overviewOpen = false;
        }""", """        function close() {
            GlobalStates.overviewOpen = false;
        }
        function openWith(text: string) {
            overviewScope.dontAutoCancelSearch = true;
            panelWindow.typedOpen = true;
            panelWindow.setSearchingText(text);
            GlobalStates.overviewOpen = true;
        }""", 1)
    s = s.replace('        property string searchingText: ""\n', '        property string searchingText: ""\n        property bool typedOpen: false\n', 1)
    s = s.replace('item: GlobalStates.overviewOpen ? columnLayout : null', 'item: GlobalStates.overviewOpen ? scrim : null', 1)
    s = s.replace('                if (!GlobalStates.overviewOpen) {\n', '                if (!GlobalStates.overviewOpen) {\n                    panelWindow.typedOpen = false;\n', 1)
    s = s.replace('        Column {\n            id: columnLayout', """        // click-outside always closes the overview (the focus grab is unreliable)
        MouseArea {
            id: scrim
            anchors.fill: parent
            enabled: GlobalStates.overviewOpen
            onPressed: GlobalStates.overviewOpen = false
        }

        Column {
            id: columnLayout""", 1)
    open(p, 'w').write(s)
