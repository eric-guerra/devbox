# DevBox

A small Bash CLI that gives every project a reproducible, containerized development environment, plus a **Jenkins** setup that runs CI in the *same* containers. You get one `.devbox` file per repo and `devbox up` / `devbox test` everywhere.

> Portfolio reference implementation of a 2015 developer-productivity project (Docker + Bash + Jenkins), using Compose v2 and Jenkins Configuration as Code.

## Usage

```bash
./install.sh
cd my-service
devbox init node          # or python, java
devbox up                 # builds Dockerfile.dev, starts app + postgres/redis/mysql if enabled
devbox shell
devbox run npm run migrate
devbox test               # runs TEST_CMD inside the container
devbox doctor             # docker, daemon, compose v2, port checks
devbox down | clean
```

`.devbox` (committed) and `.devbox.local` (per developer, gitignored):

```ini
DEVBOX_NAME=orders-api
DEVBOX_PORT=3000
TEST_CMD="npm ci && npm test"
CACHE_DIRS=/workspace/node_modules
WITH_POSTGRES=true
WITH_REDIS=false
EXTRA_ENV="LOG_LEVEL=debug"
```

## Design choices

- **Config is parsed, never `source`d**: an allow-list of keys, with errors that include the line number. A malicious or typo'd config can't execute commands (covered by a test).
- **Generated compose file**: services get healthchecks, and the app waits for `service_healthy`. Connection URLs are injected as env vars. Dependency caches live in named volumes, so bind mounts stay fast on macOS and Windows and native modules don't clash.
- **Port conflicts** are detected, and the next free port is used with a warning.
- **Safe arguments**: `devbox run` shell-quotes each argument before `sh -lc`, so `--grep "two words"` survives.
- **CI parity**: the [Jenkinsfile](Jenkinsfile) runs `devbox up` / `devbox test` with a per-build project name (no collisions between parallel builds), publishes JUnit results, and always cleans up. [jenkins/](jenkins/) provisions a controller and a Docker-capable agent entirely from code (JCasC, plugins.txt, job DSL), with no setup wizard.

## Test

```bash
bash tests/run.sh
```

The tests use a stub `docker` binary on `PATH` that records invocations, so the CLI is tested without a Docker daemon.
