# Deploying GeneScout publicly

GeneScout is a standard R Shiny app. It ships an `app.R` entrypoint (for hosts
that expect a single-file app, such as some Posit Connect and shinyapps.io
workflows) that reuses the canonical `global.R` / `ui.R` / `server.R` definition,
so either entrypoint runs the same app. The deterministic ranking needs **no API
key**; the optional AI stages use a key the
user pastes in the browser (BYOK) that lives only in the session. This guide
covers the settings that matter when the app is exposed to the public internet.

## Posit Connect Cloud (manifest.json)

Posit Connect Cloud deploys from a Git repo and needs a `manifest.json` at the
repo root (beside `app.R`) that pins the R version and package dependencies. It is
committed here, captured from the pinned `renv.lock`, so the deployed environment
matches the tested one. Regenerate it whenever dependencies change:

```r
rsconnect::writeManifest(appDir = ".")
```

An `.rscignore` keeps local and secret files (`.Renviron`, `presentations/`,
`docs/local/`, `.RData`) out of the bundle, and the committed manifest lists only
Git-tracked files. If you regenerate, confirm `.Renviron` never appears in
`manifest.json`.

The manifest pins R `4.6.1` (from `renv.lock`). If Connect Cloud reports an
unsupported R version, align `renv.lock` to a supported version and regenerate.

## App-level settings (already wired)

Set the environment variable `GENESCOUT_PRODUCTION=1` for public deployments. It
turns on production-safe behaviour in `global.R` / `server.R`:

- **Sanitized errors**: `options(shiny.sanitize.errors = TRUE)` so internal error
  messages are not leaked to the browser. (Left off in development so errors stay
  debuggable.)
- **Reconnection**: `session$allowReconnect(TRUE)`, so a session survives a
  transient network drop when the host supports reconnect (below).

Always on (independent of the flag):

- **Upload size**: `options(shiny.maxRequestSize = 30 * 1024^2)` (30 MB), well
  above any realistic single-column gene list. Raise it in `global.R` if needed.

## Session, idle, and connection timeouts

Open-source Shiny has **no built-in idle timeout**; those are set by the host.
Increase them so long-running reviews (a large disease-discovery run, or a user
reading results) are not disconnected:

- **shinyapps.io / Posit Connect**: in `rsconnect::deployApp()` or the dashboard,
  raise **Idle timeout** (`appIdleTimeout`, disconnect after inactivity) and the
  **connection/read timeout** (`appConnectionTimeout`). For a demo, 15-30 min idle
  is comfortable. Also raise **max worker/connection** limits for concurrency.
- **Shiny Server (open source / Pro)**: in `/etc/shiny-server/shiny-server.conf`
  set `app_init_timeout` (startup) and `app_idle_timeout` (0 disables idle culling)
  under the `location` block; front with nginx and raise `proxy_read_timeout`.
- **ShinyProxy**: set `proxy.heartbeat-rate` / `proxy.heartbeat-timeout` and the
  container `proxy.container-wait-time`; scale `proxy.max-instances` for concurrency.

## Reverse proxy (nginx / Traefik)

WebSockets must be proxied for Shiny to work, and read timeouts must exceed a long
run:

```nginx
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_read_timeout 1800s;   # >= your longest expected run
client_max_body_size 30m;   # match shiny.maxRequestSize
```

Terminate **HTTPS** at the proxy: BYOK keys and results should never travel in the
clear.

## Keys, data, and safety

- **BYOK keys** are per-session only: never stored, logged, or persisted (see
  `R/byok.R`). Do **not** bake a provider key into the image for a public instance;
  let each user supply their own, or gate the AI features behind auth.
- **Research use only.** The app never emits clinical/diagnostic output; keep the
  disclaimer visible (it is, on every page).
- **Only public/synthetic example data** ships in `data/examples/`. Never deploy an
  instance seeded with real patient data.
- **Rate/cost.** The public bio-database clients are cached (30-min success-only)
  and the interactive run caps gene and seed counts; for a busy public instance,
  consider a caching reverse proxy and per-source rate limits.

## Container

A `Dockerfile` is included. Build and run, passing the production flag:

```sh
docker build -t genescout .
docker run -p 3838:3838 -e GENESCOUT_PRODUCTION=1 genescout
```

Pin dependencies via `renv.lock` (already committed) so the image is reproducible.
