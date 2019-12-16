defmodule ExSqlClientTest do
  use ExUnit.Case
  doctest ExSqlClient

  setup_all do
    connection_string =
      "Server=localhost; MultipleActiveResultSets=true; User Id=sa; Password=InsecurePassword123"

    {:ok, pid} = ExSqlClient.start_link()
    {:ok, true} = ExSqlClient.connect(pid, connection_string)
    {:ok, %{pid: pid}}
  end

  @tag :integration
  test "can select unnamed scalar", %{pid: pid} do
    assert ExSqlClient.execute(pid, "SELECT 5") == {:ok, [%{"0" => 5}]}
  end

  @tag :integration
  test "can select mix of named and unnamed scalars", %{pid: pid} do
    assert ExSqlClient.execute(pid, "SELECT 2, 'a string', 5 as 'five'") ==
             {:ok, [%{"0" => 2, "1" => "a string", "five" => 5}]}
  end

  @tag :integration
  test "can select named scalar", %{pid: pid} do
    assert ExSqlClient.execute(pid, "SELECT 5 as result") == {:ok, [%{"result" => 5}]}
  end

  @tag :integration
  test "can pass parameters to query", %{pid: pid} do
    assert ExSqlClient.execute(pid, "SELECT @param as result", %{param: 5}) ==
             {:ok, [%{"result" => 5}]}
  end

  @tag :integration
  test "can select datetime", %{pid: pid} do
    {:ok, [%{"0" => datetime}]} =
      ExSqlClient.execute(pid, "SELECT CONVERT(datetime, '1900-01-01 00:00:00', 104)")

    assert is_map(datetime)
  end

  @tag :integration
  test "can select UUID", %{pid: pid} do
    {:ok, [%{"0" => uuid}]} = ExSqlClient.execute(pid, "SELECT NEWID()")
    assert String.length(uuid) == 36
  end

  @tag :integration
  test "can select multiple result sets", %{pid: pid} do
    assert ExSqlClient.execute(pid, "SELECT 1 as first_result_set; SELECT 1 as second_result_set") ==
             {:ok, [%{"first_result_set" => 1}, %{"second_result_set" => 1}]}
  end
end
