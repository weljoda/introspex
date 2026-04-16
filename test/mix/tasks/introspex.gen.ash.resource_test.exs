defmodule Mix.Tasks.Introspex.Gen.Ash.ResourceTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Introspex.Gen.Ash.Resource

  defmodule TestRepo do
    def __adapter__, do: Ecto.Adapters.Postgres

    def config, do: [database: "test_db", username: "postgres", password: "postgres"]

    def start_link(_opts \\ []) do
      {:error, {:already_started, self()}}
    end

    def query(_query, _params) do
      {:error, %{message: "Could not query database"}}
    end
  end

  defmodule NotARepo do
    # This module doesn't implement __adapter__
  end

  describe "run/1" do
    test "handles when repo is already started" do
      assert_raise Mix.Error, ~r/Could not query database/, fn ->
        Resource.run(["--repo", "Mix.Tasks.Introspex.Gen.Ash.ResourceTest.TestRepo", "--dry-run"])
      end
    end

    test "raises error when module is not a repo" do
      assert_raise Mix.Error, ~r/is not an Ecto.Repo/, fn ->
        Resource.run(["--repo", "Mix.Tasks.Introspex.Gen.Ash.ResourceTest.NotARepo"])
      end
    end

    test "raises error when repo module doesn't exist" do
      assert_raise Mix.Error, ~r/Could not load/, fn ->
        Resource.run(["--repo", "NonExistent.Repo"])
      end
    end

    test "raises error when --repo is not provided" do
      assert_raise Mix.Error, ~r/--repo option is required/, fn ->
        Resource.run([])
      end
    end

    test "raises error when --repo is missing but other options are given" do
      assert_raise Mix.Error, ~r/--repo option is required/, fn ->
        Resource.run(["--table", "users"])
      end
    end

    test "raises error for invalid association naming strategy" do
      assert_raise Mix.Error, ~r/Invalid --association-naming value/, fn ->
        Resource.run([
          "--repo",
          "Mix.Tasks.Introspex.Gen.Ash.ResourceTest.TestRepo",
          "--association-naming",
          "invalid"
        ])
      end
    end

    test "raises error for invalid association naming apply mode" do
      assert_raise Mix.Error, ~r/Invalid --association-naming-apply value/, fn ->
        Resource.run([
          "--repo",
          "Mix.Tasks.Introspex.Gen.Ash.ResourceTest.TestRepo",
          "--association-naming-apply",
          "invalid"
        ])
      end
    end
  end

  describe "parse_opts/1" do
    test "parses all available options" do
      args = [
        "--repo",
        "MyApp.Repo",
        "--schema",
        "custom_schema",
        "--table",
        "users",
        "--exclude-views",
        "--binary-id",
        "--no-timestamps",
        "--no-associations",
        "--module-prefix",
        "Custom",
        "--output-dir",
        "lib/custom",
        "--dry-run",
        "--domain",
        "Accounts",
        "--context-tables",
        "users,profiles",
        "--path",
        "queries",
        "--association-naming",
        "fk_stem",
        "--association-naming-apply",
        "always",
        "--singularize"
      ]

      switches = [
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

      {opts, _, _} = OptionParser.parse(args, switches: switches)

      assert opts[:repo] == "MyApp.Repo"
      assert opts[:schema] == "custom_schema"
      assert opts[:table] == "users"
      assert opts[:exclude_views] == true
      assert opts[:binary_id] == true
      assert opts[:no_timestamps] == true
      assert opts[:no_associations] == true
      assert opts[:module_prefix] == "Custom"
      assert opts[:output_dir] == "lib/custom"
      assert opts[:dry_run] == true
      assert opts[:domain] == "Accounts"
      assert opts[:context_tables] == "users,profiles"
      assert opts[:path] == "queries"
      assert opts[:association_naming] == "fk_stem"
      assert opts[:association_naming_apply] == "always"
      assert opts[:singularize] == true
    end

    test "parses --context as alias for --domain" do
      args = [
        "--repo",
        "MyApp.Repo",
        "--context",
        "Accounts",
        "--context-tables",
        "users,profiles"
      ]

      switches = [
        repo: :string,
        context: :string,
        context_tables: :string
      ]

      {opts, _, _} = OptionParser.parse(args, switches: switches)

      assert opts[:repo] == "MyApp.Repo"
      assert opts[:context] == "Accounts"
      assert opts[:context_tables] == "users,profiles"
    end

    test "context-tables limits table generation" do
      args = [
        "--repo",
        "MyApp.Repo",
        "--context-tables",
        "users,profiles"
      ]

      switches = [
        repo: :string,
        context_tables: :string
      ]

      {opts, _, _} = OptionParser.parse(args, switches: switches)

      assert opts[:context_tables] == "users,profiles"
    end

    test "path option works with domain" do
      args = [
        "--repo",
        "MyApp.Repo",
        "--path",
        "queries/reports",
        "--domain",
        "Analytics"
      ]

      switches = [
        repo: :string,
        path: :string,
        domain: :string
      ]

      {opts, _, _} = OptionParser.parse(args, switches: switches)

      assert opts[:path] == "queries/reports"
      assert opts[:domain] == "Analytics"
    end

    test "singularize defaults to false when not provided" do
      args = ["--repo", "MyApp.Repo"]

      switches = [
        repo: :string,
        singularize: :boolean
      ]

      {opts, _, _} = OptionParser.parse(args, switches: switches)

      refute opts[:singularize]
    end

    test "singularize is true when flag is present" do
      args = ["--repo", "MyApp.Repo", "--singularize"]

      switches = [
        repo: :string,
        singularize: :boolean
      ]

      {opts, _, _} = OptionParser.parse(args, switches: switches)

      assert opts[:singularize] == true
    end
  end
end
