# ExSqlClient

[![Build Status](https://travis-ci.com/svan-jansson/ex_sql_client.svg?branch=master)](https://travis-ci.com/svan-jansson/ex_sql_client)

MSSQL driver for Elixir based on Netler and .NET's `System.Data.SqlClient`.

## Goals

- Provide an easy-to-use interface for interacting with MSSQL
- Provide comprehensible type mappings between MSSQL and Elixir
- Support encrypted connections
- Support multiple result sets
- Implement the `DbConnection` behaviour
- Provide an `Ecto.Adapter` that is compatible with Ecto 3
