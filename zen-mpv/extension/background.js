// Detects streams per tab from network requests, then hands the best one to the native host (same host as ff2mpv: "ff2mpv").
const streams = new Map();
const subs = new Map();                          // tabId -> [{url, referer, ts}] subtitle files (vtt/srt/ass/...) the tab loaded
const SUBFILE = /\.(vtt|srt|ass|ssa|ttml|dfxp)(\?|#|$)/i;                       // tabId -> [{url, kind, referer, origin, ts}]
const SEGMENT = /\.(ts|m4s|aac|vtt|webvtt|key|m4a|cmfv|cmfa)(\?|#|$)/i;
const KINDS = [
  [/\.m3u8(\?|#|$)/i, "hls"], [/\.mpd(\?|#|$)/i, "dash"], [/\.(mp4|webm|mkv|mov)(\?|#|$)/i, "file"],
];

function kindOf(url, type) {
  if (SEGMENT.test(url)) return null;
  for (const [re, k] of KINDS) if (re.test(url)) return k;
  if (/mpegurl/i.test(type || "")) return "hls";
  if (/dash\+xml/i.test(type || "")) return "dash";
  return null;
}

function header(headers, name) {
  const h = (headers || []).find(x => x.name.toLowerCase() === name);
  return h ? h.value : "";
}

function remember(tabId, entry) {
  if (tabId < 0) return;
  const list = streams.get(tabId) || [];
  if (list.some(s => s.url === entry.url)) return;
  list.push(entry);
  streams.set(tabId, list.slice(-30));
  browser.browserAction.setBadgeText({ tabId, text: String(list.length) });
  browser.browserAction.setBadgeBackgroundColor({ tabId, color: "#6b3a8c" });
}

function rememberSub(tabId, entry) {
  if (tabId < 0) return;
  const list = subs.get(tabId) || [];
  if (list.some(x => x.url === entry.url)) return;
  list.push(entry);
  subs.set(tabId, list.slice(-30));
}

// Request headers give the referer/origin the stream needs when mpv fetches it
browser.webRequest.onBeforeSendHeaders.addListener(d => {
  if (SUBFILE.test(d.url)) { rememberSub(d.tabId, { url: d.url, referer: header(d.requestHeaders, "referer"), ts: Date.now() }); return; }
  const kind = kindOf(d.url, "");
  if (kind) remember(d.tabId, { url: d.url, kind, referer: header(d.requestHeaders, "referer"), origin: header(d.requestHeaders, "origin"), ts: Date.now() });
}, { urls: ["<all_urls>"], types: ["xmlhttprequest", "media", "other", "object", "sub_frame", "main_frame"] }, ["requestHeaders"]);

// Streams served without a telling extension: judge by content type
browser.webRequest.onHeadersReceived.addListener(d => {
  const type = header(d.responseHeaders, "content-type");
  if (/text\/vtt|x-subrip|ttml\+xml/i.test(type)) { rememberSub(d.tabId, { url: d.url, referer: "", ts: Date.now() }); return; }
  const kind = kindOf(d.url, type) || (/^video\//i.test(type) && Number(header(d.responseHeaders, "content-length") || 0) > 1e6 ? "file" : null);
  if (kind) remember(d.tabId, { url: d.url, kind, referer: "", origin: "", ts: Date.now() });
}, { urls: ["<all_urls>"], types: ["xmlhttprequest", "media", "other", "object"] }, ["responseHeaders"]);

browser.tabs.onUpdated.addListener((id, info) => { if (info.status === "loading" && info.url) { streams.delete(id); subs.delete(id); browser.browserAction.setBadgeText({ tabId: id, text: "" }); } });
browser.tabs.onRemoved.addListener(id => { streams.delete(id); subs.delete(id); });

// Default = what the page is playing right now: the most recently requested stream (the player keeps re-fetching the quality it is using,
// so after you pick a server/quality on the page that one is the newest). The others stay available in mpv's right-click menu > Sources.
function best(list) {
  return [...list].sort((a, b) => b.ts - a.ts)[0];
}

function ranked(list) { return [...list].sort((x, y) => y.ts - x.ts); }

browser.browserAction.onClicked.addListener(async tab => {
  const list = ranked(streams.get(tab.id) || []);
  const s = list[0];
  // The best stream plays at once; the others go along as `sources` for mpv's right-click menu (Sources...)
  const msg = s ? { url: s.url, stream: true, referer: s.referer || tab.url, origin: s.origin, page: tab.url,
                    sources: list.slice(0, 15).map(x => ({ url: x.url, kind: x.kind, referer: x.referer || tab.url, origin: x.origin })),
                    subs: (subs.get(tab.id) || []).slice(-10).map(x => ({ url: x.url, referer: x.referer || tab.url })) }
                : { url: tab.url };
  try { await browser.runtime.sendNativeMessage("ff2mpv", msg); }
  catch (e) { browser.notifications.create({ type: "basic", title: "mpv Stream Sniffer", message: "Native host failed: " + e.message, iconUrl: "icon.svg" }); }
});
