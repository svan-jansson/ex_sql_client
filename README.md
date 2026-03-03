<p align="center">
    <img src="logo/ex_sql_client.svg" alt="netler logo" height="150px">
</p>

[![Build Status](https://github.com/svan-jansson/ex_sql_client/actions/workflows/build-test-publish.yml/badge.svg)](https://github.com/svan-jansson/ex_sql_client/actions/workflows/build-test-publish.yml)
[![Hex pm](https://img.shields.io/hexpm/v/ex_sql_client.svg?style=flat)](https://hex.pm/packages/ex_sql_client)
[![Hex pm](https://img.shields.io/hexpm/dt/ex_sql_client.svg?style=flat)](https://hex.pm/packages/ex_sql_client)

# ExSqlClient

Microsoft SQL Server driver for Elixir based on [Netler](https://github.com/svan-jansson/netler) and .NET's `System.Data.SqlClient`.

## Goals

- Provide a user friendly interface for interacting with MSSQL
- Provide comprehensible type mappings between MSSQL and Elixir
- Real-life implementation of a `Netler` use case to help discover issues and use as proof-of-concept

## Checklist

- ☑ Support encrypted connections
- ☑ Support multiple result sets
- ☑ Implement the `DbConnection` behaviour
  - ☑ Connect
  - ☑ Disconnect
  - ☑ Execute
  - ☑ Transactions
  - ☑ Prepared Statements
- ☑ Release first version on hex.pm
- ☑ Provide an `Ecto.Adapter` that is compatible with Ecto 3

## Installation

Add `ex_sql_client` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_sql_client, "~> 0.4"}
  ]
end
```

To use the Ecto adapter, also add `ecto` and `ecto_sql`:

```elixir
def deps do
  [
    {:ex_sql_client, "~> 0.4"},
    {:ecto, "~> 3.10"},
    {:ecto_sql, "~> 3.10"}
  ]
end
```

---

## Using ExSqlClient Directly

Use this approach when you want low-level access to SQL Server without Ecto, or when you need to run raw DDL, stored procedures, or arbitrary queries.

### Connecting

Start a connection using a standard ADO.NET connection string:

```elixir
{:ok, conn} =
  ExSqlClient.start_link(
    connection_string:
      "Server=myServerAddress;Database=myDataBase;User Id=myUsername;Password=myPassword;"
  )
```

### Executing Queries

Pass parameters as a map with string keys. Use `@paramName` placeholders in your SQL:

```elixir
{:ok, rows} =
  ExSqlClient.query(conn, "SELECT * FROM [records] WHERE [status] = @status", %{status: 1})

# rows is a list of maps, one map per row, with string column names as keys
# e.g. [%{"id" => 1, "status" => 1, "name" => "foo"}, ...]
```

Queries with no parameters:

```elixir
{:ok, rows} = ExSqlClient.query(conn, "SELECT @@VERSION", %{})
```

### Transactions

```elixir
DBConnection.transaction(conn, fn conn ->
  {:ok, _} = ExSqlClient.query(conn, "INSERT INTO [orders] ([ref]) VALUES (@ref)", %{ref: "ORD-1"})
  {:ok, _} = ExSqlClient.query(conn, "UPDATE [stock] SET [qty] = [qty] - 1 WHERE [id] = @id", %{id: 42})
end)
```

### Prepared Statements

```elixir
query = %ExSqlClient.Query{statement: "SELECT * FROM [users] WHERE [email] = @email"}

{:ok, query} = DBConnection.prepare(conn, query)
{:ok, rows}  = DBConnection.execute(conn, query, %{email: "user@example.com"})
:ok          = DBConnection.close(conn, query)
```

---

## Using the Ecto Adapter

`ExSqlClient.Ecto` is a full `Ecto.Adapters.SQL` adapter for Microsoft SQL Server. It generates MSSQL-dialect SQL (bracket identifiers, `TOP(n)`, `OFFSET…FETCH`, `OUTPUT INSERTED/DELETED` for returning) and maps Ecto types to SQL Server column types.

### Setting Up a Repo

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: ExSqlClient.Ecto
end
```

### Configuration

```elixir
# config/config.exs 
config :my_app, MyApp.Repo,
  connection_string:
    "Server=tcp:db.example.com,1433;Database=mydb;User Id=myapp_user;Password=secret;Encrypt=True"
```

Add the repo to your application's supervision tree:

```elixir
def start(_type, _args) do
  children = [
    MyApp.Repo
  ]
  Supervisor.start_link(children, strategy: :one_for_one)
end
```

### Schema Example

```elixir
defmodule MyApp.User do
  use Ecto.Schema

  schema "users" do
    field :name,  :string
    field :email, :string
    field :active, :boolean, default: true
    timestamps()
  end
end
```

### Query Examples

```elixir
# Fetch all active users
MyApp.Repo.all(from u in MyApp.User, where: u.active == true)

# Insert a record and return it
{:ok, user} = MyApp.Repo.insert(%MyApp.User{name: "Alice", email: "alice@example.com"})

# Update
MyApp.Repo.update_all(from(u in MyApp.User, where: u.active == false), set: [name: "Deactivated"])

# Delete
MyApp.Repo.delete_all(from u in MyApp.User, where: u.email == ^"old@example.com")

# Raw SQL via the Ecto adapter
{:ok, result} = MyApp.Repo.query("SELECT @@VERSION")
```

### Known Limitations

| Feature | Status |
|---|---|
| Migrations / DDL | Not supported — use `ExSqlClient.query/3` directly for DDL |
| `Repo.stream/2` | Raises at runtime — cursors are not supported by the protocol |
| `query_many/4` | Raises at runtime — multiple result sets are not supported |
| `on_conflict` | Only `:raise` is supported |
| Window functions | Not supported |
| Materialized CTEs | Not supported |
| `DISTINCT` on multiple columns | Not supported; use `distinct: true` for a distinct result set |
| Aggregate filters (`filter/2`) | Not supported |
| `json_extract_path` | Not supported; use `fragment/1` with `JSON_VALUE`/`JSON_QUERY` instead |
| `OFFSET` without `ORDER BY` | Raises at compile time — SQL Server requires `ORDER BY` when using `OFFSET` |
| `OFFSET` without `LIMIT` | Raises at compile time |

---

## Performance

ExSqlClient uses [Netler](https://github.com/svan-jansson/netler) to communicate with a .NET worker process over a local TCP socket using MessagePack serialisation. Every query involves at least one Elixir → .NET → SQL Server → .NET → Elixir round-trip.

### Benchmark highlights

Measured with `mix run bench/benchmarks.exs` against SQL Server 2022 in a local container. Single-process, `pool_size: 5` for query scenarios, `pool_size: 1` for prepared statements. Machine: Intel Core Ultra 9 285H, Elixir 1.19.5, Erlang/OTP 28.

| Scenario | Median latency | Throughput |
|---|---|---|
| Netler IPC only (no SQL) | 0.022 ms | ~26 000 req/s |
| SELECT constant (`SELECT 1`) | 0.95 ms | ~900 req/s |
| SELECT 1 row | 0.94 ms | ~900 req/s |
| SELECT 1 row, parameterised | 1.13 ms | ~760 req/s |
| SELECT 10 rows | 1.17 ms | ~770 req/s |
| SELECT 100 rows | 1.37 ms | ~670 req/s |
| Prepared statement (SELECT 1 row) | 0.40 ms | ~1 400 req/s |
| INSERT | 5.34 ms | ~180 req/s |
| Transaction (INSERT + commit) | 6.38 ms | ~150 req/s |

### What the numbers mean

**Netler IPC overhead is negligible.** The raw IPC round-trip (no SQL) costs ~0.02 ms. The ~1 ms you see on a simple SELECT is almost entirely SQL Server query execution and ADO.NET overhead — not the Elixir↔.NET transport.

**Prepared statements halve read latency.** Reusing a prepared statement drops median latency from ~0.94 ms to ~0.40 ms by skipping the SQL Server parse/compile step on repeated identical queries.

**Row count has modest impact on reads.** Fetching 100 rows takes ~1.37 ms vs ~0.94 ms for 1 row — the extra 0.4 ms is serialisation and transfer of the additional data.

**Write operations are slower due to SQL Server I/O.** An INSERT takes ~5.3 ms; wrapping it in an explicit transaction adds ~1 ms for the `BEGIN`/`COMMIT` round-trips.

**Throughput scales with pool size.** The figures above are for a single Elixir process. With a larger `pool_size` and concurrent callers, total throughput grows proportionally up to the SQL Server's own limits.

### Running the benchmarks yourself

```bash
# Uses Testcontainers to spin up SQL Server automatically
mix run bench/benchmarks.exs

# Or point at an existing SQL Server instance
MSSQL_CONNECTION_STRING="Server=...;..." mix run bench/benchmarks.exs
```
