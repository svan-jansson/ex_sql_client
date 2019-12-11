defmodule ExSqlClient.DotnetSqlClient do
  use Netler, dotnet_project: :dotnet_sql_client

  def connect(connection_string), do: invoke("Connect", [connection_string])
  def execute_scalar(command), do: invoke("ExecuteScalar", [command])
end
