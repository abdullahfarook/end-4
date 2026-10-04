pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * - Eases fuzzy searching for applications by name
 * - Guesses icon name for window class name
 */
Singleton {
    id: root
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property var substitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code": "visual-studio-code",
        "gnome-tweaks": "org.gnome.tweaks",
        "pavucontrol-qt": "pavucontrol",
        "wps": "wps-office2019-kprometheus",
        "wpsoffice": "wps-office2019-kprometheus",
        "footclient": "foot",
    })
    property var regexSubstitutions: [
        {
            "regex": /^steam_app_(\d+)$/,
            "replace": "steam_icon_$1"
        },
        {
            "regex": /Minecraft.*/,
            "replace": "minecraft"
        },
        {
            "regex": /.*polkit.*/,
            "replace": "system-lock-screen"
        },
        {
            "regex": /gcr.prompter/,
            "replace": "system-lock-screen"
        }
    ]

    // Deduped list to fix double icons
    readonly property list<DesktopEntry> list: Array.from(DesktopEntries.applications.values)
        .filter((app, index, self) => 
            index === self.findIndex((t) => (
                t.id === app.id
            ))
    )
    
    readonly property var preppedNames: list.map(a => ({
        name: Fuzzy.prepare(`${a.name} `),
        entry: a
    }))

    readonly property var preppedIcons: list.map(a => ({
        name: Fuzzy.prepare(`${a.icon} `),
        entry: a
    }))

    function fuzzyQuery(search: string): var { // Idk why list<DesktopEntry> doesn't work
        if (root.sloppySearch) {
            const results = list.map(obj => ({
                entry: obj,
                score: Levendist.computeScore(obj.name.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }

        return Fuzzy.go(search, preppedNames, {
            all: true,
            key: "name"
        }).map(r => ({
            entry: r.obj.entry,
            score: r.score + root.usageBoost(r.obj.entry.id)
        })).sort((a, b) => b.score - a.score)
            .map(item => item.entry);
    }

    // App usage tracking (frecency): { "<desktop id>": { "launches": [epochMs, ...] } }
    property var usage: ({})
    readonly property int maxLaunchesKept: 20
    readonly property real halfLifeDays: 7

    // Each launch counts 1, halving every halfLifeDays
    function frecency(id) {
        const launches = root.usage[id]?.launches ?? [];
        const now = Date.now();
        return launches.reduce((sum, t) => sum + Math.pow(0.5, (now - t) / 86400000 / root.halfLifeDays), 0);
    }

    function usageBoost(id) {
        return Math.min(0.3, 0.08 * Math.log(1 + root.frecency(id)));
    }

    function recordLaunch(id) {
        const launches = (root.usage[id]?.launches ?? []).concat(Date.now()).slice(-root.maxLaunchesKept);
        const updated = Object.assign({}, root.usage);
        updated[id] = { "launches": launches };
        root.usage = updated;
        usageFileView.setText(JSON.stringify(root.usage));
    }

    function frequentApps(limit: int): var {
        return Object.keys(root.usage)
            .map(id => ({ id: id, score: root.frecency(id) }))
            .sort((a, b) => b.score - a.score)
            .map(item => list.find(app => app.id === item.id))
            .filter(Boolean)
            .slice(0, limit);
    }

    // Converts the old { count, last } format to a launches list
    function migrateUsage(data) {
        const migrated = {};
        for (const id in data) {
            const item = data[id];
            migrated[id] = item.launches ? item : { "launches": Array(Math.min(item.count ?? 1, root.maxLaunchesKept)).fill(item.last ?? Date.now()) };
        }
        return migrated;
    }

    FileView {
        id: usageFileView
        path: Directories.appUsagePath
        onLoaded: {
            try {
                root.usage = root.migrateUsage(JSON.parse(usageFileView.text()));
            } catch (e) {
                root.usage = {};
            }
        }
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound)
                usageFileView.setText(JSON.stringify({}));
        }
    }

    function iconExists(iconName) {
        if (!iconName || iconName.length == 0) return false;
        return (Quickshell.iconPath(iconName, true).length > 0) 
            && !iconName.includes("image-missing");
    }

    function getReverseDomainNameAppName(str) {
        return str.split('.').slice(-1)[0]
    }

    function getKebabNormalizedAppName(str) {
        return str.toLowerCase().replace(/\s+/g, "-");
    }

    function getUndescoreToKebabAppName(str) {
        return str.toLowerCase().replace(/_/g, "-");
    }

    function guessIcon(str) {
        if (!str || str.length == 0) return "image-missing";

        // Quickshell's desktop entry lookup
        const entry = DesktopEntries.byId(str);
        if (entry) return entry.icon;

        // Normal substitutions
        if (substitutions[str]) return substitutions[str];
        if (substitutions[str.toLowerCase()]) return substitutions[str.toLowerCase()];

        // Regex substitutions
        for (let i = 0; i < regexSubstitutions.length; i++) {
            const substitution = regexSubstitutions[i];
            const replacedName = str.replace(
                substitution.regex,
                substitution.replace,
            );
            if (replacedName != str) return replacedName;
        }

        // Icon exists -> return as is
        if (iconExists(str)) return str;


        // Simple guesses
        const lowercased = str.toLowerCase();
        if (iconExists(lowercased)) return lowercased;

        const reverseDomainNameAppName = getReverseDomainNameAppName(str);
        if (iconExists(reverseDomainNameAppName)) return reverseDomainNameAppName;

        const lowercasedDomainNameAppName = reverseDomainNameAppName.toLowerCase();
        if (iconExists(lowercasedDomainNameAppName)) return lowercasedDomainNameAppName;

        const kebabNormalizedGuess = getKebabNormalizedAppName(str);
        if (iconExists(kebabNormalizedGuess)) return kebabNormalizedGuess;

        const undescoreToKebabGuess = getUndescoreToKebabAppName(str);
        if (iconExists(undescoreToKebabGuess)) return undescoreToKebabGuess;

        // Search in desktop entries
        const iconSearchResults = Fuzzy.go(str, preppedIcons, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
        if (iconSearchResults.length > 0) {
            const guess = iconSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        const nameSearchResults = root.fuzzyQuery(str);
        if (nameSearchResults.length > 0) {
            const guess = nameSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        // Quickshell's desktop entry lookup
        const heuristicEntry = DesktopEntries.heuristicLookup(str);
        if (heuristicEntry) return heuristicEntry.icon;

        // Give up
        return "application-x-executable";
    }
}
