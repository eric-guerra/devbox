#!/usr/bin/env bash
# Tiny test harness: runs each test_* function in a fresh temp project with a stub `docker`
# on PATH that records its arguments, so the CLI can be tested without a Docker daemon.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVBOX="$ROOT/bin/devbox"
PASS=0
FAIL=0

setup() {
  WORK="$(mktemp -d)"
  mkdir -p "$WORK/stub" "$WORK/My Project"
  cat > "$WORK/stub/docker" <<'STUB'
#!/usr/bin/env bash
echo "docker $*" >> "$DOCKER_LOG"
case "$*" in
  "info") exit 0 ;;
  *"ps -q"*) [[ -f "$DOCKER_RUNNING" ]] && echo "abc123"; exit 0 ;;
esac
exit 0
STUB
  chmod +x "$WORK/stub/docker"
  export PATH="$WORK/stub:$PATH" DOCKER_LOG="$WORK/docker.log" DOCKER_RUNNING="$WORK/running" NO_COLOR=1
  : > "$DOCKER_LOG"
  cd "$WORK/My Project" || exit 1
}

teardown() {
  cd / && rm -rf "$WORK"
}

assert_eq() {
  [[ "$1" == "$2" ]] || { echo "    expected: $2"; echo "    actual:   $1"; return 1; }
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || { echo "    expected to contain: $2"; echo "    in: $1"; return 1; }
}

assert_fails() {
  local out
  if out="$("$@" 2>&1)"; then echo "    expected failure: $*"; return 1; fi
  LAST_OUTPUT="$out"
}

# ---------------------------------------------------------------- tests

test_init_creates_config_with_sanitized_name() {
  "$DEVBOX" init node 2>/dev/null || return 1
  [[ -f Dockerfile.dev ]] || { echo "    no Dockerfile.dev"; return 1; }
  assert_contains "$(cat .devbox)" "DEVBOX_NAME=my-project"
  assert_fails "$DEVBOX" init node && assert_contains "$LAST_OUTPUT" "already exists"
}

test_init_rejects_unknown_template() {
  assert_fails "$DEVBOX" init cobol && assert_contains "$LAST_OUTPUT" "unknown template"
}

test_config_parser_rejects_unknown_keys_and_never_executes() {
  printf 'DEVBOX_NAME=x\nRM_RF=$(touch pwned)\n' > .devbox
  assert_fails "$DEVBOX" status && assert_contains "$LAST_OUTPUT" "unknown setting 'RM_RF'"
  [[ ! -f pwned ]] || { echo "    config was executed!"; return 1; }
  printf 'DEVBOX_NAME=$(touch pwned)\n' > .devbox
  "$DEVBOX" status >/dev/null 2>&1
  [[ ! -f pwned ]] || { echo "    value was executed!"; return 1; }
}

test_config_validates_ports_and_flags() {
  printf 'DEVBOX_PORT=99999\n' > .devbox
  assert_fails "$DEVBOX" status && assert_contains "$LAST_OUTPUT" "DEVBOX_PORT must be a port"
  printf 'WITH_REDIS=yes\n' > .devbox
  assert_fails "$DEVBOX" status && assert_contains "$LAST_OUTPUT" "WITH_REDIS must be true or false"
  printf 'garbage line\n' > .devbox
  assert_fails "$DEVBOX" status && assert_contains "$LAST_OUTPUT" ".devbox:1: expected KEY=VALUE"
}

test_local_overrides_win() {
  printf 'DEVBOX_NAME=base\nDEVBOX_PORT=3000 # comment\n' > .devbox
  printf 'DEVBOX_NAME="Override Name"\n' > .devbox.local
  "$DEVBOX" status 2>/dev/null
  assert_contains "$(cat "$DOCKER_LOG")" "compose -p override-name"
}

test_up_renders_compose_with_services() {
  printf 'DEVBOX_NAME=api\nDEVBOX_PORT=45678\nWITH_POSTGRES=true\nWITH_REDIS=true\nCACHE_DIRS=/workspace/node_modules\nEXTRA_ENV="FOO=bar"\n' > .devbox
  "$DEVBOX" up 2>/dev/null || return 1
  local yml
  yml="$(cat .devbox-compose.yml)"
  assert_contains "$yml" '"45678:45678"' &&
  assert_contains "$yml" "DATABASE_URL=postgres://dev:dev@postgres:5432/dev" &&
  assert_contains "$yml" "REDIS_URL=redis://redis:6379" &&
  assert_contains "$yml" "FOO=bar" &&
  assert_contains "$yml" "cache0:/workspace/node_modules" &&
  assert_contains "$yml" "condition: service_healthy" &&
  assert_contains "$(cat "$DOCKER_LOG")" "compose -p api -f .devbox-compose.yml up -d --build"
}

test_run_requires_running_container_and_quotes_args() {
  printf 'DEVBOX_NAME=api\nDEVBOX_PORT=45679\n' > .devbox
  assert_fails "$DEVBOX" run echo hi && assert_contains "$LAST_OUTPUT" "has not been started"
  "$DEVBOX" up 2>/dev/null
  assert_fails "$DEVBOX" run echo hi && assert_contains "$LAST_OUTPUT" "is not running"
  touch "$DOCKER_RUNNING"
  "$DEVBOX" run npm test -- --grep "two words" 2>/dev/null
  assert_contains "$(cat "$DOCKER_LOG")" 'exec -T app sh -lc npm test -- --grep two\ words'
}

test_test_command_uses_config() {
  printf 'DEVBOX_NAME=api\nDEVBOX_PORT=45680\nTEST_CMD="make check"\n' > .devbox
  "$DEVBOX" up 2>/dev/null
  touch "$DOCKER_RUNNING"
  "$DEVBOX" test 2>/dev/null
  assert_contains "$(cat "$DOCKER_LOG")" "exec -T app sh -lc make check"
}

test_clean_requires_confirmation() {
  printf 'DEVBOX_NAME=api\n' > .devbox
  "$DEVBOX" clean </dev/null 2>/dev/null
  [[ "$(cat "$DOCKER_LOG")" != *"down --volumes"* ]] || { echo "    cleaned without confirmation"; return 1; }
  DEVBOX_YES=1 "$DEVBOX" clean 2>/dev/null
  assert_contains "$(cat "$DOCKER_LOG")" "down --volumes --rmi local"
}

test_start_cmd_renders_single_command() {
  printf 'DEVBOX_NAME=api\nDEVBOX_PORT=45681\nSTART_CMD="npm run dev -- --port 3000"\n' > .devbox
  "$DEVBOX" up 2>/dev/null
  local cmd
  cmd="$(grep 'command:' .devbox-compose.yml)"
  assert_eq "$cmd" '    command: ["sh", "-lc", "npm run dev -- --port 3000"]'
  [[ "$(cat .devbox-compose.yml)" != *"volumes:"$'\n'"  "* ]] || true
}

test_unknown_command() {
  assert_fails "$DEVBOX" frobnicate && assert_contains "$LAST_OUTPUT" "unknown command"
}

# ---------------------------------------------------------------- runner

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  setup
  if out="$($t 2>&1)"; then
    PASS=$((PASS + 1)); echo "ok   $t"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $t"; [[ -n "$out" ]] && echo "$out"
  fi
  teardown
done
echo "---- $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
