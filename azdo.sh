#!/usr/bin/env bash
# Call the devops.hdi.at REST API with the Kerberos ticket (SPNEGO).
#
#   azdo.sh <path> [curl args...]
#
# <path> is relative to https://devops.hdi.at/HdiCollection/ , for example
#   azdo.sh DevOps/_apis/git/repositories
#   azdo.sh DevOps/_apis/git/repositories/hdi-agent-skills/pullrequests/19103 | jq .title
#   azdo.sh DevOps/_apis/wiki/wikis/DevOps.wiki/pages/1 -X PATCH -H 'If-Match: "<etag>"' -d @body.json
#
# api-version=$AZDO_API_VERSION (default 6.0) is appended unless the path has
# one already; AZDO_API_VERSION= (empty) appends none, as connectionData needs.
set -euo pipefail
dir=$(cd "$(dirname "$0")" && pwd)
. "$dir/env.sh"

if [[ $# -lt 1 ]]; then
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi
path=${1#/}; shift

if ! klist -s 2>/dev/null; then
  echo "No valid Kerberos ticket. Run: $dir/kinit-hdi.sh user@hdi.at" >&2
  exit 1
fi

url="${AZDO_BASE_URL:-https://devops.hdi.at/HdiCollection}/$path"
ver=${AZDO_API_VERSION-6.0}
if [[ -n $ver && $url != *api-version=* ]]; then
  [[ $url == *\?* ]] && url+="&api-version=$ver" || url+="?api-version=$ver"
fi

body=$(mktemp); trap 'rm -f "$body"' EXIT
code=$(curl --negotiate -u : -sS -o "$body" -w '%{http_code}' \
  -H 'Content-Type: application/json' "$@" "$url")

if [[ $code == 2?? ]]; then
  cat "$body"
  exit 0
fi
# Errors: the JSON message, or the <title> of an HTML error page, not the page.
msg=$(jq -er '.message' "$body" 2>/dev/null) \
  || msg=$(grep -o -m1 '<title>[^<]*' "$body" | sed 's/<title>//') \
  || msg=$(head -c 300 "$body")
echo "HTTP $code: $msg" >&2
[[ $code == 401 ]] && echo "Ticket rejected or missing: klist; $dir/kinit-hdi.sh" >&2
exit 1
