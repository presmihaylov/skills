#!/usr/bin/env bash
#
# intercom_api.sh — Intercom REST API helper
#
# Usage:
#   intercom_api.sh <command> [args...]
#
# Commands:
#   search-conversations <query_json> [starting_after] [per_page]
#   search-contacts      <query_json> [starting_after] [per_page]
#   search-tickets       <query_json> [starting_after] [per_page]
#   get-conversation     <conversation_id> [plaintext]
#   list-tags
#
# Environment:
#   INTERCOM_API_TOKEN  — Intercom API access token (required)

set -euo pipefail

BASE_URL="https://api.intercom.io"
API_VERSION="2.11"

# --- Auth ---
if [ -z "${INTERCOM_API_TOKEN:-}" ]; then
  echo "Error: INTERCOM_API_TOKEN environment variable is not set." >&2
  echo "Set it to your Intercom API access token." >&2
  exit 1
fi

# --- Helpers ---
api_call() {
  local method="$1"
  local endpoint="$2"
  local body="${3:-}"

  local args=(
    -s -S
    -X "$method"
    -H "Authorization: Bearer ${INTERCOM_API_TOKEN}"
    -H "Content-Type: application/json"
    -H "Accept: application/json"
    -H "Intercom-Version: ${API_VERSION}"
  )

  if [ -n "$body" ]; then
    args+=(-d "$body")
  fi

  local http_code response_body
  response_body=$(curl "${args[@]}" -w "\n%{http_code}" "${BASE_URL}${endpoint}")
  http_code=$(echo "$response_body" | tail -n1)
  response_body=$(echo "$response_body" | sed '$d')

  if [ "$http_code" -ge 400 ]; then
    echo "Error: HTTP ${http_code}" >&2
    echo "$response_body" | jq . 2>/dev/null || echo "$response_body" >&2
    exit 1
  fi

  echo "$response_body" | jq .
}

build_search_body() {
  local query_json="$1"
  local starting_after="${2:-}"
  local per_page="${3:-}"

  local pagination="{}"
  if [ -n "$per_page" ] && [ -n "$starting_after" ]; then
    pagination=$(jq -n --argjson pp "$per_page" --arg sa "$starting_after" \
      '{"per_page": $pp, "starting_after": $sa}')
  elif [ -n "$per_page" ]; then
    pagination=$(jq -n --argjson pp "$per_page" '{"per_page": $pp}')
  elif [ -n "$starting_after" ]; then
    pagination=$(jq -n --arg sa "$starting_after" '{"starting_after": $sa}')
  fi

  if [ "$pagination" = "{}" ]; then
    jq -n --argjson q "$query_json" '{"query": $q}'
  else
    jq -n --argjson q "$query_json" --argjson p "$pagination" '{"query": $q, "pagination": $p}'
  fi
}

# --- Commands ---
cmd_search_conversations() {
  local query_json="$1"
  local starting_after="${2:-}"
  local per_page="${3:-}"
  local body
  body=$(build_search_body "$query_json" "$starting_after" "$per_page")
  api_call POST "/conversations/search" "$body"
}

cmd_search_contacts() {
  local query_json="$1"
  local starting_after="${2:-}"
  local per_page="${3:-}"
  local body
  body=$(build_search_body "$query_json" "$starting_after" "$per_page")
  api_call POST "/contacts/search" "$body"
}

cmd_search_tickets() {
  local query_json="$1"
  local starting_after="${2:-}"
  local per_page="${3:-}"
  local body
  body=$(build_search_body "$query_json" "$starting_after" "$per_page")
  api_call POST "/tickets/search" "$body"
}

cmd_get_conversation() {
  local conversation_id="$1"
  local display_as="${2:-}"
  local endpoint="/conversations/${conversation_id}"
  if [ "$display_as" = "plaintext" ]; then
    endpoint="${endpoint}?display_as=plaintext"
  fi
  api_call GET "$endpoint"
}

cmd_list_tags() {
  api_call GET "/tags"
}

# --- Main ---
command="${1:-}"
shift || true

case "$command" in
  search-conversations)
    [ $# -lt 1 ] && { echo "Usage: $0 search-conversations <query_json> [starting_after] [per_page]" >&2; exit 1; }
    cmd_search_conversations "${1}" "${2:-}" "${3:-}"
    ;;
  search-contacts)
    [ $# -lt 1 ] && { echo "Usage: $0 search-contacts <query_json> [starting_after] [per_page]" >&2; exit 1; }
    cmd_search_contacts "${1}" "${2:-}" "${3:-}"
    ;;
  search-tickets)
    [ $# -lt 1 ] && { echo "Usage: $0 search-tickets <query_json> [starting_after] [per_page]" >&2; exit 1; }
    cmd_search_tickets "${1}" "${2:-}" "${3:-}"
    ;;
  get-conversation)
    [ $# -lt 1 ] && { echo "Usage: $0 get-conversation <conversation_id> [plaintext]" >&2; exit 1; }
    cmd_get_conversation "${1}" "${2:-}"
    ;;
  list-tags)
    cmd_list_tags
    ;;
  *)
    echo "Usage: $0 <command> [args...]" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "  search-conversations <query_json> [starting_after] [per_page]" >&2
    echo "  search-contacts      <query_json> [starting_after] [per_page]" >&2
    echo "  search-tickets       <query_json> [starting_after] [per_page]" >&2
    echo "  get-conversation     <conversation_id> [plaintext]" >&2
    echo "  list-tags" >&2
    exit 1
    ;;
esac
