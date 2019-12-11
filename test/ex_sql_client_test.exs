defmodule ExSqlClientTest do
  use ExUnit.Case
  doctest ExSqlClient

  @tag :integration
  test "can connect to server and execute a sql command", _context do
    connection_string =
      "Server=localhost; MultipleActiveResultSets=true; User Id=sa; Password=InsecurePassword123"

    assert ExSqlClient.connect(connection_string) == {:ok, 1}
    assert ExSqlClient.execute_scalar("SELECT 5") == {:ok, 5}
  end
end
