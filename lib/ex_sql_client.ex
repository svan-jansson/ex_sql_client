defmodule ExSqlClient do
  @moduledoc """
  This module implements [DbConnection](https://hexdocs.pm/db_connection) to handle connections to a Microsoft SQL Server database
  """

  alias ExSqlClient.Query

  @doc """
  Creates a supervisor child specification for a pool of connections.
  See `start_link/2` for options.
  """
  def child_spec(opts) do
    DBConnection.child_spec(ExSqlClient.Protocol, default(opts))
  end

  @doc """
  Starts and links to a database connection process.
  By default the `DBConnection` starts a pool with a single connection.
  The size of the pool can be increased with `:pool_size`. A separate
  pool can be given with the `:pool` option.
  """
  def start_link(opts \\ []) do
    DBConnection.start_link(ExSqlClient.Protocol, default(opts))
  end

  @doc """
  Executes a query on a given connection. Returns `{:ok, result}` or `{:error, reason}`.
  """
  def query(conn, query, params \\ %{}, opts \\ []) do
    query = %Query{statement: query}
    response = DBConnection.prepare_execute(conn, query, params, opts)

    case response do
      {:ok, _query, result} -> {:ok, result}
      _ -> response
    end
  end

  @doc """
  Prepare a query with a database connection for later execution.
  It returns `{:ok, query}` on success or `{:error, exception}` if there was
  an error.
  The returned `query` can then be passed to `execute/4` and/or `close/3`
  """
  def prepare(conn, query, opts \\ []) do
    opts = Keyword.put(opts, :prepare, true)
    DBConnection.prepare(conn, query, opts)
  end

  defdelegate execute(conn, query, params, opts \\ []), to: DBConnection
  defdelegate close(conn, query, opts \\ []), to: DBConnection
  defdelegate transaction(conn, fun, opts \\ []), to: DBConnection
  defdelegate rollback(conn, any), to: DBConnection

  defp default(opts), do: opts
end
