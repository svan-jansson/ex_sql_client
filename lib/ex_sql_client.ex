defmodule ExSqlClient do
  alias ExSqlClient.DotnetSqlClient

  def connect(connection_string), do: DotnetSqlClient.connect(connection_string)
  def execute_scalar(command), do: DotnetSqlClient.execute_scalar(command)
end
