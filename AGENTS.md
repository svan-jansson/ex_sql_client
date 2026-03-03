# AGENTS.md

Guidelines for AI agents and automated tools contributing to **ex_sql_client**.

---

## What this project is

`ex_sql_client` is an Elixir Microsoft SQL Server driver. It is a thin Elixir
wrapper over a .NET worker process (via [Netler](https://github.com/svan-jansson/netler))
that uses `Microsoft.Data.SqlClient` to communicate with SQL Server.

The library requires a running SQL Server instance for its integration tests.

---

## Repository layout

```
lib/
  ex_sql_client.ex            # Public API – start_link/query/prepare/transaction
  ex_sql_client/
    protocol.ex               # DBConnection behaviour implementation (Netler RPC)
    query.ex                  # Query struct (statement + statement_id)
    ecto.ex                   # Ecto 3 adapter entry point (use Ecto.Adapters.SQL)
    ecto/
      connection.ex           # Ecto.Adapters.SQL.Connection: SQL generation + result normalisation
dotnet/dotnet_sql_client/
  DotnetSqlClient.csproj      # .NET 8 project file
  Program.cs                  # Netler.NET server bootstrap
  SqlAdapter.cs               # SQL Server operations via Microsoft.Data.SqlClient
test/
  query_test.exs              # Integration: raw query tests
  transaction_test.exs        # Integration: transaction tests
  prepared_statement_test.exs # Integration: prepared statement tests
  data_type_test.exs          # Integration: type mapping tests
  test_helper.exs             # Testcontainers setup and connection string injection
  ecto/
    query_test.exs            # Unit: SQL generation tests (no DB required)
    ecto_adapter_test.exs     # Integration: end-to-end Ecto adapter tests
mix.exs                       # Build config and project metadata
.github/workflows/            # GitHub Actions CI (build + test + publish)
```

---

## Building

Prerequisites: Elixir ≥ 1.9, Erlang/OTP, .NET 8 SDK, running SQL Server instance.

```bash
mix deps.get
mix compile --warnings-as-errors
```

The `--warnings-as-errors` flag is enforced in CI; treat compiler warnings as
bugs.

The Netler compiler (`mix compile.netler`) automatically builds the .NET project
in `dotnet/dotnet_sql_client/` and places the binary in `priv/`.

---

## Testing

Integration tests spin up a SQL Server container automatically via
[Testcontainers](https://hex.pm/packages/testcontainers). Docker (or a
compatible runtime) must be available on the machine.

```bash
mix test --only integration
```

The container is started once in `test/test_helper.exs` and the connection
string is shared with all test modules via `Application.put_env`. All tests are
tagged with `@tag :integration`. There are no unit tests that run without a
live database.

---

## Code conventions

### Elixir

- Format every file with `mix format` before committing. The formatter config
  lives in `.formatter.exs`.
- Follow standard Elixir naming: `snake_case` functions, `CamelCase` modules.
- Public functions should have `@doc` and `@spec` annotations.
- Return values use tagged tuples (`{:ok, value}` / `{:error, reason}`). Do not
  raise exceptions across module boundaries.
- The Netler route names in `Program.cs` must match the atoms used in the
  Elixir protocol layer exactly.

### C\#

- The .NET project targets `net8.0`. Do not downgrade the target framework.
- Use `Microsoft.Data.SqlClient` (not the deprecated `System.Data.SqlClient`).
- Follow existing naming conventions: `PascalCase` for methods and classes,
  `camelCase` for locals.
- Route handler methods in `SqlAdapter.cs` must have the signature
  `public object MethodName(params object[] parameters)`.

---

## Architecture notes

The call chain for a query is:

```
Elixir caller
  → ExSqlClient (DBConnection behaviour)
    → Netler RPC (TCP socket, port process)
      → Program.cs (Netler.NET server)
        → SqlAdapter.cs
          → Microsoft.Data.SqlClient
            → SQL Server
```

Key invariants:
- The .NET process is started by Netler as a port. It listens on a TCP port
  passed as `args[0]`; the Elixir PID is passed as `args[1]`.
- All route names in `Program.cs` must be registered and match what the
  Elixir layer calls via Netler.
- Connection and transaction state is held in `SqlAdapter` — one instance per
  connection process.

---

## What to work on

Good first contributions:
- Expanding test coverage for edge-case data types.
- Adding `@spec` / `@type` annotations to the Elixir modules.
- Improving error propagation from the .NET layer to Elixir.
- Updating dependencies as new versions are released.

Areas requiring extra care:
- Anything touching `Program.cs` or `SqlAdapter.cs` — changes must compile
  with the pinned .NET version and be verified against a live SQL Server.
- Netler version upgrades — the RPC protocol may change between major versions;
  always check `Program.cs` against the new Netler.NET API.
- `DBConnection` behaviour callbacks — maintain compatibility with the
  `db_connection` contract.

---

## Pull request checklist

- [ ] `mix compile --warnings-as-errors` passes.
- [ ] `mix test --only integration` passes against a local SQL Server.
- [ ] `mix format --check-formatted` passes.
- [ ] `mix credo` passes.
- [ ] New public functions have `@doc` and `@spec`.
- [ ] Commit messages are concise and in the imperative mood.

---

## Out of scope

- Windows CI — the SQL Server Docker container is Linux-only in GitHub Actions;
  the library itself is cross-platform but CI runs on Linux.
- Supporting databases other than Microsoft SQL Server.
- Changing the `DBConnection` protocol — maintain compatibility with standard
  Elixir database tooling (Ecto, etc.).
