defmodule ExSqlClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_sql_client,
      version: "0.2.1",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: Mix.compilers() ++ [:netler],
      dotnet_projects: [
        {:dotnet_sql_client, autostart: false}
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:netler, "~> 0.3"},
      {:db_connection, "~> 2.2"}
    ]
  end
end
