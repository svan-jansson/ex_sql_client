defmodule ExSqlClient do
  alias ExSqlClient.Query

  def child_spec(opts) do
    DBConnection.child_spec(ExSqlClient.Protocol, default(opts))
  end

  def start_link(opts \\ []) do
    DBConnection.start_link(ExSqlClient.Protocol, default(opts))
  end

  def query(conn, query, params \\ %{}, opts \\ []) do
    query = %Query{statement: query}
    response = DBConnection.prepare_execute(conn, query, params, opts)

    case response do
      {:ok, _query, result} -> {:ok, result}
      _ -> response
    end
  end

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
