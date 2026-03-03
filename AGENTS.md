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

There are two categories of tests:

**Unit tests** (no database required) — SQL generation tests for the Ecto adapter:

```bash
mix test test/ecto/query_test.exs
```

**Integration tests** spin up a SQL Server container automatically via
[Testcontainers](https://hex.pm/packages/testcontainers). Docker or a
compatible rootless runtime (e.g. Podman) must be available.

```bash
# Core driver integration tests
mix test --include integration

# All Ecto adapter tests (unit + integration)
mix test test/ecto/ --include integration
```

The container is started once in `test/test_helper.exs` and the connection
string is shared with all test modules via `Application.put_env`. Integration
tests are tagged with `@tag :integration` and are excluded by default; pass
`--include integration` to run them.

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

The call chain for a raw (`ExSqlClient`) query is:

```
Elixir caller
  → ExSqlClient (public API)
    → ExSqlClient.Protocol (DBConnection behaviour)
      → Netler RPC (TCP socket, port process)
        → Program.cs (Netler.NET server)
          → SqlAdapter.cs
            → Microsoft.Data.SqlClient
              → SQL Server
```

When using the Ecto adapter, an additional layer sits in front:

```
Ecto / Repo
  → ExSqlClient.Ecto (Ecto.Adapters.SQL)
    → ExSqlClient.Ecto.Connection (SQL generation, result normalisation)
      → ExSqlClient.Protocol (DBConnection behaviour)
        → … (same chain as above)
```

Key invariants:
- The .NET process is started by Netler as a port. It listens on a TCP port
  passed as `args[0]`; the Elixir PID is passed as `args[1]`.
- All route names in `Program.cs` must be registered and match what the
  Elixir layer calls via `Netler.Client.invoke/3`.
- Connection and transaction state is held in `SqlAdapter` — one instance per
  connection process.
- The Ecto adapter generates MSSQL-dialect SQL: bracket identifiers `[name]`,
  `TOP(n)` for limits without offset, `OFFSET … FETCH NEXT … ROWS ONLY` for
  pagination, and `OUTPUT INSERTED/DELETED` for `RETURNING`.
- Netler/MessagePack deserialises result rows as Elixir `Map`, which sorts
  string keys alphabetically. `ExSqlClient.Ecto.Connection` recovers the
  correct column order by parsing the SELECT projection or OUTPUT clause from
  the SQL string before returning results to Ecto.

---

## What to work on

Good first contributions:
- Expanding test coverage for edge-case data types.
- Adding `@spec` / `@type` annotations to the Elixir modules.
- Improving error propagation from the .NET layer to Elixir.
- Updating dependencies as new versions are released.
- Expanding `test/ecto/query_test.exs` with additional SQL generation cases.

Areas requiring extra care:
- Anything touching `Program.cs` or `SqlAdapter.cs` — changes must compile
  with the pinned .NET version and be verified against a live SQL Server.
- `SqlAdapter.cs` DML result handling — `ExecuteReader` is used for all
  statements so that `OUTPUT` clauses are supported; `RecordsAffected` is
  captured inside the `using` block and injected as a synthetic
  `__rows_affected__` row for DML without an `OUTPUT` clause.
- Netler version upgrades — the RPC protocol may change between major versions;
  always check `Program.cs` against the new Netler.NET API.
- `DBConnection` behaviour callbacks — maintain compatibility with the
  `db_connection` contract.
- `ExSqlClient.Ecto.Connection` — column-order recovery relies on regex parsing
  of the generated SQL; changes to the SQL generator must keep
  `column_order_from_sql/1` in sync.

---

## Pull request checklist

- [ ] `mix compile --warnings-as-errors` passes.
- [ ] `mix test test/ecto/query_test.exs` passes (no DB needed).
- [ ] `mix test --include integration` passes against a local SQL Server.
- [ ] `mix test test/ecto/ --include integration` passes for Ecto adapter changes.
- [ ] `mix format --check-formatted` passes.
- [ ] `mix credo` passes.
- [ ] New public functions have `@doc` and `@spec`.
- [ ] Commit messages are concise and in the imperative mood.

---

## Out of scope

- Windows CI — the SQL Server Docker container is Linux-only in GitHub Actions;
  the library itself is cross-platform but CI runs on Linux.
- Supporting databases other than Microsoft SQL Server.
- Ecto migrations / DDL — `execute_ddl/1` raises intentionally; use
  `ExSqlClient.query/3` directly for schema changes.
- `Repo.stream/2` and cursor-based fetching — the Netler/C# layer does not
  implement server-side cursors.
- Multiple result sets via the Ecto adapter (`query_many/4` raises); use the
  raw `ExSqlClient` API if you need multiple result sets.
- Changing the `DBConnection` protocol — maintain compatibility with standard
  Elixir database tooling.
