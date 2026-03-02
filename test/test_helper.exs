ExUnit.start()

# Testcontainers defaults to /var/run/docker.sock. Under rootless Podman
# (common on Fedora/RHEL) the live socket is at $XDG_RUNTIME_DIR/podman/podman.sock.
# Auto-point DOCKER_HOST there when the variable is unset and the socket exists.
unless System.get_env("DOCKER_HOST") do
  xdg = System.get_env("XDG_RUNTIME_DIR", "")
  podman_sock = Path.join(xdg, "podman/podman.sock")

  if xdg != "" and File.exists?(podman_sock) do
    System.put_env("DOCKER_HOST", "unix://#{podman_sock}")
  end
end

{:ok, _} = Application.ensure_all_started(:hackney)
{:ok, _} = Testcontainers.start_link()

mssql_image =
  System.get_env("MSSQL_IMAGE", "mcr.microsoft.com/mssql/server:2025-latest")

{:ok, container} =
  Testcontainers.Container.new(mssql_image)
  |> Testcontainers.Container.with_environment("SA_PASSWORD", "InsecurePassword123")
  |> Testcontainers.Container.with_environment("ACCEPT_EULA", "Y")
  |> Testcontainers.Container.with_exposed_port(1433)
  |> Testcontainers.Container.with_waiting_strategy(
    Testcontainers.LogWaitStrategy.new(~r/SQL Server is now ready/, 120_000)
  )
  |> Testcontainers.start_container()

port = Testcontainers.Container.mapped_port(container, 1433)

connection_string =
  "Server=localhost,#{port}; MultipleActiveResultSets=true; User Id=sa; Password=InsecurePassword123; TrustServerCertificate=True"

Application.put_env(:ex_sql_client, :test_connection_string, connection_string)
