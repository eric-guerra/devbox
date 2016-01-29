#!/usr/bin/env bash
# Shared helpers: logging, prompts, ports, quoting.

if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
  _c_red=$'\e[31m'; _c_green=$'\e[32m'; _c_yellow=$'\e[33m'; _c_blue=$'\e[34m'; _c_off=$'\e[0m'
else
  _c_red=""; _c_green=""; _c_yellow=""; _c_blue=""; _c_off=""
fi

info() { printf '%s›%s %s\n' "$_c_blue" "$_c_off" "$*" >&2; }
ok() { printf '%s✓%s %s\n' "$_c_green" "$_c_off" "$*" >&2; }
warn() { printf '%s!%s %s\n' "$_c_yellow" "$_c_off" "$*" >&2; }
die() { printf '%s✗%s %s\n' "$_c_red" "$_c_off" "$*" >&2; exit 1; }

confirm() {
  [[ "${DEVBOX_YES:-}" == "1" ]] && return 0
  [[ -t 0 ]] || return 1
  local reply
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# Lowercase, alphanumerics and dashes only (docker compose project names).
sanitize_name() {
  local n
  n="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  printf '%s' "${n:-devbox}"
}

# Quote each argument so `devbox run npm test -- --grep "a b"` survives `sh -lc`.
quote_args() {
  local out="" a
  for a in "$@"; do
    out+="$(printf '%q' "$a") "
  done
  printf '%s' "${out% }"
}

port_is_free() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ! ss -ltn "sport = :$port" 2>/dev/null | grep -q LISTEN
  elif command -v lsof >/dev/null 2>&1; then
    ! lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
  else
    # Fallback: try to connect; success means something is listening.
    ! (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null
  fi
}

# First free port at or above $1 (up to 50 tries).
find_free_port() {
  local port="$1" i
  for ((i = 0; i < 50; i++)); do
    if port_is_free "$port"; then
      printf '%s' "$port"
      return 0
    fi
    port=$((port + 1))
  done
  die "no free port found near $1"
}

ensure_gitignore() {
  local entry="$1"
  if [[ -d .git || -f .gitignore ]]; then
    grep -qxF "$entry" .gitignore 2>/dev/null || printf '%s\n' "$entry" >> .gitignore
  fi
}

require_docker() {
  command -v docker >/dev/null 2>&1 || die "docker is not installed (run devbox doctor)"
  docker info >/dev/null 2>&1 || die "docker daemon is not running"
}
