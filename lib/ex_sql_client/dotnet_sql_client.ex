defmodule ExSqlClient.DotnetSqlClient do
  use Netler, dotnet_project: :dotnet_sql_client

  def add(a, b), do: invoke("Add", [a, b])
end
