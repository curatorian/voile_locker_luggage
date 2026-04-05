# Voile Locker & Luggage Plugin

A visitor locker management plugin for [Voile](https://github.com/curatorian/voile), the open-source GLAM library management system.

Provides per-node locker assignment during visitor check-in, staff management UI, session history, and auto-expiry.

## Features

- Per-node locker enable/disable toggle
- Configurable locker count per node
- Auto-assign available locker during visitor check-in
- Manual locker assignment and release by staff
- Locker statuses: `available`, `occupied`, `maintenance`, `reserved`
- Session history with timestamps and release tracking
- Admin UI at `/manage/plugins/locker_luggage/`

---

## Requirements

| Requirement      | Version    |
| ---------------- | ---------- |
| Elixir           | `~> 1.18`  |
| OTP              | `~> 27`    |
| Phoenix LiveView | `~> 1.1`   |
| Voile            | `>= 0.1.2` |
| PostgreSQL       | `>= 14`    |

---

## Installation

### Option A — From Hex _(coming soon)_

```elixir
# mix.exs
{:voile_locker_luggage, "~> 0.1.0"}
```

### Option B — From GitHub (recommended for now)

You can pin to a specific release tag:

```elixir
# mix.exs
{:voile_locker_luggage,
  github: "curatorian/voile_locker_luggage",
  tag: "v0.1.0",
  sparse: "."
}
```

Or track the latest commit on main (not recommended for production):

```elixir
{:voile_locker_luggage,
  github: "curatorian/voile_locker_luggage",
  branch: "main",
  sparse: "."
}
```

### Option C — From a local path (development / self-hosted)

If you have cloned this repository alongside your Voile installation:

```elixir
# mix.exs — inside the host Voile app
{:voile_locker_luggage, path: "plugins/voile_locker_luggage"}
```

This is the recommended approach if you are running Voile from source in a
monorepo-style setup (all plugins live under `plugins/` inside the Voile repo).

---

## Setup Steps

After adding the dependency, follow these steps inside your **Voile host app**:

### 1. Fetch dependencies

```bash
mix deps.get
```

### 2. Compile

```bash
mix compile
```

The plugin is a separate OTP application and will be compiled alongside Voile.

### 3. Install the plugin from the admin UI

Start Voile and navigate to:

```
/manage/plugins
```

Click **"Install"** next to _Locker & Luggage_. This runs the plugin's database
migrations and registers it in `voile_plugins`.

Alternatively, install via IEx:

```elixir
Voile.PluginManager.install("Elixir.VoileLockerLuggage")
```

### 4. Activate the plugin

After installing, click **"Activate"** in the admin UI, or via IEx:

```elixir
Voile.PluginManager.activate("Elixir.VoileLockerLuggage")
```

Activation registers the check-in hook so the plugin participates in visitor flows.

### 5. Configure per-node

Navigate to `/manage/plugins/locker_luggage/nodes` and enable the locker system for
each node (library branch / service desk) that has physical lockers.

### 6. Configure plugin settings

Navigate to `/manage/plugins/locker_luggage/settings` to configure:

| Setting                       | Default | Description                                                |
| ----------------------------- | ------- | ---------------------------------------------------------- |
| Allow Self-Release            | `true`  | Visitors can release their own locker at check-out         |
| Auto-Expire After (hours)     | `24`    | Expire sessions automatically after N hours (0 = disabled) |
| Show Locker Number on Receipt | `true`  | Print locker number on check-in receipt                    |
| Notify Staff on Expiry        | `false` | Dashboard notification when a session expires              |

---

## Database Migrations

Migrations are applied automatically when you **Install** the plugin from the
admin UI. They run against the same PostgreSQL database as the Voile host app.

Tables created by this plugin are prefixed with `plugin_locker_luggage_`:

- `plugin_locker_luggage_lockers` — individual locker records per node
- `plugin_locker_luggage_sessions` — assignment history (active + closed)
- `plugin_locker_luggage_node_configs` — per-node enable/disable and locker count

To roll back all migrations (performed when you **Uninstall** the plugin):

```elixir
Voile.PluginManager.uninstall("Elixir.VoileLockerLuggage")
```

> **Warning:** Uninstalling drops all plugin tables and their data permanently.

---

## Production Installation

### Using `mix release`

Elixir releases bake in all compiled code and dependencies at build time.
Because the plugin is a dependency in `mix.exs`, it is automatically included
in the release artifact.

**Build steps:**

```bash
# 1. Add the dep to mix.exs (see Installation above), then:
mix deps.get --only prod
MIX_ENV=prod mix compile

# 2. Build the release
MIX_ENV=prod mix release

# 3. Deploy the release artifact to the server
# (copy _build/prod/rel/voile/ to the target machine)

# 4. On the server, start the app
./bin/voile start

# 5. Install and activate the plugin (one-time, via remote IEx)
./bin/voile remote
iex> Voile.PluginManager.install("Elixir.VoileLockerLuggage")
iex> Voile.PluginManager.activate("Elixir.VoileLockerLuggage")
```

From the second deployment onward, the plugin is already registered in the
database — just redeploying the release is enough. If there are new migrations,
call `on_update/2` or re-run install from the admin UI.

### Using Podman / Docker (container-based)

The plugin must be included in the container image at **build time** — there is
no dynamic plugin loading at container runtime. The image acts as the release
artifact.

**Example `Containerfile` / `Dockerfile` additions:**

```dockerfile
# If using Option C (local path dep):
# Make sure the plugin dir is copied before mix deps.get
COPY plugins/ plugins/

# Standard Phoenix build steps — no changes needed
RUN mix deps.get --only prod
RUN MIX_ENV=prod mix compile
RUN MIX_ENV=prod mix release
```

If using Option B (GitHub dep), no extra COPY step is needed — `mix deps.get`
fetches the plugin automatically during the image build.

**Plugin activation in a containerised environment:**

Since you cannot do an interactive IEx session easily in production containers,
you can activate the plugin via a release eval command in your startup script
or Docker entrypoint:

```bash
# In entrypoint.sh or deploy script — runs once on first deploy
./bin/voile eval "Voile.PluginManager.install(\"Elixir.VoileLockerLuggage\")"
./bin/voile eval "Voile.PluginManager.activate(\"Elixir.VoileLockerLuggage\")"
```

Or add an idempotent task to your Voile deployment hooks so it is safe to run
on every container restart:

```bash
# Safe to run every time — install/activate are no-ops if already done
./bin/voile eval "
  case Voile.Plugins.get_plugin_by_plugin_id(\"locker_luggage\") do
    nil -> Voile.PluginManager.install(\"Elixir.VoileLockerLuggage\")
    _ -> :ok
  end
"
```

> **Key rule:** Adding or removing a plugin always requires rebuilding the
> container image and redeploying. This is by design — plugins are trusted
> compiled Elixir code, not dynamic bytecode.

---

## Updating the Plugin

### 1. Update the version in `mix.exs`

```elixir
# Change tag to the new release
{:voile_locker_luggage, github: "your-org/voile_locker_luggage", tag: "v1.1.0"}
```

### 2. Fetch and rebuild

```bash
mix deps.update voile_locker_luggage
mix deps.get
MIX_ENV=prod mix release   # or rebuild the container image
```

### 3. Run update migrations

From the admin UI at `/manage/plugins`, click **"Update"**. This calls
`on_update/2` which runs any new migrations.

Or via release eval:

```bash
./bin/voile eval "Voile.PluginManager.update(\"Elixir.VoileLockerLuggage\")"
```

---

## Version Checking

This plugin exposes its current version via `VoileLockerLuggage.metadata/0`:

```elixir
VoileLockerLuggage.metadata().version  # "1.0.0"
```

Voile's plugin system is designed to support automatic version-checking against
GitHub Releases. When implemented, the check works as follows:

1. Voile periodically fetches `https://api.github.com/repos/curatorian/voile_locker_luggage/releases/latest`
2. Compares the `tag_name` against the installed plugin's `metadata().version`
3. Shows an **"Update available"** badge in `/manage/plugins` if a newer version exists

This is an upcoming feature of the core Voile plugin manager. Until then, check
the [GitHub Releases page](https://github.com/curatorian/voile_locker_luggage/releases)
manually for new versions.

---

## Uninstalling

1. Navigate to `/manage/plugins`
2. Click **"Deactivate"** — removes all hooks from the running system
3. Click **"Uninstall"** — rolls back all database migrations

> Warning: Uninstalling permanently drops all locker and session data.

4. Remove the dependency from `mix.exs`:

```elixir
# Remove or comment out:
# {:voile_locker_luggage, ...}
```

5. Rebuild and redeploy.

---

## Development

Clone this repository alongside Voile for local development:

```bash
git clone https://github.com/curatorian/voile_locker_luggage \
  /path/to/voile/plugins/voile_locker_luggage
```

Ensure Voile's `mix.exs` references the plugin as a path dep (see Option C above).

Plugin code hot-reloads automatically in dev mode — changes to `.ex` and `.heex`
files under `plugins/` are picked up by Phoenix's live reload without restarting
the server.

### Running plugin migrations in dev

```bash
cd /path/to/voile
mix ecto.migrate   # runs both core and plugin migrations
```

Or trigger via the admin UI after installing the plugin in dev.

---

## Architecture

This plugin follows the [Voile Plugin System](https://github.com/curatorian/voile/blob/main/plans/voile-plugin-system.md) contract:

- Implements the `Voile.Plugin` behaviour (`metadata/0`, `on_install/0`, `on_activate/0`, `on_deactivate/0`, `on_uninstall/0`, `on_update/2`, `hooks/0`, `routes/0`, `nav/0`, `settings_schema/0`)
- Ships its own Ecto migrations under `priv/migrations/`
- Uses `Voile.Repo` for all database operations
- Registers hooks via `Voile.Hooks` to extend core behaviour
- Mounts LiveViews under `/manage/plugins/locker_luggage/`

---

## License

Apache 2.0 — see [LICENSE](LICENSE).
