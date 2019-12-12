defmodule ExSqlClientTest do
  use ExUnit.Case
  doctest ExSqlClient

  setup do
    connection_string =
      "Server=localhost; MultipleActiveResultSets=true; User Id=sa; Password=InsecurePassword123"

    {:ok, true} = ExSqlClient.connect(connection_string)
    {:ok, %{connected: true}}
  end

  @tag :integration
  test "can select unnamed scalar", _context do
    assert ExSqlClient.execute("SELECT 5") == {:ok, [%{"" => 5}]}
  end

  @tag :integration
  test "can select named scalar", _context do
    assert ExSqlClient.execute("SELECT 5 as result") == {:ok, [%{"result" => 5}]}
  end

  @tag :integration
  test "can pass parameters to query", _context do
    assert ExSqlClient.execute("SELECT @param as result", %{param: 5}) ==
             {:ok, [%{"result" => 5}]}
  end
end
