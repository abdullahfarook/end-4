#!/usr/bin/env bash
# Backend for the Gist bar widget (GistButton/GistPopup): your GitHub gists through `gh api`, mirrored in a local cache
# so the popup opens instantly, works offline and can filter by file content.
#   sync                 list gists, re-fetch only the ones whose updated_at changed, drop deleted ones; prints the sync time
#   create  < payload    POST /gists     (payload: {description, public, files: {name: {content}}}); prints "ID URL"
#   update ID < payload  PATCH /gists/ID (payload: {description, files: {name: {content} | {filename, content} | null}}); prints "ID URL"
#   delete ID            DELETE /gists/ID
#   clip                 secret gist from the clipboard; copies its URL and notifies
# The cache is $XDG_CACHE_HOME/gist-widget/{g/<id>.json, index.json}; index.json (newest first, file contents clipped
# at 200 KB) is what the widget reads. It is rewritten only when it changes, so an idle sync doesn't reset the popup.
set -euo pipefail
umask 077   # the cache holds secret gists
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/gist-widget"
mkdir -p "$CACHE/g"
exec 9>"$CACHE/lock"; flock 9   # one sync/mutation at a time

index() {
  local tmp="$CACHE/index.json.part"
  shopt -s nullglob; local files=("$CACHE"/g/*.json); shopt -u nullglob
  if ((${#files[@]})); then
    jq -s 'sort_by(.updated_at) | reverse | map({id, description: (.description // ""), public, html_url, created_at, updated_at,
           comments, owner: (.owner.login // ""),
           files: [.files[] | {filename, language: (.language // ""), size, raw_url, truncated: (.truncated // false),
                   clipped: ((.content // "") | length > 200000), content: ((.content // "")[0:200000])}]})' "${files[@]}" > "$tmp"
  else
    echo '[]' > "$tmp"
  fi
  if cmp -s "$tmp" "$CACHE/index.json"; then rm -f "$tmp"; else mv "$tmp" "$CACHE/index.json"; fi
}
# Store one API response (a full gist object) in the cache; sets $id.
store() { id=$(jq -r .id <<<"$1"); printf '%s\n' "$1" > "$CACHE/g/$id.json.part" && mv "$CACHE/g/$id.json.part" "$CACHE/g/$id.json"; }
created() { jq -r '"\(.id) \(.html_url)"' "$CACHE/g/$id.json"; }

case "${1:-}" in
  sync)
    list=$(gh api --paginate '/gists?per_page=100' --jq '.[] | "\(.id) \(.updated_at)"')
    declare -A live=(); need=()
    while read -r id up; do
      [[ -n "$id" ]] || continue
      live[$id]=1
      f="$CACHE/g/$id.json"
      [[ -f "$f" && "$(jq -r .updated_at "$f")" == "$up" ]] || need+=("$id")
    done <<<"$list"
    if ((${#need[@]})); then
      printf '%s\n' "${need[@]}" | xargs -r -P 6 -I{} sh -c \
        'gh api "/gists/$1" > "$2/$1.json.part" && mv "$2/$1.json.part" "$2/$1.json"' _ {} "$CACHE/g"
    fi
    for f in "$CACHE"/g/*.json; do
      [[ -e "$f" ]] || continue
      id=$(basename "$f" .json); [[ -n "${live[$id]:-}" ]] || rm -f "$f"
    done
    index
    date -u +%Y-%m-%dT%H:%M:%SZ | tee "$CACHE/synced_at"
    ;;
  create)
    resp=$(gh api -X POST /gists --input -)   # assign first: a failing $(…) inside an argument wouldn't stop set -e
    store "$resp"; index; created
    ;;
  update)
    [[ -n "${2:-}" ]] || { echo "usage: $0 update ID" >&2; exit 2; }
    resp=$(gh api -X PATCH "/gists/$2" --input -)
    store "$resp"; index; created
    ;;
  delete)
    [[ -n "${2:-}" ]] || { echo "usage: $0 delete ID" >&2; exit 2; }
    gh api -X DELETE "/gists/$2" >/dev/null
    rm -f "$CACHE/g/$2.json"; index
    ;;
  clip)
    content=$(wl-paste --no-newline 2>/dev/null || true)
    [[ -n "${content//[[:space:]]/}" ]] || { notify-send -a Gist "Gist" "The clipboard is empty"; exit 1; }
    name="clipboard-$(date +%Y%m%d-%H%M%S).txt"
    resp=$(jq -n --arg n "$name" --arg c "$content" '{description: "", public: false, files: {($n): {content: $c}}}' \
      | gh api -X POST /gists --input -) || { notify-send -a Gist "Gist" "Creating the gist failed"; exit 1; }
    store "$resp"; index
    url=$(jq -r .html_url "$CACHE/g/$id.json")
    wl-copy "$url"
    notify-send -a Gist "Secret gist created" "$url (link copied)"
    created
    ;;
  *) echo "usage: $0 sync|create|update ID|delete ID|clip" >&2; exit 2 ;;
esac
