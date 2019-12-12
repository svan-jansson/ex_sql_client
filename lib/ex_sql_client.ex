defmodule ExSqlClient do
  alias ExSqlClient.DotnetSqlClient

  def connect(connection_string), do: DotnetSqlClient.connect(connection_string)
  def execute(command), do: DotnetSqlClient.execute(command, %{})
  def execute(command, parameters), do: DotnetSqlClient.execute(command, parameters)
end
