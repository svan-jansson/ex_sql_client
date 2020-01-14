defmodule TransactionTest do
  use ExUnit.Case

  setup_all do
    connection_string =
      "Server=localhost; MultipleActiveResultSets=true; User Id=sa; Password=InsecurePassword123"

    {:ok, conn} = ExSqlClient.start_link(connection_string: connection_string)
    {:ok, %{conn: conn}}
  end

  @tag :integration
  test "can execute a query in a transaction", %{conn: conn} do
    assert ExSqlClient.transaction(conn, fn transaction ->
             assert ExSqlClient.query(transaction, "SELECT 5") == {:ok, [%{"0" => 5}]}
             :completed
           end) == {:ok, :completed}
  end

  @tag :integration
  test "can rollback a transaction", %{conn: conn} do
    assert ExSqlClient.transaction(conn, fn transaction ->
             assert ExSqlClient.query(transaction, "SELECT 5") == {:ok, [%{"0" => 5}]}
             ExSqlClient.rollback(transaction, :oops)
           end) == {:error, :oops}
  end
end
