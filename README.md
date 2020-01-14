# ExSqlClient

[![Build Status](https://travis-ci.com/svan-jansson/ex_sql_client.svg?branch=master)](https://travis-ci.com/svan-jansson/ex_sql_client)

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
- Release first version on hex.pm ☐
- Provide an `Ecto.Adapter` that is compatible with Ecto 3 ☐
