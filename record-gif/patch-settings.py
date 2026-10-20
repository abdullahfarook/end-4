#!/usr/bin/env python3
# Settings > Services: output format option (config screenRecord.format: mp4 | gif | both), shown under the recording path.
# usage: patch-settings.py Config.qml ServicesConfig.qml (idempotent)
import sys

c, v = sys.argv[1], sys.argv[2]
s = open(c).read()
block = s.split("screenRecord: JsonObject")[1].split("}")[0]
if "property string format" not in block:
    old = 'property string savePath: Directories.videos.replace("file://","") // strip "file://"\n'
    assert old in s, "screenRecord.savePath not found"
    s = s.replace(old, old + '                property string format: "mp4" // mp4 | gif | both\n', 1)
    open(c, "w").write(s)
s = open(c).read()
if 'property string copy' not in s.split("screenRecord: JsonObject")[1].split("}")[0]:
    old = 'property string format: "mp4" // mp4 | gif | both\n'
    s = s.replace(old, old + '                property string copy: "gif" // none | mp4 | gif | both (what goes on the clipboard)\n', 1)
    open(c, "w").write(s)

t = open(v).read()
if "screenRecord.format" not in t:
    old = "                Config.options.screenRecord.savePath = text;\n            }\n        }\n"
    new = old + """
        ConfigSelectionArray {
            currentValue: Config.options.screenRecord.format
            onSelected: newValue => {
                Config.options.screenRecord.format = newValue;
            }
            options: [
                { displayName: Translation.tr("MP4"), icon: "movie", value: "mp4" },
                { displayName: Translation.tr("GIF"), icon: "gif_box", value: "gif" },
                { displayName: Translation.tr("MP4 + GIF"), icon: "perm_media", value: "both" }
            ]
        }
"""
    assert old in t, "recording path field not found"
    open(v, "w").write(t.replace(old, new, 1))

t = open(v).read()
if "screenRecord.copy" not in t:
    anchor = '{ displayName: Translation.tr("MP4 + GIF"), icon: "perm_media", value: "both" }\n            ]\n        }\n'
    new = anchor + """
        ConfigSelectionArray {
            currentValue: Config.options.screenRecord.copy
            onSelected: newValue => {
                Config.options.screenRecord.copy = newValue;
            }
            options: [
                { displayName: Translation.tr("Copy: nothing"), icon: "content_paste_off", value: "none" },
                { displayName: Translation.tr("Copy: MP4"), icon: "movie", value: "mp4" },
                { displayName: Translation.tr("Copy: GIF"), icon: "gif_box", value: "gif" },
                { displayName: Translation.tr("Copy: both"), icon: "file_copy", value: "both" }
            ]
        }
"""
    assert anchor in t, "format selector not found"
    open(v, "w").write(t.replace(anchor, new, 1))
