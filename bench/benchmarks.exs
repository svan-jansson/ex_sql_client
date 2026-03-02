# Run with: mix run bench/benchmarks.exs
#
# By default this script starts a SQL Server container via Testcontainers.
# Set MSSQL_CONNECTION_STRING to skip Testcontainers and use an existing server.
# Set MSSQL_IMAGE to change the SQL Server version (default: 2022-latest).

# ---------------------------------------------------------------------------
# Connection setup
# ---------------------------------------------------------------------------

connection_string =
  case System.get_env("MSSQL_CONNECTION_STRING") do
    nil ->
      # Auto-detect rootless Podman socket (common on Fedora / RHEL).
      unless System.get_env("DOCKER_HOST") do
        xdg = System.get_env("XDG_RUNTIME_DIR", "")
        podman_sock = Path.join(xdg, "podman/podman.sock")

        if xdg != "" and File.exists?(podman_sock) do
          System.put_env("DOCKER_HOST", "unix://#{podman_sock}")
        end
      end

      {:ok, _} = Application.ensure_all_started(:hackney)
      {:ok, _} = Testcontainers.start_link()

      image = System.get_env("MSSQL_IMAGE", "mcr.microsoft.com/mssql/server:2022-latest")
      IO.puts("Starting SQL Server container (#{image}) …")

      {:ok, container} =
        Testcontainers.Container.new(image)
        |> Testcontainers.Container.with_environment("SA_PASSWORD", "InsecurePassword123")
        |> Testcontainers.Container.with_environment("ACCEPT_EULA", "Y")
        |> Testcontainers.Container.with_exposed_port(1433)
        |> Testcontainers.Container.with_waiting_strategy(
          Testcontainers.LogWaitStrategy.new(~r/SQL Server is now ready/, 120_000)
        )
        |> Testcontainers.start_container()

      port = Testcontainers.Container.mapped_port(container, 1433)

      "Server=localhost,#{port}; MultipleActiveResultSets=true; User Id=sa; Password=InsecurePassword123; TrustServerCertificate=True"

    cs ->
      cs
  end

# Give SQL Server a moment to finish authentication setup after the log
# "ready" message fires — without this the pool workers hit a transient
# "Login failed" on their first connection attempt and must retry.
Process.sleep(2_000)

IO.puts("SQL Server ready. Starting benchmarks …\n")

# ---------------------------------------------------------------------------
# Connection pools
#
# bench_pool  – pool_size: 5 for general query benchmarks
# prep_pool   – pool_size: 1 so the prepared statement always lives on the
#               same .NET worker process and its statement_id stays valid
# ---------------------------------------------------------------------------

{:ok, bench_pool} =
  ExSqlClient.start_link(connection_string: connection_string, pool_size: 5)

{:ok, prep_pool} =
  ExSqlClient.start_link(connection_string: connection_string, pool_size: 1)

# Raw Netler client — starts the .NET binary but never calls Connect, so it
# never touches SQL Server.  Used to measure pure IPC overhead in isolation.
{:ok, raw_netler} = Netler.Client.start_link(:dotnet_sql_client)

# ---------------------------------------------------------------------------
# Schema setup
# ---------------------------------------------------------------------------

{:ok, _} =
  ExSqlClient.query(bench_pool, """
  CREATE TABLE bench_rows (
    id    INT           IDENTITY(1,1) PRIMARY KEY,
    label NVARCHAR(100) NOT NULL,
    value INT           NOT NULL
  )
  """)

IO.puts("Seeding 1 000 rows …")

for i <- 1..1_000 do
  {:ok, _} =
    ExSqlClient.query(
      bench_pool,
      "INSERT INTO bench_rows (label, value) VALUES (@label, @value)",
      %{"label" => "row-#{i}", "value" => i}
    )
end

IO.puts("Done seeding.\n")

# ---------------------------------------------------------------------------
# Prepared statement (reused across all iterations)
# Pinned to prep_pool (pool_size: 1) to keep the statement_id valid.
# ---------------------------------------------------------------------------

{:ok, prepared_select} =
  ExSqlClient.prepare(
    prep_pool,
    %ExSqlClient.Query{
      statement: "SELECT TOP 1 label, value FROM bench_rows WHERE id = @id"
    }
  )

# ---------------------------------------------------------------------------
# Benchmarks
# ---------------------------------------------------------------------------

Benchee.run(
  %{
    # Pure Netler IPC round-trip — no SQL Server involvement.
    # Subtract this from any query scenario to isolate the SQL Server + ADO.NET cost.
    "netler round-trip (no SQL)" => fn ->
      {:ok, true} = Netler.Client.invoke(raw_netler, "NoOp", [])
    end,
    "select constant" => fn ->
      {:ok, _} = ExSqlClient.query(bench_pool, "SELECT 1 AS n")
    end,
    "select 1 row" => fn ->
      {:ok, _} = ExSqlClient.query(bench_pool, "SELECT TOP 1 label, value FROM bench_rows")
    end,
    "select 1 row (parameterized)" => fn ->
      {:ok, _} =
        ExSqlClient.query(
          bench_pool,
          "SELECT TOP 1 label, value FROM bench_rows WHERE id = @id",
          %{"id" => :rand.uniform(1_000)}
        )
    end,
    "select 10 rows" => fn ->
      {:ok, _} = ExSqlClient.query(bench_pool, "SELECT TOP 10 label, value FROM bench_rows")
    end,
    "select 100 rows" => fn ->
      {:ok, _} = ExSqlClient.query(bench_pool, "SELECT TOP 100 label, value FROM bench_rows")
    end,
    "prepared statement (select)" => fn ->
      {:ok, _query, _rows} =
        ExSqlClient.execute(prep_pool, prepared_select, %{"id" => :rand.uniform(1_000)})
    end,
    "insert" => fn ->
      {:ok, _} =
        ExSqlClient.query(
          bench_pool,
          "INSERT INTO bench_rows (label, value) VALUES (@label, @value)",
          %{"label" => "bench", "value" => 0}
        )
    end,
    "transaction (insert + commit)" => fn ->
      {:ok, _} =
        ExSqlClient.transaction(bench_pool, fn tx ->
          ExSqlClient.query(
            tx,
            "INSERT INTO bench_rows (label, value) VALUES (@label, @value)",
            %{"label" => "bench", "value" => 0}
          )
        end)
    end
  },
  time: 10,
  warmup: 2,
  memory_time: 2
)

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

ExSqlClient.close(prep_pool, prepared_select)
{:ok, _} = ExSqlClient.query(bench_pool, "DROP TABLE bench_rows")
