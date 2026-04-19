defmodule Introspex.AshResourceBuilder do
  @moduledoc """
  Builds Ash 3.x resource definitions from database introspection data.

  ## Generated resource structure

      defmodule MyApp.Accounts.User do
        use Ash.Resource,
          domain: MyApp.Accounts,
          data_layer: AshPostgres.DataLayer

        postgres do
          table "users"
          repo MyApp.Repo

          references do
            reference :organization, on_delete: :nothing, on_update: :nothing
          end
        end

        actions do
          defaults [:read, :destroy, create: :*, update: :*]
        end

        attributes do
          uuid_primary_key :id
          attribute :email, :string do
            allow_nil? false
          end
          attribute :name, :string
          timestamps()
        end

        relationships do
          belongs_to :organization, MyApp.Accounts.Organization
          has_many :posts, MyApp.Blog.Post do
            destination_attribute :user_id
          end
        end

        identities do
          identity :unique_email, [:email]
        end
      end

  ## Notes on generated output

  - Enums are rendered as `:atom` with `constraints: [one_of: [...]]`. Upgrade to a
    custom `Ash.Type` for DB-level type safety.
  - `many_to_many` emits a `through:` referencing the join table as a full module.
    Ensure the join table is also generated as an Ash resource.
  - PostGIS geometry/geography types are rendered as `:string`. Configure
    `AshPostgres` PostGIS support separately.
  - JSON/JSONB fields use Ash's native `:map` type directly (no manual annotation needed).
  - Use `public: true` opt (or `--public` CLI flag) to add `public? true` to all
    attributes and relationships, making them visible to Ash actions by default.
  """

  alias Introspex.Postgres.TypeMapper
  alias Introspex.SchemaBuilder

  @association_kinds [:belongs_to, :has_many, :has_one, :many_to_many]

  @doc """
  Builds a complete Ash resource module from table metadata.

  ## Parameters

    * `table_info` - Map with keys: `table`, `columns`, `primary_keys`,
      `relationships`, `unique_constraints`, `check_constraints`, `table_type`
    * `module_name` - Full module name string, e.g. `"MyApp.Accounts.User"`
    * `opts` - Keyword list:
      * `:binary_id` - use UUID primary keys (default: false, auto-detected)
      * `:skip_timestamps` - omit `timestamps()` macro (default: false)
      * `:no_associations` - skip all relationship generation (default: false)
      * `:module_prefix` - prefix for related module name resolution
      * `:repo_module` - the Ecto.Repo module name string (default: `"MyApp.Repo"`)
      * `:domain_module` - the Ash Domain module name string (optional)
      * `:association_naming` - naming strategy: `"fk_stem"`, `"table_plus_stem"`,
        `"constraint"` (default: `"table_plus_stem"`)
      * `:association_naming_apply` - when to apply: `"duplicates_only"`, `"always"`
        (default: `"duplicates_only"`)
      * `:public` - add `public? true` to all attributes and relationships (default: false)

  Returns a string containing the complete resource module code.
  """
  def build_resource(table_info, module_name, opts \\ []) do
    %{
      table: table,
      columns: columns,
      primary_keys: primary_keys,
      relationships: relationships,
      unique_constraints: unique_constraints,
      check_constraints: check_constraints,
      table_type: table_type
    } = table_info

    binary_id = Keyword.get(opts, :binary_id, false)
    skip_timestamps = Keyword.get(opts, :skip_timestamps, false)
    module_prefix = Keyword.get(opts, :module_prefix)
    repo_module = Keyword.get(opts, :repo_module, "MyApp.Repo")
    domain_module = Keyword.get(opts, :domain_module)
    no_associations = Keyword.get(opts, :no_associations, false)
    singularize = Keyword.get(opts, :singularize, true)
    public = Keyword.get(opts, :public, false)

    primary_key_info = detect_primary_key_type(columns, primary_keys)

    has_timestamps = TypeMapper.ecto_timestamps_compatible?(columns) and not skip_timestamps

    schema_fields =
      if has_timestamps do
        Enum.reject(columns, &TypeMapper.ecto_timestamp_field?(&1.name))
      else
        columns
      end

    relationships = SchemaBuilder.normalize_relationships(relationships, opts)

    foreign_key_fields =
      if !no_associations do
        relationships.belongs_to |> Enum.map(& &1.foreign_key) |> Enum.map(&to_string/1)
      else
        []
      end

    attribute_fields = Enum.reject(schema_fields, &(&1.name in foreign_key_fields))

    build_module(%{
      module_name: module_name,
      table: table,
      attribute_fields: attribute_fields,
      columns: columns,
      primary_keys: primary_keys,
      primary_key_info: primary_key_info,
      binary_id: binary_id,
      has_timestamps: has_timestamps,
      relationships: relationships,
      unique_constraints: unique_constraints,
      check_constraints: check_constraints,
      table_type: table_type,
      module_prefix: module_prefix,
      repo_module: repo_module,
      domain_module: domain_module,
      no_associations: no_associations,
      singularize: singularize,
      public: public
    })
  end

  defp detect_primary_key_type(columns, primary_keys) do
    case primary_keys do
      [pk_name] ->
        pk_column = Enum.find(columns, &(&1.name == pk_name))

        if pk_column do
          is_uuid = pk_column.data_type in ["uuid", "UUID"]
          has_db_default = pk_column.has_db_default

          %{
            name: pk_name,
            is_uuid: is_uuid,
            has_db_default: has_db_default,
            data_type: pk_column.data_type
          }
        else
          %{name: pk_name, is_uuid: false, has_db_default: false, data_type: "integer"}
        end

      _ ->
        %{name: nil, is_uuid: false, has_db_default: false, data_type: "integer"}
    end
  end

  defp build_module(%{
         module_name: module_name,
         table: table,
         attribute_fields: attribute_fields,
         columns: columns,
         primary_keys: primary_keys,
         primary_key_info: primary_key_info,
         binary_id: binary_id,
         has_timestamps: has_timestamps,
         relationships: relationships,
         unique_constraints: unique_constraints,
         check_constraints: check_constraints,
         table_type: table_type,
         module_prefix: module_prefix,
         repo_module: repo_module,
         domain_module: domain_module,
         no_associations: no_associations,
         singularize: singularize,
         public: public
       }) do
    comment_doc =
      if table.comment do
        "@moduledoc \"\"\"\n  #{table.comment}\n  \"\"\""
      else
        case table_type do
          :view -> "@moduledoc \"Ash resource for database view\""
          :materialized_view -> "@moduledoc \"Ash resource for materialized view\""
          _ -> "@moduledoc false"
        end
      end

    domain_opts =
      if domain_module do
        "domain: #{domain_module},\n    data_layer: AshPostgres.DataLayer"
      else
        "# domain: MyApp.MyDomain,  # specify your Ash domain\n    data_layer: AshPostgres.DataLayer"
      end

    belongs_to_rels =
      if !no_associations && table_type == :table,
        do: Map.get(relationships, :belongs_to, []),
        else: []

    postgres_section =
      build_postgres_section(
        table.name,
        repo_module,
        check_constraints,
        belongs_to_rels,
        unique_constraints,
        table_type
      )

    attributes_section =
      build_attributes_section(
        attribute_fields,
        primary_keys,
        primary_key_info,
        binary_id,
        has_timestamps,
        public
      )

    relationships_section =
      if !no_associations && table_type == :table do
        build_relationships_section(
          relationships,
          module_prefix,
          columns,
          singularize,
          primary_keys,
          public
        )
      else
        nil
      end

    resource_section = build_resource_section(primary_keys, table_type)
    actions_section = build_actions_section(table_type, primary_keys)
    identities_section = build_identities_section(unique_constraints)

    sections =
      [
        postgres_section,
        resource_section,
        actions_section,
        attributes_section,
        relationships_section,
        identities_section
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n  ")

    """
    defmodule #{module_name} do
      #{comment_doc}
      use Ash.Resource,
        #{domain_opts}

      #{sections}
    end
    """
  end

  defp build_postgres_section(
         table_name,
         repo_module,
         check_constraints,
         belongs_to_rels,
         unique_constraints,
         table_type
       ) do
    references_block =
      if belongs_to_rels != [] do
        lines =
          Enum.map(belongs_to_rels, fn assoc ->
            "      reference :#{assoc.field}, on_delete: :nothing, on_update: :nothing"
          end)

        "\n\n    references do\n#{Enum.join(lines, "\n")}\n    end"
      else
        ""
      end

    identity_index_names_line =
      case Enum.filter(unique_constraints, &(length(&1.columns) > 0)) do
        [] ->
          ""

        constraints ->
          pairs =
            Enum.map_join(constraints, ", ", fn c ->
              "#{c.constraint_name}: \"#{c.constraint_name}\""
            end)

          "\n\n    identity_index_names [#{pairs}]"
      end

    constraints_comment =
      if check_constraints && length(check_constraints) > 0 do
        lines =
          Enum.map(check_constraints, fn c ->
            "    # check_constraint :field, name: \"#{c.constraint_name}\", message: \"TODO: set message\"\n" <>
              "    # SQL: #{c.definition}"
          end)

        "\n\n    # Check constraints detected - set field name and message before enabling:\n" <>
          Enum.join(lines, "\n")
      else
        ""
      end

    view_block =
      if table_type in [:view, :materialized_view] do
        "\n    migrate? false\n    # TODO: Create this #{if table_type == :materialized_view, do: "materialized view", else: "view"} migration manually, e.g.:\n    # execute \"CREATE #{if table_type == :materialized_view, do: "MATERIALIZED VIEW", else: "VIEW"} #{table_name} AS SELECT ...\""
      else
        ""
      end

    "postgres do\n    table \"#{table_name}\"\n    repo #{repo_module}#{view_block}#{references_block}#{identity_index_names_line}#{constraints_comment}\n  end"
  end

  defp build_attributes_section(
         fields,
         primary_keys,
         primary_key_info,
         binary_id,
         has_timestamps,
         public
       ) do
    pk_line = build_primary_key_attribute(primary_keys, primary_key_info, binary_id, public)

    field_lines =
      case primary_keys do
        [single_pk] -> Enum.reject(fields, &(&1.name == single_pk))
        _ -> fields
      end
      |> Enum.map(&build_attribute_definition(&1, primary_keys, public))
      |> Enum.reject(&is_nil/1)

    timestamps_line = if has_timestamps, do: ["timestamps()"], else: []

    all_lines = List.wrap(pk_line) ++ field_lines ++ timestamps_line
    inner = Enum.join(all_lines, "\n    ")
    "attributes do\n    #{inner}\n  end"
  end

  defp build_primary_key_attribute([single_pk], pk_info, binary_id, public) do
    cond do
      # UUID type or --binary-id forced: Ash generates the UUID value
      pk_info.is_uuid || binary_id ->
        "uuid_primary_key :#{single_pk}"

      pk_info.has_db_default && TypeMapper.integer_type?(pk_info.data_type) ->
        "integer_primary_key :#{single_pk}"

      # Everything else (manual integer, varchar, etc.): user must supply the value
      true ->
        type_str =
          pk_info.data_type
          |> TypeMapper.ash_map_type(nil, default: nil)
          |> TypeMapper.ash_type_to_string()

        body =
          ["primary_key? true", "allow_nil? false"] ++ if(public, do: ["public? true"], else: [])

        "attribute :#{single_pk}, #{type_str} do\n      #{Enum.join(body, "\n      ")}\n    end"
    end
  end

  defp build_primary_key_attribute(_primary_keys, _pk_info, _binary_id, _public) do
    nil
  end

  @uuid_gen_functions ~w[gen_random_uuid() uuid_generate_v4() uuid_generate_v1()]

  defp build_attribute_definition(column, primary_keys, public) do
    %{
      name: name,
      data_type: data_type,
      not_null: not_null,
      default: default,
      enum_values: enum_values
    } = column

    generated_always = Map.get(column, :generated_always, false)
    has_db_default = Map.get(column, :has_db_default, false)

    type = TypeMapper.ash_map_type(data_type, enum_values, default: default)
    type_string = TypeMapper.ash_type_to_string(type)

    is_composite_pk_col = length(primary_keys) > 1 && name in primary_keys

    body_lines =
      cond do
        is_composite_pk_col ->
          ["primary_key? true", "allow_nil? false"]

        generated_always ->
          if not_null, do: ["writable? false", "allow_nil? false"], else: ["writable? false"]

        has_db_default ->
          if not_null, do: ["generated? true", "allow_nil? false"], else: ["generated? true"]

        not_null ->
          ["allow_nil? false"]

        true ->
          []
      end

    body_lines = if public, do: body_lines ++ ["public? true"], else: body_lines

    attribute_line =
      if body_lines == [] do
        "attribute :#{name}, #{type_string}"
      else
        "attribute :#{name}, #{type_string} do\n      #{Enum.join(body_lines, "\n      ")}\n    end"
      end

    if default in @uuid_gen_functions do
      "# DB default: #{default} — add `default &Ash.UUID.generate/0` if Ash should generate this\n    #{attribute_line}"
    else
      attribute_line
    end
  end

  defp build_relationships_section(
         relationships,
         module_prefix,
         columns,
         singularize,
         primary_keys,
         public
       ) do
    all_assoc_lists = Enum.map(@association_kinds, &Map.get(relationships, &1, []))

    if Enum.all?(all_assoc_lists, &(&1 == [])) do
      nil
    else
      belongs_to_lines =
        Enum.map(
          Map.get(relationships, :belongs_to, []),
          &build_belongs_to_relationship(
            &1,
            module_prefix,
            columns,
            singularize,
            primary_keys,
            public
          )
        )

      has_many_lines =
        Enum.map(
          Map.get(relationships, :has_many, []),
          &build_has_many_relationship(&1, module_prefix, singularize, public)
        )

      has_one_lines =
        Enum.map(
          Map.get(relationships, :has_one, []),
          &build_has_one_relationship(&1, module_prefix, singularize, public)
        )

      many_to_many_lines =
        Enum.map(
          Map.get(relationships, :many_to_many, []),
          &build_many_to_many_relationship(&1, module_prefix, singularize, public)
        )

      all_lines = belongs_to_lines ++ has_many_lines ++ has_one_lines ++ many_to_many_lines

      if all_lines == [] do
        nil
      else
        inner = Enum.join(all_lines, "\n    ")
        "relationships do\n    #{inner}\n  end"
      end
    end
  end

  defp build_belongs_to_relationship(
         assoc,
         module_prefix,
         columns,
         singularize,
         primary_keys,
         public
       ) do
    module_name = table_to_module(assoc.table, module_prefix, singularize)

    body =
      []
      |> maybe_add(
        assoc.foreign_key != String.to_atom(to_string(assoc.field) <> "_id"),
        "source_attribute :#{assoc.foreign_key}"
      )
      |> then(fn acc ->
        fk_column = Enum.find(columns, &(&1.name == to_string(assoc.foreign_key)))

        if fk_column &&
             fk_column.data_type in ["integer", "bigint", "int4", "int8", "smallint", "int2"],
           do: ["attribute_type :integer" | acc],
           else: acc
      end)
      |> maybe_add(to_string(assoc.foreign_key) in primary_keys, "primary_key? true")
      |> maybe_add(to_string(assoc.foreign_key) in primary_keys, "allow_nil? false")
      |> maybe_add(public, "public? true")
      |> Enum.reverse()

    if body == [] do
      "belongs_to :#{assoc.field}, #{module_name}"
    else
      "belongs_to :#{assoc.field}, #{module_name} do\n      #{Enum.join(body, "\n      ")}\n    end"
    end
  end

  defp build_has_many_relationship(assoc, module_prefix, singularize, public) do
    module_name = table_to_module(assoc.table, module_prefix, singularize)

    body =
      ["destination_attribute :#{assoc.foreign_key}"]
      |> maybe_add(public, "public? true")

    "has_many :#{assoc.field}, #{module_name} do\n      #{Enum.join(body, "\n      ")}\n    end"
  end

  defp build_has_one_relationship(assoc, module_prefix, singularize, public) do
    module_name = table_to_module(assoc.table, module_prefix, singularize)

    body =
      ["destination_attribute :#{assoc.foreign_key}"]
      |> maybe_add(public, "public? true")

    "has_one :#{assoc.field}, #{module_name} do\n      #{Enum.join(body, "\n      ")}\n    end"
  end

  defp build_many_to_many_relationship(assoc, module_prefix, singularize, public) do
    module_name = table_to_module(assoc.table, module_prefix, singularize)
    through_module = table_to_module(assoc.join_through, module_prefix, singularize)

    # join_keys: [{source_fk_in_join, :id}, {:id, dest_fk_in_join}]
    {source_attr, source_fallback?} =
      case assoc.join_keys do
        [{src, _} | _] -> {src, false}
        _ -> {:source_id, true}
      end

    {dest_attr, dest_fallback?} =
      case Enum.at(assoc.join_keys, 1) do
        {_, dest} -> {dest, false}
        _ -> {:destination_id, true}
      end

    todo_comment =
      if source_fallback? || dest_fallback?,
        do: "# TODO: verify source/destination attributes on join resource\n    ",
        else: ""

    body =
      [
        "through #{through_module}",
        "source_attribute_on_join_resource :#{source_attr}",
        "destination_attribute_on_join_resource :#{dest_attr}"
      ]
      |> maybe_add(public, "public? true")

    todo_comment <>
      "many_to_many :#{assoc.field}, #{module_name} do\n      #{Enum.join(body, "\n      ")}\n    end"
  end

  defp build_resource_section(primary_keys, table_type) do
    if Enum.empty?(primary_keys) do
      warning =
        if table_type == :table,
          do:
            "\n    # WARNING: Configured to bypass missing primary key.\n    # Add primary_key?: true to your attributes/relationships and remove this block.",
          else: ""

      "resource do#{warning}\n    require_primary_key? false\n  end"
    else
      nil
    end
  end

  defp build_actions_section(table_type, primary_keys) do
    actions =
      cond do
        table_type != :table ->
          "defaults [:read]"

        Enum.empty?(primary_keys) ->
          "# WARNING: No primary key detected.\n    # :update and :destroy actions require a primary key to safely identify records.\n    defaults [:read, create: :*]"

        true ->
          "defaults [:read, :destroy, create: :*, update: :*]"
      end

    "actions do\n    #{actions}\n  end"
  end

  defp build_identities_section([]), do: nil

  defp build_identities_section(unique_constraints) do
    identity_lines =
      unique_constraints
      |> Enum.filter(fn c -> length(c.columns) > 0 end)
      |> Enum.map(fn constraint ->
        cols = constraint.columns |> Enum.map_join(", ", &":#{&1}")
        "identity :#{constraint.constraint_name}, [#{cols}]"
      end)

    inner = Enum.join(identity_lines, "\n    ")
    "identities do\n    #{inner}\n  end"
  end

  defp table_to_module(table_name, module_prefix, singularize) do
    name = if singularize, do: Inflex.singularize(table_name), else: table_name

    if module_prefix do
      "#{module_prefix}.#{Macro.camelize(name)}"
    else
      Macro.camelize(name)
    end
  end

  defp maybe_add(list, condition, item) do
    if condition, do: list ++ [item], else: list
  end
end
