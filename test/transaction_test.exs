defmodule TransactionTest do
  use ExUnit.Case

  setup_all do
    connection_string =
      "Server=localhost; MultipleActiveResultSets=true; User Id=sa; Password=InsecurePassword123"

    {:ok, conn} = ExSqlClient.start_link(connection_string: connection_string)
    {:ok, %{conn: conn}}
  end

  @tag :integration2
  test "can execute a query in a transaction", %{conn: conn} do
    ExSqlClient.transaction(conn, fn transaction ->
      assert ExSqlClient.query(transaction, "SELECT 5") == {:ok, [%{"0" => 5}]}
    end)
  end
end
