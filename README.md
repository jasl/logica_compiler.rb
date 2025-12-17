# logica_compiler

`logica_compiler` integrates [Logica](https://github.com/evgskv/logica) as an **offline SQL compiler**:

- You author Logica programs (`.l`)
- During build/dev, they are compiled into **digested** `.sql` files + a `manifest.json`
- At runtime, your Rails app **only reads the manifest + SQL** and executes via ActiveRecord

This keeps your web process fast (no runtime compilation) and avoids running a separate Python query service.

## What this gem provides

- **Compiler**: `.l` → digested `.sql` + `.meta.json` + `manifest.json`
- **Safety checks**: only allow `SELECT/WITH`, disallow multi-statement `;`, disallow row locks (`FOR UPDATE`, …) and DDL/DML keywords
- **CLI (Thor)**: `install / compile / clean / watch / version`
- **Optional ActiveRecord runner**: execute compiled SQL with binds, dialect-aware placeholders
  - Postgres: `$1, $2, ...` + `SET LOCAL statement_timeout`
  - SQLite: `?` placeholders + timeout no-op
- **Rails install task** (via Railtie): `rake logica_compiler:install` generates thin integration files into your app

## Installation

```ruby
# Gemfile
gem "logica_compiler"
```

Then:

```bash
bundle install
bundle exec rake logica_compiler:install
```

This generates (idempotently):

- `logica/config.yml` (with a demo query)
- `logica/requirements.txt` (pins `logica==1.3.1415926535897`)
- `logica/programs/hello_world.l` (demo program)
- `logica/programs/.keep`, `logica/compiled/.keep`
- `.gitignore` rules to ignore `logica/compiled/*` (but keep `.keep`)
- `bin/logica` (thin wrapper around the gem CLI)
- `config/initializers/logica_compiler.rb` (injects registry + runner into `Rails.application.config.x.logica`)

## CLI usage

From the Rails app root:

```bash
# ensure Python Logica is available (uses .venv/bin/logica if present, otherwise `logica` on PATH, otherwise installs into tmp/logica_venv)
bin/logica install

# compile everything in logica/config.yml to digested SQL + manifest
bin/logica compile

# compile a single query
bin/logica compile hello_world

# watch logica/programs/**/*.l and recompile on change
bin/logica watch
```

### Using a system-installed Python `logica`

If you install Python Logica globally (and `logica` is on `PATH`), `bin/logica compile` will use it automatically.
You can still force a specific executable path via `LOGICA_BIN`:

```bash
python -m pip install logica==1.3.1415926535897
bin/logica compile

# or override explicitly
LOGICA_BIN=/usr/local/bin/logica bin/logica compile
```

## Configuration (`logica/config.yml`)

Example:

```yaml
engine: postgres
output_dir: logica/compiled

queries:
  hello_world:
    program: logica/programs/hello_world.l
    predicate: Greet
```

Notes:

- If your program declares `@Engine("...");`, it must match `engine` in config.
- If you omit `@Engine(...)`, the compiler will prepend `@Engine("<engine>");` automatically.

## Running compiled queries in Rails

After compilation, the initializer provides:

- `Rails.application.config.x.logica.registry`
- `Rails.application.config.x.logica.runner`

Example:

```ruby
Rails.application.config.x.logica.runner.exec(:hello_world, statement_timeout: nil)
```

## Development (inside this repo)

Run gem tests:

```bash
bundle install --all
bundle exec rake
```

The SQLite e2e test (`test/sqlite_e2e_test.rb`) will **skip** if:

- ActiveRecord/sqlite3 gems are unavailable, or
- Python `logica` CLI cannot be found (via `LOGICA_BIN` or on PATH)

CI installs Python Logica so the e2e test runs there.

## Environment variables

- `LOGICA_BIN`: path or command name of the Python `logica` executable (optional; defaults to `.venv/bin/logica` if present, otherwise `logica` on `PATH`, otherwise `tmp/logica_venv/.../logica`)
- `LOGICA_COMPILE_TIMEOUT`: compile timeout seconds (default 30)
- `LOGICA_PYTHON`, `LOGICA_REQUIREMENTS`, `LOGICA_VENV`: advanced install overrides for the CLI
- `FORCE=1`: for `rake logica_compiler:install` only (overwrite generated files if they already exist)

For compilation, use CLI flags instead:

- `bin/logica compile --force`
- `bin/logica compile --no-prune`

## License

MIT. See `LICENSE.txt`.
