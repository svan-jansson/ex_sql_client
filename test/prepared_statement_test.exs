defmodule PreparedStatementTest do
  use ExUnit.Case

  setup_all do
    connection_string = Application.fetch_env!(:ex_sql_client, :test_connection_string)
    {:ok, conn} = ExSqlClient.start_link(connection_string: connection_string)
    {:ok, %{conn: conn}}
  end

  @tag :integration
  test "can prepare and execute a statement", %{conn: conn} do
    query = %ExSqlClient.Query{
      statement: "SELECT [name] FROM [sys].[objects] WHERE [type] = @type"
    }

    {:ok, query} = ExSqlClient.prepare(conn, query)
    {:ok, _query, result} = ExSqlClient.execute(conn, query, %{type: "P"})
    assert !Enum.empty?(result)

    {:ok, _query, result} = ExSqlClient.execute(conn, query, %{type: "U"})

    {:ok, :closed} = ExSqlClient.close(conn, query)
    assert !Enum.empty?(result)
  end

  @tag :integration
  test "fails when executing a prepared statement after it is closed", %{conn: conn} do
    query = %ExSqlClient.Query{
      statement: "SELECT [name] FROM [sys].[objects] WHERE [type] = @type"
    }

    {:ok, query} = ExSqlClient.prepare(conn, query)
    {:ok, _query, result} = ExSqlClient.execute(conn, query, %{type: "P"})
    assert !Enum.empty?(result)
    {:ok, :closed} = ExSqlClient.close(conn, query)

    {atom, _reason} = ExSqlClient.execute(conn, query, %{type: "U"})
    assert atom == :error
  end
end
