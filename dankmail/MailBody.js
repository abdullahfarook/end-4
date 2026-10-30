.pragma library

// Render only markup we generate from the provider's distilled text. Never
// load message HTML, remote images, CSS or executable URLs into the reader.
function escapeHtml(value) {
    return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;")
        .replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

function safeUrl(value) {
    return /^(https?:\/\/[^\s/?#]+|mailto:[^\s@]+@[^\s@]+)[^\s]*$/i.test(value)
        && !/[\x00-\x20\x7f<>"'\\]/.test(value);
}

function inline(text, color, linkLabel) {
    const stash = [];
    const put = html => "\x01" + (stash.push(html) - 1) + "\x01";
    const emphasis = value => escapeHtml(value)
        .replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>")
        .replace(/(^|[\s(])\*([^*\n]+)\*(?=$|[\s.,!?:;)])/g, "$1<i>$2</i>");
    const anchor = (url, label) => safeUrl(url)
        ? '<a href="' + escapeHtml(url) + '"><font color="' + color + '">' + emphasis(label) + '</font></a>'
        : emphasis(label);
    let s = text.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "");
    s = s.replace(/`([^`\n]+)`/g, (m, code) => put('<code>' + escapeHtml(code) + '</code>'));
    s = s.replace(/\[!\[([^\]]*)\]\(([^\s()]+)\)\]\(([^\s()]+)\)/g,
        (m, alt, image, url) => put(anchor(url, alt || linkLabel)));
    s = s.replace(/!\[([^\]]*)\]\(([^\s()]+)\)/g, (m, alt) => put(escapeHtml(alt)));
    s = s.replace(/\[([^\]]+)\]\(([^\s()]+)\)/g, (m, label, url) => put(anchor(url, label)));
    s = s.replace(/(?:https?:\/\/|mailto:)[^\s<>"'\x01]+/gi, url => {
        const clean = url.replace(/[.,;!?:)\]}]+$/, "");
        const tail = url.substring(clean.length);
        const label = clean.length > 72 ? clean.substring(0, 68) + "…" : clean;
        return put(anchor(clean, label)) + tail;
    });
    s = emphasis(s).replace(/\\([\\*_{}\[\]()#+.!~-])/g, "$1");
    for (let i = stash.length - 1; i >= 0; i--)
        s = s.split("\x01" + i + "\x01").join(stash[i]);
    return s;
}

function format(text, options) {
    options = options || {};
    const color = /^#[0-9a-f]{3,8}$/i.test(String(options.linkColor)) ? String(options.linkColor) : "#517cbb";
    const quoteColor = /^#[0-9a-f]{3,8}$/i.test(String(options.quoteColor)) ? String(options.quoteColor) : color;
    const render = value => inline(value, color, options.linkLabel || "Link");
    const lines = String(text || "").replace(/\r\n?/g, "\n").split("\n");
    const cells = line => line.trim().replace(/^\||\|$/g, "").split("|").map(value => value.trim());
    const tableSeparator = line => /^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$/.test(line);
    let html = "";
    let i = 0;
    while (i < lines.length) {
        const line = lines[i];
        if (!line.trim()) { i++; continue; }
        if (/^\s*```/.test(line)) {
            const code = [];
            i++;
            while (i < lines.length && !/^\s*```/.test(lines[i])) code.push(lines[i++]);
            if (i < lines.length) i++;
            html += '<pre style="margin-top:8px; margin-bottom:8px">' + escapeHtml(code.join("\n")) + '</pre>';
            continue;
        }
        if (/^\s*>/.test(line)) {
            const quoted = [];
            while (i < lines.length && /^\s*>/.test(lines[i])) quoted.push(lines[i++].replace(/^\s*> ?/, ""));
            // Bound nesting, even for hostile or malformed message text.
            const depth = options.depth || 0;
            html += '<blockquote style="margin-left:16px; margin-top:8px; margin-bottom:8px"><font color="' + quoteColor + '">' + (depth < 5
                ? format(quoted.join("\n"), {linkColor: color, quoteColor: quoteColor, linkLabel: options.linkLabel, depth: depth + 1})
                : quoted.map(render).join('<br>')) + '</font></blockquote>';
            continue;
        }
        const heading = line.match(/^\s*#{1,6}\s+(.*)$/);
        if (heading) {
            html += '<p style="margin-top:12px; margin-bottom:6px"><b>' + render(heading[1]) + '</b></p>';
            i++; continue;
        }
        if (/^\s*(?:-{3,}|\*{3,}|_{3,})\s*$/.test(line)) { html += '<hr>'; i++; continue; }
        if (i + 1 < lines.length && line.includes('|') && tableSeparator(lines[i + 1])) {
            const header = cells(line);
            html += '<table border="1" cellspacing="0" cellpadding="6" width="100%"><tr>' + header.map(c => '<th>' + render(c) + '</th>').join('') + '</tr>';
            i += 2;
            while (i < lines.length && lines[i].trim() && lines[i].includes('|')) {
                const row = cells(lines[i++]);
                html += '<tr>' + header.map((c, n) => '<td>' + render(row[n] || '') + '</td>').join('') + '</tr>';
            }
            html += '</table>'; continue;
        }
        const list = line.match(/^\s*(?:([-+*])|(\d+)[.)])\s+(.+)$/);
        if (list) {
            const ordered = !!list[2];
            const tag = ordered ? 'ol' : 'ul';
            html += '<' + tag + (ordered ? ' start="' + Number(list[2]) + '"' : '') + '>';
            while (i < lines.length) {
                const item = lines[i].match(/^\s*(?:([-+*])|(\d+)[.)])\s+(.+)$/);
                if (!item || !!item[2] !== ordered) break;
                html += '<li>' + render(item[3]) + '</li>'; i++;
            }
            html += '</' + tag + '>'; continue;
        }
        const paragraph = [render(line)];
        i++;
        while (i < lines.length && lines[i].trim() && !/^\s*(?:>|```|#{1,6}\s|[-+*]\s|\d+[.)]\s|[-*_]{3,}\s*$)/.test(lines[i])
               && !(i + 1 < lines.length && tableSeparator(lines[i + 1]))) paragraph.push(render(lines[i++]));
        html += '<p style="margin-top:0px; margin-bottom:10px; line-height:125%">' + paragraph.join('<br>') + '</p>';
    }
    return html;
}

// Reduce a message's original HTML to the subset Qt's rich text renders. width caps image/table width in px; remote images still load.
// loaded (optional) = { url: {w, h} } for images that preloaded successfully: only those are embedded, so Qt's text view never
// issues (and loops on) a failing remote image request; the rest are left out.
// ---- HTML -> Qt rich text -------------------------------------------------------------------------------------------
// Newsletters are layout tables + CSS; Qt's rich text has neither. cleanHtml parses the message into a tree, resolves the
// CSS it can (<style> rules with a single compound selector, presentational attributes, inline style) and re-emits only
// what Qt renders: stacked layout tables become blocks, real columns stay tables, buttons/cards keep their background.
var VOID = { br: 1, hr: 1, img: 1, input: 1, meta: 1, link: 1, wbr: 1, col: 1, area: 1, base: 1 };
var DROP = { head: 1, style: 1, script: 1, title: 1, svg: 1, noscript: 1, template: 1, object: 1, iframe: 1, button: 0, select: 1, textarea: 1 };
var BLOCK = { div: 1, p: 1, section: 1, article: 1, header: 1, footer: 1, main: 1, nav: 1, aside: 1, center: 1, form: 1, figure: 1,
    figcaption: 1, address: 1, dl: 1, dt: 1, dd: 1, fieldset: 1, details: 1, summary: 1, body: 1, html: 1, hgroup: 1 };
var NAMED = { white: "#ffffff", black: "#000000", red: "#ff0000", blue: "#0000ff", green: "#008000", gray: "#808080", grey: "#808080",
    orange: "#ffa500", yellow: "#ffff00", silver: "#c0c0c0", navy: "#000080", maroon: "#800000", purple: "#800080", teal: "#008080", transparent: "" };

function parseColor(v) {
    v = String(v || "").trim().toLowerCase();
    if (!v || v === "transparent" || v === "inherit" || v === "initial" || v === "none") return null;
    if (NAMED[v] !== undefined) v = NAMED[v];
    let m = v.match(/^#([0-9a-f]{3})$/);
    if (m) return [parseInt(m[1][0] + m[1][0], 16), parseInt(m[1][1] + m[1][1], 16), parseInt(m[1][2] + m[1][2], 16)];
    m = v.match(/^#([0-9a-f]{6})/);
    if (m) return [parseInt(m[1].slice(0, 2), 16), parseInt(m[1].slice(2, 4), 16), parseInt(m[1].slice(4, 6), 16)];
    m = v.match(/^rgba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)(?:[\s,/]+([\d.]+%?))?/);
    if (m) {
        if (m[4] !== undefined && parseFloat(m[4]) === 0) return null;
        return [+m[1], +m[2], +m[3]];
    }
    return null;
}
function lum(c) { return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255; }
function chroma(c) { return (Math.max(c[0], c[1], c[2]) - Math.min(c[0], c[1], c[2])) / 255; }
function hex(c) { return "#" + c.map(x => (x < 16 ? "0" : "") + x.toString(16)).join(""); }
function px(v, base) {  // css length -> px (null when unknown); % and em resolve against base
    if (v === undefined || v === null) return null;
    const m = String(v).trim().match(/^(-?[\d.]+)\s*(px|pt|em|rem|%)?$/i);
    if (!m) return null;
    const n = parseFloat(m[1]), u = (m[2] || "px").toLowerCase();
    return u === "px" ? n : u === "pt" ? n * 1.333 : u === "%" ? (base ? n * base / 100 : null) : n * (base || 16);
}
function box(v, base) {  // margin/padding shorthand -> [top, right, bottom, left]
    const p = String(v || "").trim().split(/\s+/).map(x => px(x, base) || 0);
    if (!p.length || String(v || "").trim() === "") return [0, 0, 0, 0];
    return p.length === 1 ? [p[0], p[0], p[0], p[0]] : p.length === 2 ? [p[0], p[1], p[0], p[1]] : p.length === 3 ? [p[0], p[1], p[2], p[1]] : p;
}

function parseStyle(s, into) {
    String(s || "").split(";").forEach(d => {
        const i = d.indexOf(":");
        if (i < 1) return;
        into[d.slice(0, i).trim().toLowerCase()] = d.slice(i + 1).replace(/!important/i, "").trim();
    });
    return into;
}
function parseSheet(css) {  // [{tag, cls[], id, spec, props}] for plain single-compound selectors outside @media/@supports
    const rules = [];
    css = css.replace(/\/\*[\s\S]*?\*\//g, "").replace(/<!--|-->/g, "");
    let depth = 0, out = "", skip = 0;
    for (let i = 0; i < css.length; i++) {  // drop @media & co by brace balancing
        const ch = css[i];
        if (ch === "@" && depth === 0) {
            const m = css.slice(i).match(/^@(media|supports|font-face|keyframes|-[a-z-]*keyframes|page|import|charset)[^{;]*([{;])/i);
            if (m) {
                if (m[2] === ";") { i += m[0].length - 1; continue; }
                let d = 1, j = i + m[0].length;
                while (j < css.length && d > 0) { if (css[j] === "{") d++; else if (css[j] === "}") d--; j++; }
                i = j - 1; continue;
            }
        }
        out += ch;
    }
    out.replace(/([^{}]+)\{([^{}]*)\}/g, (all, sel, body) => {
        const props = parseStyle(body, {});
        sel.split(",").forEach(sx => {
            sx = sx.trim();
            const m = sx.match(/^([a-z][a-z0-9]*)?((?:\.[\w-]+)*)(#[\w-]+)?$/i);
            if (!m || sx === "") return;
            const cls = m[2] ? m[2].split(".").filter(x => x) : [];
            rules.push({ "tag": (m[1] || "").toLowerCase(), "cls": cls, "id": m[3] ? m[3].slice(1) : "", "props": props,
                         "spec": (m[3] ? 100 : 0) + cls.length * 10 + (m[1] ? 1 : 0) });
        });
        return all;
    });
    return rules;
}

function parseTree(h) {
    const root = { "t": "#root", "a": {}, "c": [], "p": null };
    let cur = root;
    const stack = [root];
    const re = /<!--[\s\S]*?-->|<(\/?)([a-zA-Z][a-zA-Z0-9:-]*)((?:"[^"]*"|'[^']*'|[^>"'])*)>|([^<]+|<)/g;
    let m;
    const closeUp = (names, stopAt) => {  // pop to the nearest open element in names, not crossing stopAt
        for (let i = stack.length - 1; i > 0; i--) {
            const t = stack[i].t;
            if (stopAt[t]) return;
            if (names[t]) { stack.length = i; cur = stack[i - 1]; return; }
        }
    };
    while ((m = re.exec(h)) !== null) {
        if (m[4] !== undefined) {
            if (m[4].trim() !== "" || cur.t === "pre") cur.c.push({ "t": "#text", "x": m[4] });
            else if (m[4].length) cur.c.push({ "t": "#text", "x": " " });
            continue;
        }
        if (m[2] === undefined) continue;  // comment
        const tag = m[2].toLowerCase();
        if (m[1]) {  // closing
            for (let i = stack.length - 1; i > 0; i--) {
                if (stack[i].t === tag) { stack.length = i; cur = stack[i - 1]; break; }
                if (tag !== "table" && (stack[i].t === "table" || stack[i].t === "td" && tag !== "td" && tag !== "tr")) break;
            }
            continue;
        }
        const a = {};
        m[3].replace(/([^\s=\/"'>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g, (all, k, v1, v2, v3) => {
            a[k.toLowerCase()] = v1 !== undefined ? v1 : v2 !== undefined ? v2 : v3 !== undefined ? v3 : "";
            return all;
        });
        if (tag === "td" || tag === "th") closeUp({ "td": 1, "th": 1 }, { "tr": 1, "table": 1 });
        else if (tag === "tr") closeUp({ "td": 1, "th": 1, "tr": 1 }, { "table": 1, "tbody": 1, "thead": 1, "tfoot": 1 });
        else if (tag === "li") closeUp({ "li": 1 }, { "ul": 1, "ol": 1 });
        else if (tag === "p") closeUp({ "p": 1 }, { "td": 1, "th": 1, "div": 1, "table": 1 });
        const node = { "t": tag, "a": a, "c": [], "p": cur };
        cur.c.push(node);
        if (!VOID[tag] && !/\/\s*$/.test(m[3] || "")) { stack.push(node); cur = node; }
    }
    return root;
}

function plainText(n) { return n.t === "#text" ? n.x : n.c.map(plainText).join(""); }
function hasText(n) {  // any visible text below (an image-only block keeps no background stripe once the image is split out)
    if (n.t === "#text") return /[^\s\u00a0]/.test(n.x.replace(/&nbsp;/gi, ""));
    if (n.hide) return false;
    for (let i = 0; i < n.c.length; i++) if (hasText(n.c[i])) return true;
    return false;
}
function hasContent(n) {  // visible text or an image anywhere below
    if (n.t === "#text") return /[^\s ͏​-‍⁠﻿­]/.test(n.x.replace(/&nbsp;|&zwnj;|&#847;|&#8199;|&#8204;|&#xa0;/gi, ""));
    if (n.t === "img") return !n.hide;
    if (n.t === "hr") return true;
    if (n.hide) return false;
    for (let i = 0; i < n.c.length; i++) if (hasContent(n.c[i])) return true;
    return false;
}

var _memo = { "key": "", "val": "" };
function cleanHtml(h, width, loaded) {
    if (!h) return "";
    const key = width + "|" + (loaded ? Object.keys(loaded).length : "-") + "|" + h.length + "|" + h.slice(0, 64) + h.slice(-64);
    if (_memo.key === key) return _memo.val;
    const out = _clean(h, width, loaded);
    _memo = { "key": key, "val": out };
    return out;
}

function _clean(h, width, loaded) {
    let css = "";
    h.replace(/<style\b[^>]*>([\s\S]*?)<\/style>/gi, (all, body) => { css += body + "\n"; return all; });
    const rules = parseSheet(css);
    rules.sort((a, b) => a.spec - b.spec);
    h = h.replace(/<!--[\s\S]*?-->/g, "").replace(/<![a-z][^>]*>|<\?[\s\S]*?\?>/gi, "").replace(/<(head|style|script|title|svg|noscript|template)\b[\s\S]*?<\/\1\s*>/gi, "");
    const tree = parseTree(h);

    function computed(n) {  // css props of one element: attributes < sheet < inline
        const p = {};
        const a = n.a;
        if (a.bgcolor) p["background-color"] = a.bgcolor;
        if (a.color) p["color"] = a.color;
        if (a.align && n.t !== "table" && n.t !== "img") p["text-align"] = a.align;
        if (a.width) p["width"] = /^\d+$/.test(a.width) ? a.width + "px" : a.width;
        if (a.height) p["height"] = /^\d+$/.test(a.height) ? a.height + "px" : a.height;
        if (n.t === "b" || n.t === "strong" || /^h[1-6]$/.test(n.t) || n.t === "th") p["font-weight"] = "bold";
        const cls = a["class"] ? a["class"].split(/\s+/) : [];
        rules.forEach(r => {
            if (r.tag && r.tag !== n.t) return;
            if (r.id && r.id !== a.id) return;
            for (let i = 0; i < r.cls.length; i++) if (cls.indexOf(r.cls[i]) < 0) return;
            for (const k in r.props) p[k] = r.props[k];
        });
        parseStyle(a.style, p);
        // shorthands
        if (p["background"] && !p["background-color"]) {
            const m = String(p["background"]).match(/(#[0-9a-f]{3,8}\b|rgba?\([^)]*\)|\b[a-z]+\b)/i);
            if (m && parseColor(m[1])) p["background-color"] = m[1];
        }
        return p;
    }
    function isHidden(p) {
        if (/none/i.test(p["display"] || "") || /hidden|collapse/i.test(p["visibility"] || "") || /mso-hide:\s*all/i.test(p["mso-hide"] || "") || /all/i.test(p["mso-hide"] || "")) return true;
        if (p["opacity"] !== undefined && parseFloat(p["opacity"]) === 0) return true;
        const mh = px(p["max-height"]), mw = px(p["max-width"]);
        if ((mh === 0 || mw === 0) && /hidden/i.test(p["overflow"] || "")) return true;
        if (px(p["height"]) === 0 && /hidden/i.test(p["overflow"] || "")) return true;
        return false;
    }
    // mark hidden subtrees and attach computed props once
    (function annotate(n) {
        if (n.t === "#text") return;
        n.p_ = n.t === "#root" ? {} : computed(n);
        n.hide = !!DROP[n.t] || isHidden(n.p_);
        n.c.forEach(annotate);
    })(tree);

    function esc(t) { return t.replace(/&(?!#?\w+;)/g, "&amp;").replace(/</g, "&lt;"); }
    function blockStyle(p, ctx, extra) {  // style attr for a block: align, margins, bg
        const s = [];
        const al = ctx.align;
        if (al) s.push("text-align:" + al);
        const mar = box(p["margin"], ctx.w), pad = box(p["padding"], ctx.w);
        const mt = Math.min(20, 0.6 * Math.max(0, (px(p["margin-top"], ctx.w) !== null ? px(p["margin-top"], ctx.w) : mar[0]) + (px(p["padding-top"], ctx.w) !== null ? px(p["padding-top"], ctx.w) : pad[0])));
        const mb = Math.min(20, 0.6 * Math.max(0, (px(p["margin-bottom"], ctx.w) !== null ? px(p["margin-bottom"], ctx.w) : mar[2]) + (px(p["padding-bottom"], ctx.w) !== null ? px(p["padding-bottom"], ctx.w) : pad[2])));
        if (mt > 0) s.push("margin-top:" + Math.round(mt) + "px");
        if (mb > 0) s.push("margin-bottom:" + Math.round(mb) + "px");
        const lh = String(p["line-height"] || "");
        if (/%$/.test(lh) && parseFloat(lh) > 100) s.push("line-height:" + Math.min(180, Math.round(parseFloat(lh))) + "%");
        else if (/^\d*\.?\d+$/.test(lh) && parseFloat(lh) > 1) s.push("line-height:" + Math.min(180, Math.round(parseFloat(lh) * 100)) + "%");
        if (ctx.bgOwn && ctx.hasText !== false) s.push("background-color:" + ctx.bgOwn);
        return (s.concat(extra || [])).join(";");
    }
    function textProps(p, ctx) {  // inline-level style: color, size, weight, italics, decoration. Returns { css, ctx }
        const s = [];
        const c = Object.assign({}, ctx);
        const col = parseColor(p["color"]);
        if (col) {
            const inBg = !!ctx.bg;
            if (inBg || (chroma(col) > 0.3 && lum(col) > 0.18 && lum(col) < 0.8)) { s.push("color:" + hex(col)); c.color = hex(col); }
        }
        const fs = px(p["font-size"], 16);
        if (fs !== null && fs > 1) s.push("font-size:" + Math.round(Math.max(10, Math.min(34, fs * 0.92))) + "px");
        const fw = String(p["font-weight"] || "").toLowerCase();
        if (ctx.noWeight) {}
        else if (fw === "bold" || fw === "bolder" || parseInt(fw) >= 600) s.push("font-weight:bold");
        else if (fw === "normal" || (fw !== "" && parseInt(fw) < 500)) s.push("font-weight:normal");
        if (/italic|oblique/i.test(p["font-style"] || "")) s.push("font-style:italic");
        const td = String(p["text-decoration"] || p["text-decoration-line"] || "");
        if (/underline/.test(td)) s.push("text-decoration:underline");
        else if (/line-through/.test(td)) s.push("text-decoration:line-through");
        else if (/none/.test(td)) s.push("text-decoration:none");
        if (/uppercase/i.test(p["text-transform"] || "")) c.upper = true;
        else if (/none|capitalize|lowercase/i.test(p["text-transform"] || "")) c.upper = false;
        if (/nowrap/i.test(p["white-space"] || "")) c.nowrap = true;
        return { "css": s.join(";"), "ctx": c };
    }
    function bgOf(p) {  // visible background colour, or null (near-white/transparent is dropped: it only fights the panel theme)
        const c = parseColor(p["background-color"]);
        return c && lum(c) < 0.88 ? hex(c) : null;
    }
    function imgTag(n, ctx) {
        const src = n.a.src ? n.a.src.replace(/&amp;/g, "&") : "";
        if (!/^https?:/i.test(src)) return "";
        const known = loaded ? loaded[src] : null;
        if (loaded && !known) return "";
        const p = n.p_;
        let w = px(p["width"], ctx.w);
        if (w === null && n.a.width) w = px(n.a.width + "px");
        let ht = px(p["height"]);
        if (ht === null && n.a.height) ht = px(n.a.height + "px");
        if ((w !== null && w <= 12) || (ht !== null && ht <= 12 && w === null)) return "";  // spacers, tracking pixels, icons: they also tear table rows apart when split out
        if (known && (known.w <= 3 || known.h <= 3)) return "";
        if (w === null && known) w = known.w;
        if (w !== null) w = Math.min(w, ctx.w);
        const attr = src.replace(/&/g, "&amp;").replace(/"/g, "&quot;");
        let hh = "";
        if (w && known && known.w > 0) hh = ' height="' + Math.max(1, Math.round(w * known.h / known.w)) + '"';
        else if (w && ht !== null && n.a.width) hh = ' height="' + Math.round(ht) + '"';
        const al = ctx.align === "center" || ctx.align === "right" ? ' data-align="' + ctx.align + '"' : "";
        const hr = ctx.href ? ' data-href="' + ctx.href.replace(/&/g, "&amp;").replace(/"/g, "&quot;") + '"' : "";
        return '<img src="' + attr + '"' + (w ? ' width="' + Math.round(w) + '"' : "") + hh + al + hr + ">";
    }

    function inlineKids(n, ctx) { return n.c.map(k => node(k, ctx)).join(""); }

    function tableCells(t) {  // [[td...]] flattening thead/tbody/tfoot
        const rows = [];
        (function walk(n) {
            n.c.forEach(k => {
                if (k.hide) return;
                if (k.t === "tr") rows.push(k.c.filter(x => (x.t === "td" || x.t === "th") && !x.hide));
                else if (k.t === "thead" || k.t === "tbody" || k.t === "tfoot") walk(k);
                else if (k.t === "td" || k.t === "th") rows.push([k]);
            });
        })(t);
        return rows;
    }
    function cellCtx(td, ctx) {
        const p = td.p_;
        const c = Object.assign({}, ctx);
        const al = String(p["text-align"] || td.a.align || "").toLowerCase();
        if (al === "center" || al === "right" || al === "left") c.align = al;
        const bg = bgOf(p);
        if (bg) { c.bg = bg; c.bgOwn = bg; c.hasText = hasText(td); } else c.bgOwn = null;
        return c;
    }

    function table(n, ctx) {
        const rows = tableCells(n).map(r => r.filter(td => hasContent(td))).filter(r => r.length > 0 || false);
        if (rows.length === 0) return "";
        const tp = n.p_;
        const tAlign = String(n.a.align || "").toLowerCase();
        const tctx = Object.assign({}, ctx);
        const tAl = String(tp["text-align"] || "").toLowerCase();
        if (tAl) tctx.align = tAl;
        if (tAlign === "center" || tAlign === "right") tctx.alignTable = tAlign;
        const tbg = bgOf(tp);
        let tw = px(tp["width"], ctx.w);
        const maxw = px(tp["max-width"], ctx.w);
        if (tw !== null && maxw !== null) tw = Math.min(tw, maxw);
        else if (tw === null && maxw !== null) tw = maxw;
        if (tw !== null) tw = Math.min(tw, ctx.w);
        const flat = rows.every(r => r.length === 1 && !(parseInt(r[0].a.colspan) > 1 && false));
        const cardy = tbg || rows.every(r => r.length === 1 && bgOf(r[0].p_) && rows.length === 1) || rows.some(r => r.length === 1 && bgOf(r[0].p_));
        const tn = tw !== null ? tw : ctx.w;
        const innerW = Math.max(120, tn);
        if (flat) {
            let html = "";
            const solo = rows.length === 1 && rows[0].length === 1;
            // a button/card (own background, content narrower than the page) stays a 1-cell table so the background hugs the content
            const td0 = solo ? rows[0][0] : null;
            const bg0 = td0 ? bgOf(td0.p_) || tbg : null;
            if (solo && bg0 && (tw === null || tw < ctx.w * 0.95) && plainText(td0).length < 90) {
                const c = cellCtx(td0, tctx);
                c.bg = bg0; c.bgOwn = null; c.w = Math.max(80, innerW);
                const pad = box(td0.p_["padding"], ctx.w);
                const pp = Math.max(pad[0], px(td0.p_["padding-top"], ctx.w) || 0), pl = Math.max(pad[1], px(td0.p_["padding-left"], ctx.w) || 0);
                const wrapAlign = tctx.alignTable || (c.align === "center" ? "center" : "");
                const cp = Math.round(Math.max(5, Math.min(14, (pp + pl) / 2)));
                const tbl = '<table cellspacing="0" cellpadding="' + cp + '"' + (wrapAlign === "center" ? ' align="center"' : "") + ' style="background-color:' + bg0 + '"><tr><td style="background-color:' + bg0 + '">' + cell(td0, c) + "</td></tr></table>";
                return '<div style="margin-top:8px;margin-bottom:8px">' + tbl + "</div>";
            }
            rows.forEach(r => {
                const td = r[0];
                const c = cellCtx(td, tctx);
                if (tbg && !c.bgOwn) { c.bg = tbg; }
                c.w = Math.max(120, Math.min(innerW, tn));
                const pad = box(td.p_["padding"], ctx.w);
                const padL = (px(td.p_["padding-left"], ctx.w) !== null ? px(td.p_["padding-left"], ctx.w) : pad[3]) + (px(td.p_["padding-right"], ctx.w) !== null ? px(td.p_["padding-right"], ctx.w) : pad[1]);
                c.w = Math.max(120, c.w - Math.min(padL, 80));
                html += cell(td, c, true);
            });
            return html;
        }
        // real columns
        const ncols = Math.max.apply(null, rows.map(r => r.length));
        let html = '<table cellspacing="0" cellpadding="0" width="' + (tw !== null && tw < ctx.w * 0.95 ? Math.round(tw) : "100%") + '"' + (tbg ? ' style="background-color:' + tbg + '"' : "") + ">";
        rows.forEach(r => {
            html += "<tr>";
            const wsum = r.reduce((a, td) => a + (px(td.p_["width"], innerW) || 0), 0);
            r.forEach(td => {
                const c = cellCtx(td, tctx);
                const cw = px(td.p_["width"], innerW);
                const share = cw !== null && wsum > 0 ? cw / wsum : 1 / r.length;
                c.w = Math.max(80, Math.round(innerW * share));
                const pad = box(td.p_["padding"], ctx.w);
                const pl = px(td.p_["padding-left"], ctx.w) !== null ? px(td.p_["padding-left"], ctx.w) : pad[3];
                const pr = px(td.p_["padding-right"], ctx.w) !== null ? px(td.p_["padding-right"], ctx.w) : pad[1];
                c.w = Math.max(60, c.w - Math.min(pl + pr, 60));
                const sty = [];
                if (c.bgOwn) sty.push("background-color:" + c.bgOwn);
                if (c.align) sty.push("text-align:" + c.align);
                const ptop = px(td.p_["padding-top"], ctx.w) !== null ? px(td.p_["padding-top"], ctx.w) : pad[0];
                const va = String(td.p_["vertical-align"] || td.a.valign || "").toLowerCase();
                const anyW = r.some(x => px(x.p_["width"], innerW) !== null);
                const wAttr = !anyW ? ' width="' + Math.round(100 / r.length) + '%"'
                    : cw !== null && cw < innerW * 0.9 ? ' width="' + Math.round(cw + Math.min(pl, 24) + Math.min(pr, 24)) + '"' : "";
                html += '<td' + wAttr + ' valign="' + (va === "middle" ? "middle" : va === "bottom" ? "bottom" : "top") + '"' +
                    ' style="padding-left:' + Math.round(Math.min(pl, 24)) + "px;padding-right:" + Math.round(Math.min(pr, 24)) + "px;padding-top:" + Math.round(Math.min(ptop, 20)) + "px" + (sty.length ? ";" + sty.join(";") : "") + '">' +
                    cell(td, c) + "</td>";
            });
            html += "</tr>";
        });
        return html + "</table>";
    }
    function cell(td, c, asBlock) {
        const tpx = textProps(td.p_, c);
        const body = inlineKids(td, tpx.ctx);
        if (!asBlock) return tpx.css ? '<span style="' + tpx.css + '">' + body + "</span>" : body;
        const st = [blockStyle(td.p_, c), tpx.css].filter(x => x).join(";");
        return '<div' + (st ? ' style="' + st + '"' : "") + ">" + body + "</div>";
    }

    function node(n, ctx) {
        if (n.t === "#text") {
            let t = n.x.replace(/[͏​-‍⁠﻿­]/g, "").replace(/&(?:zwnj|zwj|#847|#8204|#8203|#x34f|#173|shy);?/gi, "");
            if (ctx.pre) return esc(t).replace(/\n/g, "<br>");
            t = t.replace(/\s+/g, " ");
            if (ctx.upper) t = t.toUpperCase();
            return ctx.nowrap ? esc(t).replace(/ /g, "&nbsp;") : esc(t);
        }
        if (n.hide) return "";
        const t = n.t;
        const p = n.p_;
        if (t === "br") return "<br>";
        if (t === "wbr") return "";
        if (t === "hr") return "<hr>";
        if (t === "img") return imgTag(n, ctx);
        if (t === "table") return table(n, ctx);
        if (t === "tbody" || t === "thead" || t === "tfoot" || t === "tr" || t === "td" || t === "th" || t === "caption" || t === "colgroup" || t === "col") return inlineKids(n, ctx);
        const tp = textProps(p, (t === "b" || t === "strong") ? Object.assign({}, ctx, { "noWeight": true }) : ctx);
        let c = tp.ctx;
        if (c.noWeight) c = Object.assign({}, c, { "noWeight": false });
        const al = String(p["text-align"] || "").toLowerCase();
        if (al === "center" || al === "right" || al === "left") c = Object.assign({}, c, { "align": al });
        if (t === "center") c = Object.assign({}, c, { "align": "center" });
        const bg = bgOf(p);
        if (bg) c = Object.assign({}, c, { "bg": bg, "bgOwn": bg, "hasText": hasText(n) });
        else if (c.bgOwn) c = Object.assign({}, c, { "bgOwn": null });
        if (t === "pre" || t === "textarea") c = Object.assign({}, c, { "pre": true });
        const kids = () => inlineKids(n, c);
        if (t === "a") {
            const href = n.a.href ? n.a.href.replace(/&amp;/g, "&") : "";
            if (/^https?:/i.test(href)) c = Object.assign({}, c, { "href": href });
            const inner = kids();
            if (!/^(https?:|mailto:)/i.test(href)) return inner;
            const col = parseColor(p["color"]);
            const css = tp.css;  // an anchor styled as a coloured button inherits the colour from the cell
            return '<a href="' + href.replace(/&/g, "&amp;").replace(/"/g, "&quot;") + '"' + (css ? ' style="' + css + '"' : "") + ">" + inner + "</a>";
        }
        const isBlock = BLOCK[t] || /^h[1-6]$/.test(t) || t === "p" || t === "ul" || t === "ol" || t === "li" || t === "blockquote" || t === "pre";
        if (isBlock) {
            if (!hasContent(n)) return "";
            const mw = Math.min(px(p["max-width"], c.w) || 1e9, px(p["width"], c.w) || 1e9);
            if (mw < c.w) c = Object.assign({}, c, { "w": Math.max(120, mw - (box(p["padding"], c.w)[1] + box(p["padding"], c.w)[3])) });
            const inner = kids();
            let st = blockStyle(p, c) + (tp.css ? (blockStyle(p, c) ? ";" : "") + tp.css : "");
            if (t === "p" && !/margin/.test(st)) st += (st ? ";" : "") + "margin-top:6px;margin-bottom:6px";
            if (/^h[1-6]$/.test(t)) return "<" + t + (st ? ' style="' + st + '"' : "") + ">" + inner + "</" + t + ">";
            if (t === "ul" || t === "ol" || t === "li" || t === "blockquote" || t === "pre")
                return "<" + t + (st ? ' style="' + st + '"' : "") + ">" + inner + "</" + t + ">";
            return "<div" + (st ? ' style="' + st + '"' : "") + ">" + inner + "</div>";
        }
        // inline
        const inner = kids();
        if (inner === "") return "";
        let o = inner;
        if (t === "b" || t === "strong") o = "<b>" + o + "</b>";
        else if (t === "i" || t === "em" || t === "cite" || t === "dfn" || t === "var") o = "<i>" + o + "</i>";
        else if (t === "u" || t === "ins") o = "<u>" + o + "</u>";
        else if (t === "s" || t === "strike" || t === "del") o = "<s>" + o + "</s>";
        else if (t === "sup" || t === "sub" || t === "small" || t === "big" || t === "code" || t === "tt" || t === "kbd") o = "<" + t + ">" + o + "</" + t + ">";
        else if (t === "font") {
            const sz = parseInt(n.a.size);
            const map = { 1: 10, 2: 13, 3: 16, 4: 18, 5: 24, 6: 32, 7: 48 };
            const extra = sz && map[sz] && !p["font-size"] ? "font-size:" + Math.round(map[sz] * 0.92) + "px" : "";
            const css = [tp.css, extra].filter(x => x).join(";");
            return css ? '<span style="' + css + '">' + o + "</span>" : o;
        }
        return tp.css ? '<span style="' + tp.css + '">' + o + "</span>" : o;
    }

    let html = node(tree, { "w": Math.max(200, width), "align": "left", "bg": null, "bgOwn": null });
    html = html.replace(/(<br>\s*){3,}/gi, "<br><br>").replace(/<div[^>]*>\s*<\/div>/gi, "");
    return html;
}

// Remote image URLs in the original HTML (entity-decoded, the same URLs cleanHtml emits), for preloading.
function imageSources(h) {
    const out = [];
    (h || "").replace(/<img\b[^>]*?>/gi, tag => {
        const src = tag.match(/\bsrc="([^"]+)"/i);
        const url = src ? src[1].replace(/&amp;/g, "&") : "";
        if (/^https?:/i.test(url) && out.indexOf(url) < 0) out.push(url);
        return tag;
    });
    return out;
}

// Loading skeleton: the cleaned HTML split at every remote image into [{html}|{img:true, w, h}] so the view can show a
// spinner per image while they load. w/h come from the tag's width/height attributes (0 when unknown).
function segments(h, width) {
    const out = [];
    let last = 0;
    const c = cleanHtml(h, width);
    c.replace(/<img\b[^>]*?>/gi, (tag, off) => {
        if (off > last) out.push({ "html": c.slice(last, off) });
        const wm = tag.match(/\bwidth="?(\d+)/i);
        const sm = tag.match(/\bsrc="([^"]+)"/i);
        const am = tag.match(/\bdata-align="(\w+)"/);
        const hm = tag.match(/\bdata-href="([^"]*)"/);
        out.push({ "img": true, "w": wm ? parseInt(wm[1]) : 0, "url": sm ? sm[1].replace(/&amp;/g, "&") : "", "align": am ? am[1] : "",
                   "href": hm ? hm[1].replace(/&quot;/g, '"').replace(/&amp;/g, "&") : "" });
        last = off + tag.length;
        return tag;
    });
    if (last < c.length) out.push({ "html": c.slice(last) });
    return groupIcons(out);
}

// Runs of small images each followed by a short label (social icons, badges) become one {group:[{url, w, href, label}]} item
// so the view can lay them out in a row instead of stacking them.
function groupIcons(segs) {
    const label = h => String(h || "").replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ").replace(/\s+/g, " ").trim();
    const small = g => g && g.img && g.w > 0 && g.w <= 96;
    const out = [];
    let i = 0;
    while (i < segs.length) {
        const run = [];
        let j = i;
        while (j < segs.length && small(segs[j])) {
            const lab = j + 1 < segs.length && segs[j + 1].html !== undefined ? label(segs[j + 1].html) : "";
            const hasLabel = j + 1 < segs.length && segs[j + 1].html !== undefined && lab.length <= 24 && !/<(table|hr|h\d)\b/i.test(segs[j + 1].html);
            run.push({ "url": segs[j].url, "w": segs[j].w, "href": segs[j].href, "label": hasLabel ? lab : "" });
            j += hasLabel ? 2 : 1;
        }
        if (run.length >= 2) { out.push({ "group": run, "align": "center" }); i = j; }
        else { out.push(segs[i]); i++; }
    }
    return out;
}
