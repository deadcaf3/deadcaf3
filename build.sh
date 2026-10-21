#!/usr/bin/env bash
# Regenerates README.md and cards/ from merged PRs outside your own account.
# Needs gh, jq, curl and pyftsubset (fonttools + brotli).
# shortcut: overwrites README.md whole; add markers if the README ever needs other content.
# shortcut: one API call per PR every run; cache by PR number if it nears the 1000 req/h token limit.
set -euo pipefail
cd "$(dirname "$0")"

me=${GITHUB_REPOSITORY_OWNER:-$(gh api user --jq .login)}
rows=$(gh api --paginate "search/issues?q=is:pr+is:merged+author:$me+-user:$me&per_page=100" \
  --jq '.items[] | (.repository_url | ltrimstr("https://api.github.com/repos/")) + "/pulls/" + (.number | tostring)' |
  while read -r pr; do
    gh api "repos/$pr" --jq '{repo: .base.repo.full_name, owner: .base.repo.owner.login, name: .base.repo.name,
      lang: .base.repo.language, commits, additions, deletions}'
  done |
  jq -rs '
    def k: if . >= 1000 then "\((. / 100 | floor) / 10)k" else tostring end;
    def n(w): "\(k) \(w)\(if . == 1 then "" else "s" end)";
    def cut(l): if length > l then .[:l - 1] + "…" else . end;
    def x: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
    group_by(.repo)
    | map({r: .[0], prs: length,
           c: (map(.commits) | add), a: (map(.additions) | add), d: (map(.deletions) | add)})
    | sort_by(-.prs, .r.repo)[]
    | [.r.repo, .r.owner, (.r.name | cut(38) | x),
       ([.r.lang // empty, (.prs | n("PR")), (.c | n("commit")), "+\(.a | k) −\(.d | k)"] | join(" · "))]
    | join("\u001f")')

tmp=$(mktemp -d)
font() {
  pyftsubset "fonts/$1.woff2" --text="$2" --flavor=woff2 --output-file="$tmp/font"
  echo "data:font/woff2;base64,$(base64 <"$tmp/font" | tr -d '\n')"
}
card() {
  cat >"$1" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="400" height="72" viewBox="0 0 400 72">
<style>@font-face{font-family:m;src:url($mono)}@font-face{font-family:b;src:url($bold)}text{font:12px m,ui-monospace,monospace;fill:#737c87}.n{font:14px b,ui-monospace,monospace;fill:#2f7ae0}</style>
<path d="M0 .5h376" stroke="#737c87" stroke-opacity=".35"/>
<clipPath id="c"><rect y="18" width="36" height="36" rx="8"/></clipPath>
<rect y="18" width="36" height="36" rx="8" fill="#fff"/>
<image href="$logo" y="18" width="36" height="36" clip-path="url(#c)"/>
<rect x=".5" y="18.5" width="35" height="35" rx="7.5" fill="none" stroke="#737c87" stroke-opacity=".35"/>
<text class="n" x="52" y="32">$name</text>
<text x="52" y="50">$meta</text>
</svg>
EOF
}

rm -rf tiles cards && mkdir cards
: >README.md
while IFS=$'\x1f' read -r repo owner name meta; do
  avatar=$tmp/$owner
  [[ -f $avatar ]] || curl -fsSL -o "$avatar" "https://github.com/$owner.png?size=72"
  logo="data:$(file -b --mime-type "$avatar");base64,$(base64 <"$avatar" | tr -d '\n')"
  mono=$(font ibm-plex-mono-latin-400-normal "$meta")
  bold=$(font ibm-plex-mono-latin-500-normal "$name")
  base=cards/${repo//\//_}
  # One card for both themes: colors sit midway between white and GitHub dark (about 4.3:1 on each).
  card "$base.svg"
  echo "<a href=\"https://github.com/search?q=is:pr+is:merged+author:$me+repo:$repo&amp;type=pullrequests\"><img src=\"$base.svg\" alt=\"$repo\" width=\"400\"></a>" >>README.md
done <<<"$rows"
rm -rf "$tmp"
