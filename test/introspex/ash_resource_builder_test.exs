defmodule Introspex.AshResourceBuilderTest do
  use ExUnit.Case, async: true

  alias Introspex.AshResourceBuilder

  # Shared helpers

  defp base_table_info(overrides \\ %{}) do
    Map.merge(
      %{
        table: %{name: "users", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "uuid",
            not_null: true,
            default: "gen_random_uuid()",
            has_db_default: true,
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "email",
            data_type: "varchar",
            not_null: true,
            default: nil,
            has_db_default: false,
            comment: nil,
            position: 2,
            enum_values: nil
          },
          %{
            name: "name",
            data_type: "varchar",
            not_null: false,
            default: nil,
            has_db_default: false,
            comment: nil,
            position: 3,
            enum_values: nil
          },
          %{
            name: "inserted_at",
            data_type: "timestamp",
            not_null: true,
            default: "now()",
            has_db_default: true,
            comment: nil,
            position: 4,
            enum_values: nil
          },
          %{
            name: "updated_at",
            data_type: "timestamp",
            not_null: true,
            default: "now()",
            has_db_default: true,
            comment: nil,
            position: 5,
            enum_values: nil
          }
        ],
        primary_keys: ["id"],
        relationships: %{belongs_to: [], has_many: [], has_one: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      },
      overrides
    )
  end

  describe "build_resource/3 - module structure" do
    test "emits use Ash.Resource with data_layer" do
      result = AshResourceBuilder.build_resource(base_table_info(), "MyApp.User")
      assert result =~ "use Ash.Resource"
      assert result =~ "data_layer: AshPostgres.DataLayer"
    end

    test "includes domain when provided" do
      result =
        AshResourceBuilder.build_resource(base_table_info(), "MyApp.Accounts.User",
          domain_module: "MyApp.Accounts"
        )

      assert result =~ "domain: MyApp.Accounts"
    end

    test "emits a domain placeholder comment when domain not provided" do
      result = AshResourceBuilder.build_resource(base_table_info(), "MyApp.User")
      assert result =~ "# domain:"
    end

    test "emits postgres block with table and repo" do
      result =
        AshResourceBuilder.build_resource(base_table_info(), "MyApp.User",
          repo_module: "MyApp.Repo"
        )

      assert result =~ ~s(table "users")
      assert result =~ "repo MyApp.Repo"
    end

    test "emits @moduledoc false for regular tables" do
      result = AshResourceBuilder.build_resource(base_table_info(), "MyApp.User")
      assert result =~ "@moduledoc false"
    end

    test "emits view moduledoc for views" do
      info =
        base_table_info(%{
          table: %{name: "user_view", type: :view, comment: nil},
          table_type: :view
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.UserView")
      assert result =~ "Ash resource for database view"
    end

    test "includes table comment as moduledoc" do
      info =
        base_table_info(%{table: %{name: "users", type: :table, comment: "Stores user accounts"}})

      result = AshResourceBuilder.build_resource(info, "MyApp.User")
      assert result =~ "Stores user accounts"
    end
  end

  describe "build_resource/3 - primary keys" do
    test "emits uuid_primary_key :id for UUID primary key" do
      result = AshResourceBuilder.build_resource(base_table_info(), "MyApp.User")
      assert result =~ "uuid_primary_key :id"
    end

    test "emits uuid_primary_key :id when --binary-id flag is set" do
      info =
        base_table_info(%{
          columns: [
            %{
              name: "id",
              data_type: "integer",
              not_null: true,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 1,
              enum_values: nil
            },
            %{
              name: "email",
              data_type: "varchar",
              not_null: false,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 2,
              enum_values: nil
            }
          ]
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User", binary_id: true)
      assert result =~ "uuid_primary_key :id"
    end

    test "emits integer_primary_key :id for serial integer primary key" do
      info =
        base_table_info(%{
          columns: [
            # has_db_default: true simulates a SERIAL column (nextval default stripped by parse_default)
            %{
              name: "id",
              data_type: "integer",
              not_null: true,
              default: nil,
              has_db_default: true,
              comment: nil,
              position: 1,
              enum_values: nil
            },
            %{
              name: "email",
              data_type: "varchar",
              not_null: false,
              default: nil,
              comment: nil,
              position: 2,
              enum_values: nil
            },
            %{
              name: "inserted_at",
              data_type: "timestamp",
              not_null: true,
              default: nil,
              comment: nil,
              position: 3,
              enum_values: nil
            },
            %{
              name: "updated_at",
              data_type: "timestamp",
              not_null: true,
              default: nil,
              comment: nil,
              position: 4,
              enum_values: nil
            }
          ]
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User")
      assert result =~ "integer_primary_key :id"
    end

    test "emits manual attribute for integer primary key without sequence default" do
      info =
        base_table_info(%{
          columns: [
            %{
              name: "id",
              data_type: "integer",
              not_null: true,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 1,
              enum_values: nil
            },
            %{
              name: "email",
              data_type: "varchar",
              not_null: false,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 2,
              enum_values: nil
            },
            %{
              name: "inserted_at",
              data_type: "timestamp",
              not_null: true,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 3,
              enum_values: nil
            },
            %{
              name: "updated_at",
              data_type: "timestamp",
              not_null: true,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 4,
              enum_values: nil
            }
          ]
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User")
      assert result =~ "attribute :id, :integer do"
      assert result =~ "primary_key? true"
      assert result =~ "allow_nil? false"
    end

    test "emits uuid_primary_key for non-standard primary key name when binary_id forced" do
      info =
        base_table_info(%{
          columns: [
            %{
              name: "user_uuid",
              data_type: "uuid",
              not_null: true,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 1,
              enum_values: nil
            }
          ],
          primary_keys: ["user_uuid"]
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User", binary_id: true)
      assert result =~ "uuid_primary_key :user_uuid"
    end

    test "emits uuid_primary_key for UUID primary key without DB default (Ash generates)" do
      info =
        base_table_info(%{
          columns: [
            %{
              name: "user_uuid",
              data_type: "uuid",
              not_null: true,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 1,
              enum_values: nil
            }
          ],
          primary_keys: ["user_uuid"]
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User")
      assert result =~ "uuid_primary_key :user_uuid"
    end

    test "composite PK columns that are not FKs get primary_key?: true as attributes" do
      info =
        base_table_info(%{
          columns: [
            %{
              name: "user_id",
              data_type: "integer",
              not_null: true,
              default: nil,
              comment: nil,
              position: 1,
              enum_values: nil
            },
            %{
              name: "role_id",
              data_type: "integer",
              not_null: true,
              default: nil,
              comment: nil,
              position: 2,
              enum_values: nil
            }
          ],
          primary_keys: ["user_id", "role_id"]
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.UserRole")
      refute result =~ "composite primary key"
      assert result =~ "attribute :user_id, :integer do"
      assert result =~ "attribute :role_id, :integer do"
      assert result =~ "primary_key? true"
      assert result =~ "allow_nil? false"
    end

    test "mixed composite PK: FK gets primary_key?: true on belongs_to, non-FK gets it as attribute" do
      info =
        base_table_info(%{
          table: %{name: "membership", type: :table, comment: nil},
          columns: [
            %{
              name: "user_id",
              data_type: "integer",
              not_null: true,
              default: nil,
              comment: nil,
              position: 1,
              enum_values: nil
            },
            %{
              name: "rank",
              data_type: "integer",
              not_null: true,
              default: nil,
              comment: nil,
              position: 2,
              enum_values: nil
            }
          ],
          primary_keys: ["user_id", "rank"],
          relationships: %{
            belongs_to: [
              %{
                field: :user,
                table: "users",
                foreign_key: :user_id,
                constraint_name: "fk_user",
                references: :id,
                on_update: :no_action,
                on_delete: :no_action
              }
            ],
            has_many: [],
            has_one: [],
            many_to_many: []
          }
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.Membership", module_prefix: "MyApp")
      refute result =~ "composite primary key"
      assert result =~ "primary_key? true"
      assert result =~ "attribute :rank, :integer do"
      assert result =~ "belongs_to :user, MyApp.User"
    end

    test "join table: emits primary_key?: true on belongs_to and empty attributes when all PKs are FKs" do
      info =
        base_table_info(%{
          table: %{name: "special_area_owner", type: :table, comment: nil},
          columns: [
            %{
              name: "special_area_id",
              data_type: "integer",
              not_null: true,
              default: nil,
              comment: nil,
              position: 1,
              enum_values: nil
            },
            %{
              name: "owner_id",
              data_type: "integer",
              not_null: true,
              default: nil,
              comment: nil,
              position: 2,
              enum_values: nil
            }
          ],
          primary_keys: ["special_area_id", "owner_id"],
          relationships: %{
            belongs_to: [
              %{
                field: :special_area,
                table: "special_areas",
                foreign_key: :special_area_id,
                constraint_name: "fk_sa",
                references: :id,
                on_update: :no_action,
                on_delete: :no_action
              },
              %{
                field: :user,
                table: "users",
                foreign_key: :owner_id,
                constraint_name: "fk_owner",
                references: :id,
                on_update: :no_action,
                on_delete: :no_action
              }
            ],
            has_many: [],
            has_one: [],
            many_to_many: []
          }
        })

      result =
        AshResourceBuilder.build_resource(info, "MyApp.SpecialAreaOwner", module_prefix: "MyApp")

      refute result =~ "composite primary key"
      assert result =~ "primary_key? true"
      assert result =~ "belongs_to :special_area, MyApp.SpecialArea"
      assert result =~ "belongs_to :user, MyApp.User"
    end

    test "join table: source_attribute emitted alongside primary_key? when FK doesn't follow field_id convention" do
      info =
        base_table_info(%{
          table: %{name: "special_area_owner", type: :table, comment: nil},
          columns: [
            %{
              name: "special_area_id",
              data_type: "integer",
              not_null: true,
              default: nil,
              comment: nil,
              position: 1,
              enum_values: nil
            },
            %{
              name: "owner_id",
              data_type: "integer",
              not_null: true,
              default: nil,
              comment: nil,
              position: 2,
              enum_values: nil
            }
          ],
          primary_keys: ["special_area_id", "owner_id"],
          relationships: %{
            belongs_to: [
              %{
                field: :special_area,
                table: "special_areas",
                foreign_key: :special_area_id,
                constraint_name: "fk_sa",
                references: :id,
                on_update: :no_action,
                on_delete: :no_action
              },
              # field is :user but FK is :owner_id — non-standard, should emit source_attribute: too
              %{
                field: :user,
                table: "users",
                foreign_key: :owner_id,
                constraint_name: "fk_owner",
                references: :id,
                on_update: :no_action,
                on_delete: :no_action
              }
            ],
            has_many: [],
            has_one: [],
            many_to_many: []
          }
        })

      result =
        AshResourceBuilder.build_resource(info, "MyApp.SpecialAreaOwner", module_prefix: "MyApp")

      assert result =~ "source_attribute :owner_id"
      assert result =~ "primary_key? true"
    end
  end

  describe "build_resource/3 - attributes" do
    test "emits attribute with allow_nil? false for not-null columns without defaults" do
      result = AshResourceBuilder.build_resource(base_table_info(), "MyApp.User")
      assert result =~ "attribute :email, :string do"
      assert result =~ "allow_nil? false"
    end

    test "emits attribute without allow_nil? for nullable columns" do
      result = AshResourceBuilder.build_resource(base_table_info(), "MyApp.User")
      assert result =~ "attribute :name, :string"
      refute result =~ "attribute :name, :string do"
    end

    test "skips allow_nil?: false for not-null columns that have a default" do
      info =
        base_table_info(%{
          columns: [
            %{
              name: "id",
              data_type: "uuid",
              not_null: true,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 1,
              enum_values: nil
            },
            %{
              name: "status",
              data_type: "varchar",
              not_null: true,
              default: "'active'",
              has_db_default: true,
              comment: nil,
              position: 2,
              enum_values: nil
            }
          ]
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User")
      assert result =~ "attribute :status, :string do"
      assert result =~ "generated? true"
      assert result =~ "allow_nil? false"
    end

    test "does not emit :id as a separate attribute when using uuid_primary_key" do
      result = AshResourceBuilder.build_resource(base_table_info(), "MyApp.User")
      refute result =~ "attribute :id,"
    end

    test "emits timestamps() macro for compatible timestamp columns" do
      result = AshResourceBuilder.build_resource(base_table_info(), "MyApp.User")
      assert result =~ "timestamps()"
      refute result =~ "attribute :inserted_at"
      refute result =~ "attribute :updated_at"
    end

    test "skips timestamps() when --no-timestamps is set" do
      result =
        AshResourceBuilder.build_resource(base_table_info(), "MyApp.User", skip_timestamps: true)

      refute result =~ "timestamps()"
      assert result =~ "attribute :inserted_at"
    end

    test "emits DB default comment for non-PK UUID column with gen_random_uuid() default" do
      info =
        base_table_info(%{
          columns: [
            %{
              name: "id",
              data_type: "uuid",
              not_null: true,
              default: "gen_random_uuid()",
              has_db_default: true,
              comment: nil,
              position: 1,
              enum_values: nil
            },
            %{
              name: "token",
              data_type: "uuid",
              not_null: true,
              default: "gen_random_uuid()",
              has_db_default: true,
              comment: nil,
              position: 2,
              enum_values: nil
            }
          ]
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User")
      assert result =~ "# DB default: gen_random_uuid()"
      assert result =~ "Ash.UUID.generate"
      assert result =~ "attribute :token, :uuid"
    end

    test "emits writable?: false for GENERATED ALWAYS AS IDENTITY columns" do
      info =
        base_table_info(%{
          columns: [
            %{
              name: "id",
              data_type: "uuid",
              not_null: true,
              default: "gen_random_uuid()",
              has_db_default: true,
              comment: nil,
              position: 1,
              enum_values: nil
            },
            %{
              name: "row_num",
              data_type: "integer",
              not_null: true,
              default: nil,
              has_db_default: true,
              generated_always: true,
              comment: nil,
              position: 2,
              enum_values: nil
            }
          ]
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User")
      assert result =~ "attribute :row_num, :integer do"
      assert result =~ "writable? false"
      assert result =~ "allow_nil? false"
    end
  end

  describe "build_resource/3 - Ash type mapping" do
    test "maps UUID columns to :uuid" do
      info =
        base_table_info(%{
          columns: [
            %{
              name: "external_id",
              data_type: "uuid",
              not_null: false,
              default: nil,
              comment: nil,
              position: 2,
              enum_values: nil
            }
          ],
          primary_keys: []
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User")
      assert result =~ "attribute :external_id, :uuid"
    end

    test "maps json/jsonb columns to :map (no manual comment needed)" do
      info =
        base_table_info(%{
          columns: [
            %{
              name: "id",
              data_type: "integer",
              not_null: true,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 1,
              enum_values: nil
            },
            %{
              name: "metadata",
              data_type: "jsonb",
              not_null: false,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 2,
              enum_values: nil
            },
            %{
              name: "config",
              data_type: "json",
              not_null: false,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 3,
              enum_values: nil
            }
          ]
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User")
      assert result =~ "attribute :metadata, :map"
      assert result =~ "attribute :config, :map"
    end

    test "maps enum columns to :atom with constraints" do
      info =
        base_table_info(%{
          columns: [
            %{
              name: "id",
              data_type: "integer",
              not_null: true,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 1,
              enum_values: nil
            },
            %{
              name: "status",
              data_type: "user-defined",
              not_null: true,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 2,
              enum_values: ["active", "inactive", "banned"]
            }
          ]
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User")
      assert result =~ ":atom, constraints: [one_of: ["
      assert result =~ ":active"
      assert result =~ ":inactive"
      assert result =~ ":banned"
    end
  end

  describe "build_resource/3 - relationships" do
    test "emits belongs_to relationship" do
      info =
        base_table_info(%{
          relationships: %{
            belongs_to: [
              %{
                field: :organization,
                table: "organizations",
                foreign_key: :organization_id,
                constraint_name: "users_org_fk",
                references: :id,
                on_update: :no_action,
                on_delete: :no_action
              }
            ],
            has_many: [],
            has_one: [],
            many_to_many: []
          }
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User", module_prefix: "MyApp")
      assert result =~ "belongs_to :organization, MyApp.Organization"
    end

    test "belongs_to with integer FK emits attribute_type: :integer (uuid table)" do
      info =
        base_table_info(%{
          columns: [
            %{
              name: "id",
              data_type: "uuid",
              not_null: true,
              default: "gen_random_uuid()",
              has_db_default: true,
              comment: nil,
              position: 1,
              enum_values: nil
            },
            %{
              name: "publisher_id",
              data_type: "integer",
              not_null: true,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 2,
              enum_values: nil
            }
          ],
          relationships: %{
            belongs_to: [
              %{
                field: :publisher,
                table: "publishers",
                foreign_key: :publisher_id,
                constraint_name: "fk_publisher",
                references: :id,
                on_update: :no_action,
                on_delete: :no_action
              }
            ],
            has_many: [],
            has_one: [],
            many_to_many: []
          }
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.Post", module_prefix: "MyApp")
      assert result =~ "attribute_type :integer"
    end

    test "belongs_to with integer FK emits attribute_type: :integer (integer table, no binary_id)" do
      info =
        base_table_info(%{
          columns: [
            %{
              name: "id",
              data_type: "integer",
              not_null: true,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 1,
              enum_values: nil
            },
            %{
              name: "publisher_id",
              data_type: "integer",
              not_null: true,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 2,
              enum_values: nil
            },
            %{
              name: "inserted_at",
              data_type: "timestamp",
              not_null: true,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 3,
              enum_values: nil
            },
            %{
              name: "updated_at",
              data_type: "timestamp",
              not_null: true,
              default: nil,
              has_db_default: false,
              comment: nil,
              position: 4,
              enum_values: nil
            }
          ],
          relationships: %{
            belongs_to: [
              %{
                field: :publisher,
                table: "publishers",
                foreign_key: :publisher_id,
                constraint_name: "fk_publisher",
                references: :id,
                on_update: :no_action,
                on_delete: :no_action
              }
            ],
            has_many: [],
            has_one: [],
            many_to_many: []
          }
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.Post", module_prefix: "MyApp")
      assert result =~ "attribute_type :integer"
    end

    test "belongs_to with non-standard FK name emits source_attribute" do
      # field is :author but FK column is :created_by_user_id — doesn't follow author_id convention
      info =
        base_table_info(%{
          relationships: %{
            belongs_to: [
              %{
                field: :author,
                table: "users",
                foreign_key: :created_by_user_id,
                constraint_name: "fk_author",
                references: :id,
                on_update: :no_action,
                on_delete: :no_action
              }
            ],
            has_many: [],
            has_one: [],
            many_to_many: []
          }
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.Post", module_prefix: "MyApp")
      assert result =~ "source_attribute :created_by_user_id"
    end

    test "emits has_many relationship with destination_attribute" do
      info =
        base_table_info(%{
          relationships: %{
            belongs_to: [],
            has_many: [
              %{
                field: :posts,
                table: "posts",
                foreign_key: :user_id,
                constraint_name: "posts_user_fk"
              }
            ],
            has_one: [],
            many_to_many: []
          }
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User", module_prefix: "MyApp")
      assert result =~ "has_many :posts, MyApp.Post"
      assert result =~ "destination_attribute :user_id"
    end

    test "emits has_one relationship with destination_attribute" do
      info =
        base_table_info(%{
          relationships: %{
            belongs_to: [],
            has_many: [],
            has_one: [
              %{
                field: :profile,
                table: "profiles",
                foreign_key: :user_id,
                constraint_name: "profiles_user_fk"
              }
            ],
            many_to_many: []
          }
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User", module_prefix: "MyApp")
      assert result =~ "has_one :profile, MyApp.Profile"
      assert result =~ "destination_attribute :user_id"
    end

    test "emits many_to_many with through resource and join attributes" do
      info =
        base_table_info(%{
          relationships: %{
            belongs_to: [],
            has_many: [],
            has_one: [],
            many_to_many: [
              %{
                field: :tags,
                table: "tags",
                constraint_name: "user_tags_tag_fk",
                join_through: "user_tags",
                join_keys: [{:user_id, :id}, {:id, :tag_id}]
              }
            ]
          }
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User", module_prefix: "MyApp")
      assert result =~ "many_to_many :tags, MyApp.Tag"
      assert result =~ "through MyApp.UserTag"
      assert result =~ "source_attribute_on_join_resource :user_id"
      assert result =~ "destination_attribute_on_join_resource :tag_id"
    end

    test "skips relationships block when no_associations is true" do
      info =
        base_table_info(%{
          relationships: %{
            belongs_to: [],
            has_many: [
              %{field: :posts, table: "posts", foreign_key: :user_id, constraint_name: nil}
            ],
            has_one: [],
            many_to_many: []
          }
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User", no_associations: true)
      refute result =~ "relationships do"
    end

    test "skips relationships block for views" do
      info =
        base_table_info(%{
          table: %{name: "user_view", type: :view, comment: nil},
          table_type: :view,
          relationships: %{
            belongs_to: [],
            has_many: [
              %{field: :posts, table: "posts", foreign_key: :user_id, constraint_name: nil}
            ],
            has_one: [],
            many_to_many: []
          }
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.UserView")
      refute result =~ "relationships do"
    end
  end

  describe "build_resource/3 - actions" do
    test "tables get full CRUD actions" do
      result = AshResourceBuilder.build_resource(base_table_info(), "MyApp.User")
      assert result =~ "defaults [:read, :destroy, create: :*, update: :*]"
    end

    test "views get read-only actions" do
      info =
        base_table_info(%{
          table: %{name: "user_view", type: :view, comment: nil},
          table_type: :view
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.UserView")
      assert result =~ "defaults [:read]"
      refute result =~ "create:"
    end

    test "materialized views get read-only actions" do
      info =
        base_table_info(%{
          table: %{name: "user_stats", type: :materialized_view, comment: nil},
          table_type: :materialized_view
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.UserStats")
      assert result =~ "defaults [:read]"
    end
  end

  describe "build_resource/3 - identities" do
    test "emits identity for unique constraints" do
      info =
        base_table_info(%{
          unique_constraints: [
            %{constraint_name: "users_email_index", columns: ["email"]}
          ]
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User")
      assert result =~ "identities do"
      assert result =~ "identity :users_email_index, [:email]"
    end

    test "emits multi-column identity" do
      info =
        base_table_info(%{
          unique_constraints: [
            %{constraint_name: "users_name_org_index", columns: ["name", "organization_id"]}
          ]
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User")
      assert result =~ "identity :users_name_org_index, [:name, :organization_id]"
    end

    test "omits identities block when no unique constraints" do
      result = AshResourceBuilder.build_resource(base_table_info(), "MyApp.User")
      refute result =~ "identities do"
    end

    test "skips identity with empty columns list" do
      info =
        base_table_info(%{
          unique_constraints: [
            %{constraint_name: "valid_index", columns: ["email"]},
            %{constraint_name: "broken_index", columns: []}
          ]
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User")
      assert result =~ "identity :valid_index"
      refute result =~ "identity :broken_index"
    end
  end

  describe "build_resource/3 - postgres references" do
    test "emits references block for belongs_to relationships" do
      info =
        base_table_info(%{
          relationships: %{
            belongs_to: [
              %{
                field: :organization,
                table: "organizations",
                foreign_key: :organization_id,
                constraint_name: "users_org_fk",
                references: :id,
                on_update: :no_action,
                on_delete: :no_action
              }
            ],
            has_many: [],
            has_one: [],
            many_to_many: []
          }
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User", module_prefix: "MyApp")
      assert result =~ "references do"
      assert result =~ "reference :organization, on_delete: :nothing, on_update: :nothing"
    end

    test "omits references block when there are no belongs_to relationships" do
      result = AshResourceBuilder.build_resource(base_table_info(), "MyApp.User")
      refute result =~ "references do"
    end

    test "emits identity_index_names in postgres block for unique constraints" do
      info =
        base_table_info(%{
          unique_constraints: [
            %{constraint_name: "users_email_index", columns: ["email"]},
            %{constraint_name: "users_name_org_index", columns: ["name", "organization_id"]}
          ]
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User")
      assert result =~ ~s(identity_index_names [users_email_index: "users_email_index", users_name_org_index: "users_name_org_index"])
    end

    test "omits identity_index_names when there are no unique constraints" do
      result = AshResourceBuilder.build_resource(base_table_info(), "MyApp.User")
      refute result =~ "identity_index_names"
    end

    test "omits identity_index_names for constraints with empty columns" do
      info =
        base_table_info(%{
          unique_constraints: [
            %{constraint_name: "broken_index", columns: []}
          ]
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User")
      refute result =~ "identity_index_names"
    end

    test "omits references block when no_associations is true" do
      info =
        base_table_info(%{
          relationships: %{
            belongs_to: [
              %{
                field: :organization,
                table: "organizations",
                foreign_key: :organization_id,
                constraint_name: "users_org_fk",
                references: :id,
                on_update: :no_action,
                on_delete: :no_action
              }
            ],
            has_many: [],
            has_one: [],
            many_to_many: []
          }
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User", no_associations: true)
      refute result =~ "references do"
    end
  end

  describe "build_resource/3 - public option" do
    test "uuid_primary_key and integer_primary_key are already public by default, no annotation added" do
      result = AshResourceBuilder.build_resource(base_table_info(), "MyApp.User", public: true)
      assert result =~ "uuid_primary_key :id"
      refute result =~ "uuid_primary_key :id, public?: true"
    end

    test "adds public? true to attributes when public: true" do
      result = AshResourceBuilder.build_resource(base_table_info(), "MyApp.User", public: true)
      assert result =~ "attribute :email, :string do"
      assert result =~ "public? true"
    end

    test "adds public? true to belongs_to relationship when public: true" do
      info =
        base_table_info(%{
          relationships: %{
            belongs_to: [
              %{
                field: :organization,
                table: "organizations",
                foreign_key: :organization_id,
                constraint_name: "users_org_fk",
                references: :id,
                on_update: :no_action,
                on_delete: :no_action
              }
            ],
            has_many: [],
            has_one: [],
            many_to_many: []
          }
        })

      result =
        AshResourceBuilder.build_resource(info, "MyApp.User",
          module_prefix: "MyApp",
          public: true
        )

      assert result =~ "belongs_to :organization, MyApp.Organization do"
      assert result =~ "public? true"
    end

    test "adds public? true to has_many relationship when public: true" do
      info =
        base_table_info(%{
          relationships: %{
            belongs_to: [],
            has_many: [
              %{field: :posts, table: "posts", foreign_key: :user_id, constraint_name: nil}
            ],
            has_one: [],
            many_to_many: []
          }
        })

      result =
        AshResourceBuilder.build_resource(info, "MyApp.User",
          module_prefix: "MyApp",
          public: true
        )

      assert result =~ "has_many :posts, MyApp.Post do"
      assert result =~ "public? true"
    end

    test "omits public? true by default" do
      result = AshResourceBuilder.build_resource(base_table_info(), "MyApp.User")
      refute result =~ "public? true"
    end
  end

  describe "build_resource/3 - check constraints" do
    test "emits check constraint comments in postgres block" do
      info =
        base_table_info(%{
          check_constraints: [
            %{constraint_name: "users_age_check", definition: "(age > 0)"}
          ]
        })

      result = AshResourceBuilder.build_resource(info, "MyApp.User")
      assert result =~ "users_age_check"
      assert result =~ "TODO: set message"
      assert result =~ "(age > 0)"
    end
  end
end
