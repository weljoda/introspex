defmodule Introspex.AshDomainBuilder do
  @moduledoc """
  Generates Ash Domain modules that register Ash resources.

  An Ash Domain is a first-class boundary module in Ash 3.x that owns a set of
  resources and exposes them to the rest of the application. It replaces the role
  that a Phoenix context plays in Ecto-based apps, though it is more structured.

  ## Generated domain structure

      defmodule MyApp.Accounts do
        use Ash.Domain

        resources do
          resource MyApp.Accounts.User
          resource MyApp.Accounts.Profile
        end
      end
  """

  @doc """
  Builds an Ash Domain module that registers the given resources.

  ## Parameters

    * `domain_name` - The domain module name segment, e.g. `"Accounts"`
    * `schemas` - List of schema info maps, each with:
      * `:module_name` - The resource module name (last segment only), e.g. `"User"`
    * `opts` - Keyword list:
      * `:app_name` - The application module prefix, e.g. `"MyApp"`
      * `:path` - Optional path segments to include in the module name

  Returns a string containing the complete domain module code.
  """
  def build_domain(domain_name, schemas, opts) do
    app_name = Keyword.get(opts, :app_name)
    path = Keyword.get(opts, :path)

    base_parts = [app_name]

    base_parts =
      if path do
        path_parts = path |> String.split("/", trim: true) |> Enum.map(&Macro.camelize/1)
        base_parts ++ path_parts
      else
        base_parts
      end

    full_module_parts = base_parts ++ [domain_name]
    full_module_name = Enum.join(full_module_parts, ".")

    resource_lines =
      schemas
      |> Enum.map(fn schema ->
        "    resource #{full_module_name}.#{schema.module_name}"
      end)
      |> Enum.join("\n")

    """
    defmodule #{full_module_name} do
      use Ash.Domain

      resources do
    #{resource_lines}
      end
    end
    """
  end
end
