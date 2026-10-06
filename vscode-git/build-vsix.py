#!/usr/bin/env python3
"""Packs ext/ into gitpanel.vsix (no vsce needed)."""
import zipfile, os
here = os.path.dirname(os.path.abspath(__file__))
mani = '''<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
<Metadata><Identity Language="en-US" Id="gitpanel" Version="0.0.1" Publisher="local"/><DisplayName>gitpanel</DisplayName><Description xml:space="preserve">git panel helper</Description></Metadata>
<Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
<Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets></PackageManifest>'''
ct = '<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/Content-Types"><Default Extension=".json" ContentType="application/json"/><Default Extension=".js" ContentType="application/javascript"/><Default Extension=".vsixmanifest" ContentType="text/xml"/></Types>'
with zipfile.ZipFile(os.path.join(here, "gitpanel.vsix"), "w") as z:
    z.writestr("[Content_Types].xml", ct); z.writestr("extension.vsixmanifest", mani)
    for f in ("package.json", "extension.js"): z.write(os.path.join(here, "ext", f), "extension/" + f)
