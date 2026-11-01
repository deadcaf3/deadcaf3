#!/usr/bin/env bash
# Regenerates README.md and cards/ from merged PRs outside your own account.
# Needs gh, jq, curl and pyftsubset (fonttools + brotli).
# shortcut: rebuilds README.md whole from header.md + cards; put any static content in header.md.
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
       (if .r.lang then .r.lang + " · " else "" end | x), (.prs | n("PR")),
       " · \(.c | n("commit")) · +\(.a | k) −\(.d | k)"]
    | join("\u001f")')

tmp=$(mktemp -d)
font() {
  pyftsubset "fonts/$1.woff2" --text="$2" --flavor=woff2 --output-file="$tmp/font"
  echo "data:font/woff2;base64,$(base64 <"$tmp/font" | tr -d '\n')"
}
# A row of the ledger under the pond: Inter at the pond caption's size, in the caption's
# colors per theme; outside a media query the colors sit midway between the two themes.
card() {
  cat >"$1" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="500" height="56" viewBox="0 0 500 56">
<style>@font-face{font-family:r;src:url($regular)}@font-face{font-family:m;src:url($medium)}
text{font:12px r,sans-serif;fill:#737c87}.n{font:13px m,sans-serif;fill:#737c87}.p{font-family:m}.h{stroke:#737c87;stroke-opacity:.35}.a{fill:#fff}
@media(prefers-color-scheme:light){text{fill:#56606a}.n,.p{fill:#2f3741}.h{stroke:#e7e0d0;stroke-opacity:1}}
@media(prefers-color-scheme:dark){text{fill:#a9b6d6}.n,.p{fill:#dfe6f5}.h{stroke:#1f2b46;stroke-opacity:1}.a{fill:#0d1117}}</style>
<path class="h" d="M0 .5h500"/>
<clipPath id="c"><rect y="14" width="28" height="28" rx="6"/></clipPath>
<rect class="a" y="14" width="28" height="28" rx="6"/>
<image href="$logo" y="14" width="28" height="28" clip-path="url(#c)"/>
<rect class="h" x=".5" y="14.5" width="27" height="27" rx="5.5" fill="none"/>
<text class="n" x="40" y="25">$name</text>
<text x="40" y="43">$pre<tspan class="p">$prs</tspan>$post</text>
</svg>
EOF
}

rm -rf tiles cards && mkdir cards
cat header.md >README.md
# Centered like the pond, so both share their edges whatever the README's width.
echo '<p align="center">' >>README.md
while IFS=$'\x1f' read -r repo owner name pre prs post; do
  avatar=$tmp/$owner
  [[ -f $avatar ]] || curl -fsSL -o "$avatar" "https://github.com/$owner.png?size=72"
  logo="data:$(file -b --mime-type "$avatar");base64,$(base64 <"$avatar" | tr -d '\n')"
  regular=$(font inter-latin-400-normal "$pre$prs$post")
  medium=$(font inter-latin-500-normal "$name$prs")
  base=cards/${repo//\//_}
  card "$base.svg"
  # <br> keeps the rows in one column, the pond's width, instead of wrapping into a grid.
  echo "<a href=\"https://github.com/search?q=is:pr+is:merged+author:$me+repo:$repo&amp;type=pullrequests\"><img src=\"$base.svg\" alt=\"$repo\" width=\"500\"></a><br>" >>README.md
done <<<"$rows"
echo '</p>' >>README.md
rm -rf "$tmp"
