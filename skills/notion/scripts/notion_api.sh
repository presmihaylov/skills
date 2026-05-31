#!/usr/bin/env bash
#
# notion_api.sh — Notion REST API helper
#
# Mirrors the 22-tool surface of the official Notion MCP server
# (https://github.com/makenotion/notion-mcp-server), using the same
# operationIds as command names.
#
# Usage:
#   notion_api.sh <command> [args...]
#
# Environment:
#   NOTION_API_KEY   — Notion integration token (required)
#   NOTION_VERSION   — API version header (optional; default: 2025-09-03)

set -euo pipefail

BASE_URL="https://api.notion.com/v1"
NOTION_VERSION="${NOTION_VERSION:-2025-09-03}"

if [ -z "${NOTION_API_KEY:-}" ]; then
  echo "Error: NOTION_API_KEY environment variable is not set." >&2
  echo "Set it to your Notion integration token (ntn_... or secret_...)." >&2
  exit 1
fi

# --- HTTP helper ---
_call() {
  local method="$1"
  local path="$2"
  local body="${3:-}"

  local args=(
    -sS
    -X "$method"
    -H "Authorization: Bearer ${NOTION_API_KEY}"
    -H "Notion-Version: ${NOTION_VERSION}"
    -H "Accept: application/json"
  )

  if [ -n "$body" ]; then
    args+=(-H "Content-Type: application/json" -d "$body")
  fi

  local raw http_code response_body
  raw=$(curl "${args[@]}" -w "\n__HTTP__:%{http_code}" "${BASE_URL}${path}")
  http_code=$(printf '%s' "$raw" | sed -n 's/^__HTTP__://p' | tail -n1)
  response_body=$(printf '%s' "$raw" | sed '/^__HTTP__:/d')

  if [ -z "$http_code" ] || [ "$http_code" -ge 400 ]; then
    echo "Error: HTTP ${http_code:-?} ${method} ${path}" >&2
    if [ -n "$response_body" ]; then
      printf '%s\n' "$response_body" | jq . 2>/dev/null >&2 || printf '%s\n' "$response_body" >&2
    fi
    exit 1
  fi

  if [ -z "$response_body" ]; then
    echo '{}'
  else
    printf '%s\n' "$response_body" | jq . 2>/dev/null || printf '%s\n' "$response_body"
  fi
}

_require() {
  local name="$1" val="${2:-}"
  if [ -z "$val" ]; then
    echo "Error: missing required arg: $name" >&2
    exit 1
  fi
}

_validate_json() {
  local body="$1"
  if ! printf '%s' "$body" | jq empty >/dev/null 2>&1; then
    echo "Error: argument is not valid JSON" >&2
    printf '%s\n' "$body" >&2
    exit 1
  fi
}

# --- Users ---
cmd_get_self() { _call GET "/users/me"; }
cmd_get_user() { _require user_id "${1:-}"; _call GET "/users/$1"; }
cmd_get_users() {
  local start_cursor="${1:-}" page_size="${2:-}" qs=""
  [ -n "$start_cursor" ] && qs="start_cursor=${start_cursor}"
  if [ -n "$page_size" ]; then
    [ -n "$qs" ] && qs="${qs}&page_size=${page_size}" || qs="page_size=${page_size}"
  fi
  [ -n "$qs" ] && _call GET "/users?${qs}" || _call GET "/users"
}

# --- Search ---
cmd_post_search() {
  local body="${1:-{\}}"
  _validate_json "$body"
  _call POST "/search" "$body"
}

# --- Pages ---
cmd_retrieve_a_page() { _require page_id "${1:-}"; _call GET "/pages/$1"; }
cmd_post_page() {
  _require body_json "${1:-}"; _validate_json "$1"
  _call POST "/pages" "$1"
}
cmd_patch_page() {
  _require page_id "${1:-}"; _require body_json "${2:-}"; _validate_json "$2"
  _call PATCH "/pages/$1" "$2"
}
cmd_retrieve_a_page_property() {
  _require page_id "${1:-}"; _require property_id "${2:-}"
  _call GET "/pages/$1/properties/$2"
}
cmd_move_page() {
  _require page_id "${1:-}"; _require body_json "${2:-}"; _validate_json "$2"
  _call POST "/pages/$1/move" "$2"
}

# --- Blocks ---
cmd_retrieve_a_block() { _require block_id "${1:-}"; _call GET "/blocks/$1"; }
cmd_update_a_block() {
  _require block_id "${1:-}"; _require body_json "${2:-}"; _validate_json "$2"
  _call PATCH "/blocks/$1" "$2"
}
cmd_delete_a_block() { _require block_id "${1:-}"; _call DELETE "/blocks/$1"; }
cmd_get_block_children() {
  _require block_id "${1:-}"
  local start_cursor="${2:-}" page_size="${3:-}" qs=""
  [ -n "$start_cursor" ] && qs="start_cursor=${start_cursor}"
  if [ -n "$page_size" ]; then
    [ -n "$qs" ] && qs="${qs}&page_size=${page_size}" || qs="page_size=${page_size}"
  fi
  [ -n "$qs" ] && _call GET "/blocks/$1/children?${qs}" || _call GET "/blocks/$1/children"
}
cmd_patch_block_children() {
  _require block_id "${1:-}"; _require body_json "${2:-}"; _validate_json "$2"
  _call PATCH "/blocks/$1/children" "$2"
}

