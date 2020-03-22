<p align="center">
    <img src="logo/ex_sql_client.svg" alt="netler logo" height="150px">
</p>

[![Build Status](https://travis-ci.com/svan-jansson/ex_sql_client.svg?branch=master)](https://travis-ci.com/svan-jansson/ex_sql_client)
[![Hex pm](https://img.shields.io/hexpm/v/ex_sql_client.svg?style=flat)](https://hex.pm/packages/ex_sql_client)
[![Hex pm](https://img.shields.io/hexpm/dt/ex_sql_client.svg?style=flat)](https://hex.pm/packages/ex_sql_client)

# ExSqlClient

MSSQL driver for Elixir based on [Netler](https://github.com/svan-jansson/netler) and .NET's `System.Data.SqlClient`.

## Goals

- Provide a user friendly interface for interacting with MSSQL
- Provide comprehensible type mappings between MSSQL and Elixir

## Checklist

- Support encrypted connections ☑
- Support multiple result sets ☑
- Implement the `DbConnection` behaviour
  - Connect ☑
    - Disconnect ☑
  - Execute ☑
  - Transactions ☑
  - Prepared Statements ☑
- Release first version on hex.pm ☑
- Provide an `Ecto.Adapter` that is compatible with Ecto 3 ☐

## Code Examples

### Connecting to a Server and Executing a Query

```elixir
{:ok, conn} =
      ExSqlClient.start_link(
        connection_string:
          "Server=myServerAddress;Database=myDataBase;User Id=myUsername;Password=myPassword;"
      )

{:ok, response} =
      ExSqlClient.query(conn, "SELECT * FROM [records] WHERE [status]=@status", %{status: 1})
```