defmodule ExSqlClient do
  alias ExSqlClient.DotnetSqlClient

  def start_link(_opts \\ []) do
    Netler.Client.start_link(:dotnet_sql_client)
  end

  def connect(pid, connection_string),
    do: Netler.Client.invoke(pid, "Connect", [connection_string])

  def execute(pid, command, parameters \\ %{}),
    do: Netler.Client.invoke(pid, "Execute", [command, parameters])
end
