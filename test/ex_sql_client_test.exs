defmodule ExSqlClientTest do
  use ExUnit.Case
  doctest ExSqlClient

  test "greets the world" do
    assert ExSqlClient.hello() == :world
  end
end