# --- Comments ---
cmd_retrieve_a_comment() {
  _require block_id "${1:-}"
  local block_id="$1" start_cursor="${2:-}" page_size="${3:-}"
  local qs="block_id=${block_id}"
  [ -n "$start_cursor" ] && qs="${qs}&start_cursor=${start_cursor}"
  [ -n "$page_size" ] && qs="${qs}&page_size=${page_size}"
  _call GET "/comments?${qs}"
}
cmd_create_a_comment() {
  _require body_json "${1:-}"; _validate_json "$1"
  _call POST "/comments" "$1"
}

# --- Data Sources ---
cmd_query_data_source() {
  _require data_source_id "${1:-}"
  local body="${2:-{\}}"
  _validate_json "$body"
  _call POST "/data_sources/$1/query" "$body"
}
cmd_retrieve_a_data_source() { _require data_source_id "${1:-}"; _call GET "/data_sources/$1"; }
cmd_update_a_data_source() {
  _require data_source_id "${1:-}"; _require body_json "${2:-}"; _validate_json "$2"
  _call PATCH "/data_sources/$1" "$2"
}
cmd_create_a_data_source() {
  _require body_json "${1:-}"; _validate_json "$1"
  _call POST "/data_sources" "$1"
}
cmd_list_data_source_templates() {
  _require data_source_id "${1:-}"
  _call GET "/data_sources/$1/templates"
}

# --- Databases ---
cmd_retrieve_a_database() { _require database_id "${1:-}"; _call GET "/databases/$1"; }

# --- Help ---
usage() {
  cat <<'EOF'
notion_api.sh — Notion REST API helper (mirrors the official Notion MCP tools)

Users:
  get-self
  get-user <user_id>
  get-users [start_cursor] [page_size]

Search:
  post-search <body_json>

Pages:
  retrieve-a-page <page_id>
  post-page <body_json>
  patch-page <page_id> <body_json>
  retrieve-a-page-property <page_id> <property_id>
  move-page <page_id> <body_json>

Blocks:
  retrieve-a-block <block_id>
  update-a-block <block_id> <body_json>
  delete-a-block <block_id>
  get-block-children <block_id> [start_cursor] [page_size]
  patch-block-children <block_id> <body_json>

Comments:
  retrieve-a-comment <block_id> [start_cursor] [page_size]
  create-a-comment <body_json>

Data sources:
  query-data-source <data_source_id> [body_json]
  retrieve-a-data-source <data_source_id>
  update-a-data-source <data_source_id> <body_json>
  create-a-data-source <body_json>
  list-data-source-templates <data_source_id>

Databases:
  retrieve-a-database <database_id>

Environment:
  NOTION_API_KEY   Required. Notion integration token.
  NOTION_VERSION   Optional. Defaults to 2025-09-03.
EOF
}

# --- Dispatch ---
cmd="${1:-help}"
shift || true

case "$cmd" in
  get-self)                    cmd_get_self "$@" ;;
  get-user)                    cmd_get_user "$@" ;;
  get-users)                   cmd_get_users "$@" ;;
  post-search)                 cmd_post_search "$@" ;;
  retrieve-a-page)             cmd_retrieve_a_page "$@" ;;
  post-page)                   cmd_post_page "$@" ;;
  patch-page)                  cmd_patch_page "$@" ;;
  retrieve-a-page-property)    cmd_retrieve_a_page_property "$@" ;;
  move-page)                   cmd_move_page "$@" ;;
  retrieve-a-block)            cmd_retrieve_a_block "$@" ;;
  update-a-block)              cmd_update_a_block "$@" ;;
  delete-a-block)              cmd_delete_a_block "$@" ;;
  get-block-children)          cmd_get_block_children "$@" ;;
  patch-block-children)        cmd_patch_block_children "$@" ;;
  retrieve-a-comment)          cmd_retrieve_a_comment "$@" ;;
  create-a-comment)            cmd_create_a_comment "$@" ;;
  query-data-source)           cmd_query_data_source "$@" ;;
  retrieve-a-data-source)      cmd_retrieve_a_data_source "$@" ;;
  update-a-data-source)        cmd_update_a_data_source "$@" ;;
  create-a-data-source)        cmd_create_a_data_source "$@" ;;
  list-data-source-templates)  cmd_list_data_source_templates "$@" ;;
  retrieve-a-database)         cmd_retrieve_a_database "$@" ;;
  help|-h|--help)              usage ;;
  *)
    echo "Unknown command: $cmd" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac
