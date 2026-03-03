<p align="center">
    <img src="logo/ex_sql_client.svg" alt="netler logo" height="150px">
</p>

[![Build Status](https://travis-ci.com/svan-jansson/ex_sql_client.svg?branch=master)](https://travis-ci.com/svan-jansson/ex_sql_client)
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

For encrypted connections:

```elixir
{:ok, conn} =
  ExSqlClient.start_link(
    connection_string:
      "Server=myServerAddress,1433;Database=myDataBase;User Id=sa;Password=secret;TrustServerCertificate=True;"
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
    "Server=localhost,1433;Database=mydb;User Id=sa;Password=secret;TrustServerCertificate=True"
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
