defmodule ExSqlClient.DotnetSqlClient do
  use Netler, dotnet_project: :dotnet_sql_client

  def connect(connection_string), do: invoke("Connect", [connection_string])
  def execute(command, parameters), do: invoke("Execute", [command, parameters])
end
