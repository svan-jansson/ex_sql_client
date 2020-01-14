defmodule PreparedStatementTest do
  use ExUnit.Case

  setup_all do
    connection_string =
      "Server=localhost; MultipleActiveResultSets=true; User Id=sa; Password=InsecurePassword123"

    {:ok, conn} = ExSqlClient.start_link(connection_string: connection_string)
    {:ok, %{conn: conn}}
  end

  @tag :integration
  test "can prepare and execute a statement", %{conn: conn} do
    query = %ExSqlClient.Query{statement: "SELECT * FROM [sys].[objects] WHERE [type] = @type"}
    {:ok, query} = ExSqlClient.prepare(conn, query)
    {:ok, result} = ExSqlClient.execute(conn, query, %{type: "P"})
    assert Enum.count(result) > 0
  end
end
