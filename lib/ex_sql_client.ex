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

  defp default(opts), do: opts
end
