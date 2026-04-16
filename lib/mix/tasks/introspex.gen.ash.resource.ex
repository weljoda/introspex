defmodule Mix.Tasks.Introspex.Gen.Ash.Resource do
  @shortdoc "Generates Ash 3.x resources from an existing PostgreSQL database"
  @moduledoc """
  Generates Ash 3.x resource files from an existing PostgreSQL database.

  This task introspects your PostgreSQL database and generates Ash resource files
  with proper attribute types, relationships, actions, and identities.

  Before running, ensure your project has the required dependencies:

      # mix.exs
      {:ash, "~> 3.0"},
      {:ash_postgres, "~> 2.0"},

  ## Examples

      $ mix introspex.gen.ash.resource --repo MyApp.Repo
      $ mix introspex.gen.ash.resource --repo MyApp.Repo --domain Core
      $ mix introspex.gen.ash.resource --repo MyApp.Repo --domain Accounts --context-tables users,profiles
      $ mix introspex.gen.ash.resource --repo MyApp.Repo --binary-id --dry-run
      $ mix introspex.gen.ash.resource --repo MyApp.Repo --table users --domain Accounts

  ## Options

    * `--repo` - the repository module (required)
    * `--schema` - PostgreSQL schema name (default: "public")
    * `--table` - generate resource for a specific table only
    * `--exclude-views` - skip generating resources for views and materialized views
    * `--binary-id` - use UUID primary keys (auto-detected from column type)
    * `--no-timestamps` - do not generate `timestamps()` in resources
    * `--no-associations` - skip detecting and generating relationships
    * `--module-prefix` - prefix for generated module names (default: app name)
    * `--output-dir` - output directory for resource files (default: lib/app_name)
    * `--dry-run` - preview what would be generated without writing files
    * `--domain` - Ash Domain module name (e.g. "Core"); all tables are scoped under this domain.
      Use `--context-tables` to limit which tables are included.
    * `--context` - alias for `--domain` for compatibility with Ecto task conventions
    * `--context-tables` - comma-separated list of tables to include in the domain (optional;
      omit to include all tables)
    * `--path` - custom path segment(s) to insert in the output directory
    * `--association-naming` - naming strategy: fk_stem, table_plus_stem, constraint (default: table_plus_stem)
    * `--association-naming-apply` - when to apply: duplicates_only, always (default: duplicates_only)
    * `--singularize` - singularize module names to match Elixir conventions (default: true; use `--no-singularize` to keep plural names)

  ## Association Naming

  See `mix ecto.gen.schema` documentation for full details. The same strategies
  and apply modes are supported.

  ## Generated file layout

  `--domain Core` (no `--context-tables` — all tables under one domain):

      lib/my_app/core/user.ex
      lib/my_app/core/post.ex
      lib/my_app/core/...              ← one file per table
      lib/my_app/core.ex               ← Ash Domain module listing all resources

  `--domain Accounts --context-tables users,profiles` (scoped domain):

      lib/my_app/accounts/user.ex
      lib/my_app/accounts/profile.ex
      lib/my_app/accounts.ex           ← Ash Domain module

  ## many_to_many and join tables

  Ash requires `many_to_many` relationships to reference a full resource module as
  `through:`. Ensure that any join tables are also generated as Ash resources (they
  are included automatically unless filtered with `--context-tables`).
  """

  use Mix.Task

  alias Introspex.Postgres.{Introspector, RelationshipAnalyzer}
  alias Introspex.{AshResourceBuilder, AshDomainBuilder}

  @switches [
    repo: :string,
    schema: :string,
    table: :string,
    exclude_views: :boolean,
    binary_id: :boolean,
    no_timestamps: :boolean,
    no_associations: :boolean,
    module_prefix: :string,
    output_dir: :string,
    dry_run: :boolean,
    domain: :string,
    context: :string,
    context_tables: :string,
    path: :string,
    association_naming: :string,
    association_naming_apply: :string,
    singularize: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _} = OptionParser.parse!(args, switches: @switches)
    validate_association_naming_opts!(opts)

    repo = get_repo!(opts)
    ensure_repo_started!(repo)

    schema = Keyword.get(opts, :schema, "public")
    specific_table = Keyword.get(opts, :table)
    exclude_views = Keyword.get(opts, :exclude_views, false)
    dry_run = Keyword.get(opts, :dry_run, false)

    Mix.shell().info("Introspecting PostgreSQL database...")

    tables =
      case Introspector.list_tables(repo, schema, exclude_views) do
        {:error, error} ->
          Mix.raise("Failed to list tables: #{inspect(error)}")

        tables when specific_table != nil ->
          Enum.filter(tables, &(&1.name == specific_table))

        tables ->
          context_tables = parse_context_tables(opts)

          if context_tables != [] do
            Enum.filter(tables, &(&1.name in context_tables))
          else
            tables
          end
      end

    if Enum.empty?(tables) do
      Mix.shell().info("No tables found to generate resources for.")
    else
      Mix.shell().info("Found #{length(tables)} table(s) to process.")

      results =
        Enum.map(tables, fn table_info ->
          generate_resource_for_table(repo, table_info, tables, schema, opts, dry_run)
        end)

      resource_schemas = Enum.map(results, &elem(&1, 0))
      resource_paths = results |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1)

      domain = resolve_domain(opts)

      domain_path =
        if domain && !dry_run do
          generate_domain_module(opts, resource_schemas)
        end

      if dry_run do
        Mix.shell().info("\nDry run complete. No files were written.")
      else
        all_paths = resource_paths ++ List.wrap(domain_path)
        Mix.Task.run("format", all_paths)

        app_atom = get_app_name(opts) |> Macro.underscore()

        completion_message =
          if domain do
            domain_module = build_domain_module_name(domain, opts)

            """

            Resource generation complete!

            Add the generated domain to your config/config.exs:
                config :#{app_atom}, ash_domains: [#{domain_module}]
            """
          else
            "\nResource generation complete!"
          end

        Mix.shell().info(completion_message)
      end
    end
  end

  defp generate_resource_for_table(repo, table_info, all_tables, db_schema, opts, dry_run) do
    Mix.shell().info("\nProcessing #{table_info.type}: #{table_info.name}")

    domain = resolve_domain(opts)

    table_opts =
      if should_include_in_domain?(table_info.name, opts) do
        opts
      else
        Keyword.drop(opts, [:domain, :context])
      end

    columns = Introspector.get_columns(repo, table_info.name, db_schema)
    primary_keys = Introspector.get_primary_keys(repo, table_info.name, db_schema)

    relationships =
      if Keyword.get(opts, :no_associations, false) or table_info.type != :table do
        %{belongs_to: [], has_many: [], has_one: [], many_to_many: []}
      else
        RelationshipAnalyzer.analyze_relationships(repo, table_info.name, all_tables, db_schema)
      end

    unique_constraints =
      if table_info.type == :table do
        Introspector.get_unique_constraints(repo, table_info.name, db_schema)
      else
        []
      end

    check_constraints =
      if table_info.type == :table do
        Introspector.get_check_constraints(repo, table_info.name, db_schema)
      else
        []
      end

    module_name = build_module_name(table_info.name, table_opts)

    table_data = %{
      table: table_info,
      columns: columns,
      primary_keys: primary_keys,
      relationships: relationships,
      unique_constraints: unique_constraints,
      check_constraints: check_constraints,
      table_type: table_info.type
    }

    module_prefix =
      module_name
      |> String.split(".")
      |> List.delete_at(-1)
      |> Enum.join(".")

    # Derive the domain module full name for the resource's `domain:` option
    domain_module =
      if should_include_in_domain?(table_info.name, opts) do
        build_domain_module_name(domain, opts)
      else
        nil
      end

    builder_opts = [
      binary_id: Keyword.get(opts, :binary_id, false),
      skip_timestamps: Keyword.get(opts, :no_timestamps, false),
      no_associations: Keyword.get(opts, :no_associations, false),
      module_prefix: module_prefix,
      repo_module: Keyword.get(opts, :repo) |> to_string(),
      domain_module: domain_module,
      association_naming: Keyword.get(opts, :association_naming, "table_plus_stem"),
      association_naming_apply: Keyword.get(opts, :association_naming_apply, "duplicates_only"),
      singularize: Keyword.get(opts, :singularize, true)
    ]

    resource_content = AshResourceBuilder.build_resource(table_data, module_name, builder_opts)

    file_path =
      if dry_run do
        Mix.shell().info("\n--- #{module_name} ---")
        Mix.shell().info(resource_content)
        nil
      else
        write_resource_file(module_name, resource_content, table_opts)
      end

    schema_info = %{
      module_name: String.split(module_name, ".") |> List.last(),
      singular_name: singularize(table_info.name),
      plural_name: Macro.underscore(table_info.name),
      table_name: table_info.name,
      table_type: table_info.type
    }

    {schema_info, file_path}
  end

  defp get_repo!(opts) do
    case Keyword.get(opts, :repo) do
      nil ->
        Mix.raise("--repo option is required. Example: --repo MyApp.Repo")

      repo_string ->
        Module.concat([repo_string])
    end
  end

  defp validate_association_naming_opts!(opts) do
    association_naming = Keyword.get(opts, :association_naming, "table_plus_stem")
    association_naming_apply = Keyword.get(opts, :association_naming_apply, "duplicates_only")

    allowed_naming = ["fk_stem", "table_plus_stem", "constraint"]
    allowed_apply = ["duplicates_only", "always"]

    unless association_naming in allowed_naming do
      Mix.raise(
        "Invalid --association-naming value: #{association_naming}. " <>
          "Allowed values: #{Enum.join(allowed_naming, ", ")}"
      )
    end

    unless association_naming_apply in allowed_apply do
      Mix.raise(
        "Invalid --association-naming-apply value: #{association_naming_apply}. " <>
          "Allowed values: #{Enum.join(allowed_apply, ", ")}"
      )
    end
  end

  defp ensure_repo_started!(repo) do
    case Code.ensure_compiled(repo) do
      {:module, _} ->
        if function_exported?(repo, :__adapter__, 0) do
          {:ok, _} = Application.ensure_all_started(:postgrex)

          case repo.start_link() do
            {:ok, _} -> :ok
            {:error, {:already_started, _}} -> :ok
            {:error, error} -> Mix.raise("Failed to start repo: #{inspect(error)}")
          end
        else
          Mix.raise("#{inspect(repo)} is not an Ecto.Repo")
        end

      {:error, error} ->
        Mix.raise("Could not load #{inspect(repo)}: #{inspect(error)}")
    end
  end

  defp build_module_name(table_name, opts) do
    prefix = Keyword.get(opts, :module_prefix, get_app_name(opts))
    domain = resolve_domain(opts)
    base_parts = [prefix] ++ camelize_path_parts(opts)

    module_parts =
      if should_include_in_domain?(table_name, opts) do
        base_parts ++ [domain, camelize_table(table_name, opts)]
      else
        base_parts ++ [camelize_table(table_name, opts)]
      end

    Enum.join(module_parts, ".")
  end

  defp build_domain_module_name(domain, opts) do
    base_parts = [get_app_name(opts)] ++ camelize_path_parts(opts)
    Enum.join(base_parts ++ [domain], ".")
  end

  defp camelize_path_parts(opts) do
    case Keyword.get(opts, :path) do
      nil -> []
      path -> path |> String.split("/", trim: true) |> Enum.map(&Macro.camelize/1)
    end
  end

  defp get_app_name(opts) do
    Keyword.get(opts, :module_prefix) ||
      Mix.Project.config()[:app]
      |> to_string()
      |> Macro.camelize()
  end

  # Support both --domain and --context for symmetry with mix ecto.gen.schema
  defp resolve_domain(opts) do
    Keyword.get(opts, :domain) || Keyword.get(opts, :context)
  end

  defp parse_context_tables(opts) do
    case Keyword.get(opts, :context_tables) do
      nil ->
        []

      tables_string ->
        tables_string
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
    end
  end

  defp should_include_in_domain?(table_name, opts) do
    domain = resolve_domain(opts)
    context_tables = parse_context_tables(opts)

    domain != nil && (context_tables == [] || table_name in context_tables)
  end

  defp write_resource_file(module_name, content, opts) do
    app_name = get_app_name(opts) |> Macro.underscore()
    output_dir = Keyword.get(opts, :output_dir, "lib/#{app_name}")

    module_parts = String.split(module_name, ".")
    [_app_prefix | relative_parts] = module_parts
    relative_path_parts = Enum.map(relative_parts, &Macro.underscore/1)
    file_name = List.last(relative_path_parts)
    directory_parts = List.delete_at(relative_path_parts, -1)

    file_path = Path.join([output_dir] ++ directory_parts ++ ["#{file_name}.ex"])

    File.mkdir_p!(Path.dirname(file_path))
    File.write!(file_path, content)
    Mix.shell().info("Created #{file_path}")
    file_path
  end

  defp generate_domain_module(opts, schemas) do
    domain = resolve_domain(opts)

    if domain do
      schemas = Enum.reject(schemas, &is_nil/1)

      domain_content =
        AshDomainBuilder.build_domain(
          domain,
          schemas,
          app_name: get_app_name(opts),
          path: Keyword.get(opts, :path)
        )

      app_name = get_app_name(opts) |> Macro.underscore()
      output_dir = Keyword.get(opts, :output_dir, "lib/#{app_name}")
      custom_path = Keyword.get(opts, :path)

      path_parts =
        [output_dir] ++
          if custom_path, do: String.split(custom_path, "/", trim: true), else: []

      domain_file_path = Path.join(path_parts ++ ["#{Macro.underscore(domain)}.ex"])

      File.mkdir_p!(Path.dirname(domain_file_path))
      File.write!(domain_file_path, domain_content)
      Mix.shell().info("Created #{domain_file_path}")
      domain_file_path
    end
  end

  defp singularize(table_name) do
    table_name |> Macro.underscore() |> Inflex.singularize()
  end

  defp camelize_table(table_name, opts) do
    name =
      if Keyword.get(opts, :singularize, true),
        do: Inflex.singularize(table_name),
        else: table_name

    Macro.camelize(name)
  end
end
