// Detects streams per tab from network requests, then hands the best one to the native host (same host as ff2mpv: "ff2mpv").
const streams = new Map();                       // tabId -> [{url, kind, referer, origin, ts}]
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

// Request headers give the referer/origin the stream needs when mpv fetches it
browser.webRequest.onBeforeSendHeaders.addListener(d => {
  const kind = kindOf(d.url, "");
  if (kind) remember(d.tabId, { url: d.url, kind, referer: header(d.requestHeaders, "referer"), origin: header(d.requestHeaders, "origin"), ts: Date.now() });
}, { urls: ["<all_urls>"], types: ["xmlhttprequest", "media", "other", "object", "sub_frame", "main_frame"] }, ["requestHeaders"]);

// Streams served without a telling extension: judge by content type
browser.webRequest.onHeadersReceived.addListener(d => {
  const type = header(d.responseHeaders, "content-type");
  const kind = kindOf(d.url, type) || (/^video\//i.test(type) && Number(header(d.responseHeaders, "content-length") || 0) > 1e6 ? "file" : null);
  if (kind) remember(d.tabId, { url: d.url, kind, referer: "", origin: "", ts: Date.now() });
}, { urls: ["<all_urls>"], types: ["xmlhttprequest", "media", "other", "object"] }, ["responseHeaders"]);

browser.tabs.onUpdated.addListener((id, info) => { if (info.status === "loading" && info.url) { streams.delete(id); browser.browserAction.setBadgeText({ tabId: id, text: "" }); } });
browser.tabs.onRemoved.addListener(id => streams.delete(id));

// Best candidate: a master playlist / manifest first (newest), then any playlist, then a plain file
function best(list) {
  const rank = s => (s.kind === "dash" ? 3 : s.kind === "hls" ? (/master|index|playlist/i.test(s.url) ? 3.5 : 2.5) : 1) * 1e13 + s.ts;
  return [...list].sort((a, b) => rank(b) - rank(a))[0];
}

browser.browserAction.onClicked.addListener(async tab => {
  const s = best(streams.get(tab.id) || []);
  const msg = s ? { url: s.url, stream: true, referer: s.referer || tab.url, origin: s.origin, page: tab.url } : { url: tab.url };
  try { await browser.runtime.sendNativeMessage("ff2mpv", msg); }
  catch (e) { browser.notifications.create({ type: "basic", title: "mpv Stream Sniffer", message: "Native host failed: " + e.message, iconUrl: "icon.svg" }); }
});
