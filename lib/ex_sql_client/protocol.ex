defmodule ExSqlClient.Protocol do
  @moduledoc false

  use DBConnection

  require Logger

  alias Netler.Client

  defstruct client: nil, checked_out: false

  @impl true
  def connect(opts) do
    connection_string = Keyword.get(opts, :connection_string)
    {:ok, client} = Client.start_link(dotnet_project: :dotnet_sql_client)
    {:ok, true} = Client.invoke(client, "Connect", [connection_string])
    {:ok, %__MODULE__{client: client}}
  end

  @impl true
  def ping(state) do
    {:ok, [%{"0" => "pong"}]} = Client.invoke(state.client, "Execute", ["SELECT 'pong'", %{}])
    {:ok, state}
  end

  @impl true
  def handle_prepare(query, _opts, state) do
    {:ok, query, state}
  end

  @impl true
  def handle_execute(query, params, _opts, state) do
    case Client.invoke(state.client, "Execute", [query.statement, params]) do
      {:ok, result} -> {:ok, query, result, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  @impl true
  def checkin(_state) do
    Logger.error("checkin not implemented")
    :not_implemented
  end

  @impl true
  def checkout(state) do
    state = %{state | checked_out: true}
    {:ok, state}
  end

  @impl true
  def disconnect(_err, _state) do
    Logger.error("disconnect not implemented")
    :not_implemented
  end

  @impl true
  def handle_begin(_opts, _state) do
    Logger.error("handle_begin not implemented")
    :not_implemented
  end

  @impl true
  def handle_close(_query, _opts, _state) do
    Logger.error("handle_close not implemented")
    :not_implemented
  end

  @impl true
  def handle_commit(_opts, _state) do
    Logger.error("handle_commit not implemented")
    :not_implemented
  end

  @impl true
  def handle_deallocate(_query, _cursor, _opts, _state) do
    Logger.error("handle_deallocate not implemented")
    :not_implemented
  end

  @impl true
  def handle_declare(_query, _params, _opts, _state) do
    Logger.error("handle_declare not implemented")
    :not_implemented
  end

  @impl true
  def handle_fetch(_query, _cursor, _opts, _state) do
    Logger.error("handle_fetch not implemented")
    :not_implemented
  end

  @impl true
  def handle_rollback(_opts, _state) do
    Logger.error("handle_rollback not implemented")
    :not_implemented
  end

  @impl true
  def handle_status(_opts, _state) do
    Logger.error("handle_status not implemented")
    :not_implemented
  end
end
