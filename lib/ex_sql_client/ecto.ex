defmodule ExSqlClient.Ecto do
  @moduledoc """
  Ecto 3 adapter for ExSqlClient (Microsoft SQL Server).

  This adapter implements `Ecto.Adapters.SQL` on top of the existing
  `ExSqlClient.Protocol` / `DBConnection` stack.

  ## Usage

      defmodule MyApp.Repo do
        use Ecto.Repo,
          otp_app: :my_app,
          adapter: ExSqlClient.Ecto
      end

  ## Configuration

  Pass the same connection options as `ExSqlClient.start_link/1`:

      config :my_app, MyApp.Repo,
        connection_string: "Server=localhost,1433;Database=mydb;User Id=sa;Password=secret;TrustServerCertificate=True"

  ## Known Limitations

  * **`Repo.stream/2`** — raises at runtime; cursors are not supported by the
    underlying protocol.
  * **`query_many/4`** — raises at runtime; multiple result sets are not
    supported.
  * **Migrations** — not supported; use `ExSqlClient.query/4` for DDL.
  * **`on_conflict`** — only `:raise` is supported.
  * **Window functions** — not supported.
  """

  use Ecto.Adapters.SQL, driver: :ex_sql_client

  @impl Ecto.Adapter
  def ensure_all_started(_config, type) do
    # The default implementation tries to start :ex_sql_client as an OTP
    # application which would attempt to launch the .NET process before any
    # connection options are known.  We start only the runtime deps instead.
    with {:ok, _} <- Application.ensure_all_started(:netler, type) do
      Application.ensure_all_started(:db_connection, type)
    end
  end

  @impl Ecto.Adapter
  def loaders(:boolean, type), do: [&bool_decode/1, type]
  def loaders(:binary_id, type), do: [Ecto.UUID, type]
  def loaders(_, type), do: [type]

  @impl Ecto.Adapter
  def dumpers(:boolean, type), do: [type, &bool_encode/1]
  def dumpers(:binary_id, type), do: [type, Ecto.UUID]
  def dumpers(_, type), do: [type]

  @impl Ecto.Adapter.Schema
  def autogenerate(:binary_id), do: Ecto.UUID.generate()
  def autogenerate(:embed_id), do: Ecto.UUID.generate()
  def autogenerate(type), do: super(type)

  @impl Ecto.Adapter.Migration
  def supports_ddl_transaction?, do: false

  @impl Ecto.Adapter.Migration
  def lock_for_migrations(_meta, _opts, fun), do: fun.()

  # MSSQL BIT column is stored as 0/1 integer; map back to Elixir boolean.
  defp bool_decode(0), do: {:ok, false}
  defp bool_decode(1), do: {:ok, true}
  defp bool_decode(v) when is_boolean(v), do: {:ok, v}

  defp bool_encode(false), do: {:ok, 0}
  defp bool_encode(true), do: {:ok, 1}
end
