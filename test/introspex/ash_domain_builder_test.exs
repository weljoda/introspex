defmodule Introspex.AshDomainBuilderTest do
  use ExUnit.Case, async: true

  alias Introspex.AshDomainBuilder

  defp schemas do
    [
      %{
        module_name: "User",
        singular_name: "user",
        plural_name: "users",
        table_name: "users",
        table_type: :table
      },
      %{
        module_name: "Profile",
        singular_name: "profile",
        plural_name: "profiles",
        table_name: "profiles",
        table_type: :table
      }
    ]
  end

  describe "build_domain/3" do
    test "emits use Ash.Domain" do
      result = AshDomainBuilder.build_domain("Accounts", schemas(), app_name: "MyApp")
      assert result =~ "use Ash.Domain"
    end

    test "emits correct full module name" do
      result = AshDomainBuilder.build_domain("Accounts", schemas(), app_name: "MyApp")
      assert result =~ "defmodule MyApp.Accounts do"
    end

    test "registers each resource" do
      result = AshDomainBuilder.build_domain("Accounts", schemas(), app_name: "MyApp")
      assert result =~ "resource MyApp.Accounts.User"
      assert result =~ "resource MyApp.Accounts.Profile"
    end

    test "emits resources block" do
      result = AshDomainBuilder.build_domain("Accounts", schemas(), app_name: "MyApp")
      assert result =~ "resources do"
    end

    test "includes path segments in module name when :path is provided" do
      result =
        AshDomainBuilder.build_domain("Accounts", schemas(),
          app_name: "MyApp",
          path: "core/internal"
        )

      assert result =~ "defmodule MyApp.Core.Internal.Accounts do"
      assert result =~ "resource MyApp.Core.Internal.Accounts.User"
    end

    test "handles empty schema list" do
      result = AshDomainBuilder.build_domain("Accounts", [], app_name: "MyApp")
      assert result =~ "defmodule MyApp.Accounts do"
      assert result =~ "resources do"
    end

    test "camelizes domain name" do
      result = AshDomainBuilder.build_domain("BlogPosts", schemas(), app_name: "MyApp")
      assert result =~ "defmodule MyApp.BlogPosts do"
    end
  end
end
