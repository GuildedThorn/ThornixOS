# shellcheck shell=bash

set -o errexit -o nounset -o pipefail

catalog=${1:?feed catalog path is required}
credentials=${2:-/var/lib/codex/miniflux-admin.env}
api=${3:-http://127.0.0.1:8081/v1}

[[ $EUID -eq 0 ]] || {
  echo "error: run codex-seed-feeds as root" >&2
  exit 1
}
[[ -r $catalog ]] || {
  echo "error: feed catalog is unreadable: $catalog" >&2
  exit 1
}
[[ -r $credentials ]] || {
  echo "error: Miniflux credentials are unreadable: $credentials" >&2
  exit 1
}

set -a
# shellcheck disable=SC1090
source "$credentials"
set +a
: "${ADMIN_USERNAME:?missing ADMIN_USERNAME}"
: "${ADMIN_PASSWORD:?missing ADMIN_PASSWORD}"

auth="$ADMIN_USERNAME:$ADMIN_PASSWORD"
categories=$(curl --fail --silent --show-error --user "$auth" "$api/categories")
existing=$(curl --fail --silent --show-error --user "$auth" "$api/feeds")

declare -A category_ids
created=0
updated=0
skipped=0
failed=0

set_feed_title() {
  local feed_id=$1
  local feed_title=$2
  local category=$3
  local url=$4
  local payload response curl_status http_code body message

  payload=$(jq --compact-output --null-input --arg title "$feed_title" '{title: $title}')
  set +o errexit
  response=$(
    curl --silent --show-error --max-time 30 \
      --user "$auth" \
      --header 'Content-Type: application/json' \
      --request PUT \
      --data "$payload" \
      --write-out $'\n%{http_code}' \
      "$api/feeds/$feed_id" 2>&1
  )
  curl_status=$?
  set -o errexit
  http_code=${response##*$'\n'}
  body=${response%$'\n'*}

  if [[ $curl_status -eq 0 && ($http_code == 200 || $http_code == 204) ]]; then
    return 0
  fi

  message=$(jq --raw-output '.error_message // .' <<<"$body" 2>/dev/null || printf '%s' "$body")
  printf 'TITLE_FAILED\t%s\t%s\t%s\n' "$category" "$url" "$message"
  failed=$((failed + 1))
  return 1
}

while IFS=$'\t' read -r category url feed_title; do
  [[ -n $category && -n $url ]] || continue

  category_id=${category_ids[$category]:-}
  if [[ -z $category_id ]]; then
    category_id=$(jq --raw-output --arg title "$category" '.[] | select(.title == $title) | .id' <<<"$categories")
    if [[ -z $category_id ]]; then
      payload=$(jq --compact-output --null-input --arg title "$category" '{title: $title}')
      response=$(
        curl --silent --show-error --max-time 30 \
          --user "$auth" \
          --header 'Content-Type: application/json' \
          --data "$payload" \
          --write-out $'\n%{http_code}' \
          "$api/categories"
      )
      http_code=${response##*$'\n'}
      body=${response%$'\n'*}
      if [[ $http_code != 201 ]]; then
        message=$(jq --raw-output '.error_message // .' <<<"$body" 2>/dev/null || printf '%s' "$body")
        printf 'CATEGORY_FAILED\t%s\t%s\n' "$category" "$message"
        failed=$((failed + 1))
        continue
      fi
      category_id=$(jq --raw-output .id <<<"$body")
      categories=$(jq --argjson item "$body" '. + [$item]' <<<"$categories")
      printf 'CATEGORY\t%s\n' "$category"
    fi
    category_ids[$category]=$category_id
  fi

  existing_feed=$(jq --compact-output --arg url "$url" \
    'first(.[] | select(.feed_url == $url or .site_url == $url)) // empty' <<<"$existing")
  if [[ -n $existing_feed ]]; then
    current_title=$(jq --raw-output '.title // ""' <<<"$existing_feed")
    if [[ -n $feed_title && $current_title != "$feed_title" ]]; then
      feed_id=$(jq --raw-output .id <<<"$existing_feed")
      if set_feed_title "$feed_id" "$feed_title" "$category" "$url"; then
        printf 'UPDATED\t%s\t%s\n' "$feed_title" "$url"
        updated=$((updated + 1))
        existing=$(jq --argjson feed_id "$feed_id" --arg title "$feed_title" \
          'map(if .id == $feed_id then .title = $title else . end)' <<<"$existing")
      fi
      continue
    fi
    printf 'SKIPPED\t%s\n' "$url"
    skipped=$((skipped + 1))
    continue
  fi

  payload=$(jq --compact-output --null-input \
    --arg url "$url" \
    --argjson category_id "$category_id" \
    '{feed_url: $url, category_id: $category_id}')
  set +o errexit
  response=$(
    curl --silent --show-error --max-time 70 \
      --user "$auth" \
      --header 'Content-Type: application/json' \
      --data "$payload" \
      --write-out $'\n%{http_code}' \
      "$api/feeds" 2>&1
  )
  curl_status=$?
  set -o errexit
  http_code=${response##*$'\n'}
  body=${response%$'\n'*}

  if [[ $curl_status -eq 0 && $http_code == 201 ]]; then
    if ! feed_id=$(jq --exit-status --raw-output .feed_id <<<"$body" 2>/dev/null); then
      printf 'FAILED\t%s\t%s\tinvalid create response: %s\n' "$category" "$url" "$body"
      failed=$((failed + 1))
      continue
    fi
    if [[ -n $feed_title ]]; then
      set_feed_title "$feed_id" "$feed_title" "$category" "$url" || true
    fi
    printf 'ADDED\t%s\t%s\n' "$category" "$url"
    created=$((created + 1))
    existing=$(jq --argjson id "$feed_id" --arg url "$url" --arg title "$feed_title" \
      '. + [{id: $id, feed_url: $url, site_url: "", title: $title}]' <<<"$existing")
  elif jq --exit-status '.error_message? | test("already exists|duplicated feed"; "i")' <<<"$body" >/dev/null 2>&1; then
    printf 'SKIPPED\t%s\n' "$url"
    skipped=$((skipped + 1))
  else
    message=$(jq --raw-output '.error_message // .' <<<"$body" 2>/dev/null || printf '%s' "$body")
    printf 'FAILED\t%s\t%s\t%s\n' "$category" "$url" "$message"
    failed=$((failed + 1))
  fi
done <"$catalog"

printf 'SUMMARY\tcreated=%d\tupdated=%d\tskipped=%d\tfailed=%d\n' \
  "$created" "$updated" "$skipped" "$failed"
((failed == 0))
