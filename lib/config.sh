#!/usr/bin/env bash
# Loads .devbox (committed) then .devbox.local (per-developer overrides).
# Files are KEY=VALUE lines; they are parsed, never `source`d, so a config file can't run commands.

DEVBOX_ALLOWED_KEYS="DEVBOX_NAME DEVBOX_PORT DEVBOX_CONTAINER_PORT DEVBOX_SERVICE DEVBOX_SHELL DEVBOX_WORKDIR \
TEST_CMD START_CMD WITH_POSTGRES WITH_REDIS WITH_MYSQL POSTGRES_VERSION REDIS_VERSION MYSQL_VERSION CACHE_DIRS EXTRA_ENV"

parse_config_file() {
  local file="$1" line key value lineno=0
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    line="${line%%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    if [[ ! "$line" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      die "$file:$lineno: expected KEY=VALUE"
    fi
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    # Strip one level of matching quotes.
    if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then
      value="${BASH_REMATCH[1]}"
    else
      value="${value%%[[:space:]]#*}"   # trailing comment on unquoted values
      value="${value%"${value##*[![:space:]]}"}"
    fi
    case " $DEVBOX_ALLOWED_KEYS " in
      *" $key "*) printf -v "$key" '%s' "$value"; export "${key?}" ;;
      *) die "$file:$lineno: unknown setting '$key'" ;;
    esac
  done < "$file"
}

validate_port() {
  local name="$1" value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] && ((value >= 1 && value <= 65535)) || die "$name must be a port number (got '$value')"
}

load_config() {
  [[ -f .devbox ]] || die "no .devbox here; run 'devbox init <template>' first"
  parse_config_file .devbox
  parse_config_file .devbox.local

  : "${DEVBOX_NAME:=$(sanitize_name "$(basename "$PWD")")}"
  DEVBOX_NAME="$(sanitize_name "$DEVBOX_NAME")"
  : "${DEVBOX_PORT:=3000}"
  : "${DEVBOX_CONTAINER_PORT:=$DEVBOX_PORT}"
  : "${DEVBOX_SERVICE:=app}"
  : "${DEVBOX_WORKDIR:=/workspace}"
  : "${WITH_POSTGRES:=false}"
  : "${WITH_REDIS:=false}"
  : "${WITH_MYSQL:=false}"
  : "${POSTGRES_VERSION:=16}"
  : "${REDIS_VERSION:=7}"
  : "${MYSQL_VERSION:=8.0}"
  validate_port DEVBOX_PORT "$DEVBOX_PORT"
  validate_port DEVBOX_CONTAINER_PORT "$DEVBOX_CONTAINER_PORT"
  for flag in WITH_POSTGRES WITH_REDIS WITH_MYSQL; do
    [[ "${!flag}" == "true" || "${!flag}" == "false" ]] || die "$flag must be true or false"
  done
  DEVBOX_COMPOSE_FILE=".devbox-compose.yml"
  export DEVBOX_NAME DEVBOX_PORT DEVBOX_CONTAINER_PORT DEVBOX_SERVICE DEVBOX_WORKDIR DEVBOX_COMPOSE_FILE
}
