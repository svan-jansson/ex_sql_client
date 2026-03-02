defmodule Mix.Tasks.Compile.DotnetBuild do
  @moduledoc """
  Replacement for the netler `:netler` compiler task.

  `Netler.Compiler.Dotnet.compile_project/1` returns `{io_stream, exit_code}`,
  but the upstream `Mix.Tasks.Compile.Netler` checks for `:ok`, so it always
  returns `{:error, []}` regardless of whether the build succeeded (netler
  0.4.74 regression). This task performs the same steps but evaluates success
  via the integer exit code instead.
  """

  use Mix.Task.Compiler

  alias Netler.Compiler.Dotnet

  @impl Mix.Task.Compiler
  def run(_args) do
    config = Mix.Project.config()
    dotnet_projects = Keyword.get(config, :dotnet_projects, [])

    if dotnet_projects == [] do
      {:noop, []}
    else
      File.mkdir_p!("priv")

      ok? =
        dotnet_projects
        |> Enum.map(fn
          {project, _opts} -> Atom.to_string(project)
          project -> Atom.to_string(project)
        end)
        |> Enum.all?(fn project_name ->
          {_, exit_code} = Dotnet.compile_project(project_name)
          exit_code == 0
        end)

      Mix.Utils.symlink_or_copy(
        Path.expand("priv"),
        Path.join(Mix.Project.app_path(config), "priv")
      )

      if ok?, do: {:ok, []}, else: {:error, []}
    end
  end
end
