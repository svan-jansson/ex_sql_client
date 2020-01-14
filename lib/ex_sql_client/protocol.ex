defmodule ExSqlClient.Protocol do
  @moduledoc false

  use DBConnection

  require Logger

  alias Netler.Client

  defstruct client: nil, checked_out: false, status: :idle, transaction_id: nil

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
  def handle_execute(query, params, _opts, state = %{status: :transaction}) do
    case Client.invoke(state.client, "ExecuteInTransaction", [
           query.statement,
           params,
           state.transaction_id
         ]) do
      {:ok, result} -> {:ok, query, result, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  @impl true
  def handle_execute(query, params, _opts, state) do
    case Client.invoke(state.client, "Execute", [query.statement, params]) do
      {:ok, result} -> {:ok, query, result, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  @impl true
  def handle_begin(_opts, state = %{status: :idle}) do
    case Client.invoke(state.client, "BeginTransaction", []) do
      {:ok, transaction_id} ->
        {:ok, :began, %{state | status: :transaction, transaction_id: transaction_id}}

      {:error, reason} ->
        {:disconnect, reason, state}
    end
  end

  @impl true
  def handle_rollback(_opts, state = %{status: :transaction}) do
    case Client.invoke(state.client, "RollbackTransaction", [state.transaction_id]) do
      {:ok, true} ->
        {:ok, :rolledback, %{state | status: :idle, transaction_id: nil}}

      {:error, reason} ->
        {:disconnect, reason, state}
    end
  end

  @impl true
  def handle_commit(_opts, state = %{status: :transaction}) do
    case Client.invoke(state.client, "CommitTransaction", [state.transaction_id]) do
      {:ok, true} ->
        {:ok, :committed, %{state | status: :idle, transaction_id: nil}}

      {:error, reason} ->
        {:disconnect, reason, state}
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
  def handle_close(_query, _opts, _state) do
    Logger.error("handle_close not implemented")
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
  def handle_status(_opts, _state) do
    Logger.error("handle_status not implemented")
    :not_implemented
  end
end
