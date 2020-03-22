defmodule ExSqlClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_sql_client,
      name: "ExSqlClient",
      source_url: "https://github.com/svan-jansson/ex_sql_client",
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
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
      {:db_connection, "~> 2.2"},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:credo, "~> 1.1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    Microsoft SQL Server Driver for Elixir
    """
  end

  defp package do
    [
      maintainers: ["Svan Jansson"],
      licenses: ["MIT"],
      links: %{Github: "https://github.com/svan-jansson/ex_sql_client"},
      files: ~w(lib dotnet .formatter.exs mix.exs README* LICENSE*)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      logo: "logo/ex_sql_client.svg.png"
    ]
  end
end
