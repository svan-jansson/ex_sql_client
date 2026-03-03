defmodule ExSqlClient.EctoAdapterTest do
  use ExUnit.Case

  # ---------------------------------------------------------------------------
  # Repo + Schema setup
  # ---------------------------------------------------------------------------

  defmodule TestRepo do
    use Ecto.Repo,
      otp_app: :ex_sql_client,
      adapter: ExSqlClient.Ecto
  end

  defmodule User do
    use Ecto.Schema

    schema "ecto_users" do
      field(:name, :string)
      field(:email, :string)
      field(:age, :integer)
      field(:active, :boolean)
    end
  end

  # ---------------------------------------------------------------------------
  # setup_all: start repo, create test table
  # ---------------------------------------------------------------------------

  setup_all do
    connection_string = Application.fetch_env!(:ex_sql_client, :test_connection_string)

    start_supervised!(
      {TestRepo, [connection_string: connection_string, pool_size: 2]}
    )

    # Create test table (idempotent)
    TestRepo.query!("""
      IF NOT EXISTS (
        SELECT * FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_NAME = 'ecto_users'
      )
      BEGIN
        CREATE TABLE [dbo].[ecto_users] (
          [id]     INT IDENTITY(1,1) PRIMARY KEY,
          [name]   NVARCHAR(255),
          [email]  NVARCHAR(255) UNIQUE,
          [age]    INT,
          [active] BIT
        )
      END
    """)

    :ok
  end

  # Clean table before each test
  setup do
    TestRepo.delete_all(User)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  @tag :integration
  test "Repo.query!/2 raw SQL works" do
    result = TestRepo.query!("SELECT 1 AS [one]")
    assert result.num_rows == 1
    assert result.columns == ["one"]
    assert result.rows == [[1]]
  end

  @tag :integration
  test "Repo.insert/2 and Repo.all/1" do
    assert {:ok, user} =
             TestRepo.insert(%User{name: "Alice", email: "alice@example.com", age: 30, active: true})

    assert user.id != nil
    assert user.name == "Alice"

    users = TestRepo.all(User)
    assert length(users) == 1
    assert hd(users).name == "Alice"
  end

  @tag :integration
  test "Repo.get/2" do
    {:ok, user} = TestRepo.insert(%User{name: "Bob", email: "bob@example.com", age: 25, active: false})
    found = TestRepo.get(User, user.id)

    assert found != nil
    assert found.name == "Bob"
  end

  @tag :integration
  test "Repo.update/2" do
    {:ok, user} = TestRepo.insert(%User{name: "Charlie", email: "charlie@example.com", age: 20, active: true})

    changeset = Ecto.Changeset.change(user, name: "Charles")
    assert {:ok, updated} = TestRepo.update(changeset)
    assert updated.name == "Charles"

    found = TestRepo.get!(User, user.id)
    assert found.name == "Charles"
  end

  @tag :integration
  test "Repo.delete/1" do
    {:ok, user} = TestRepo.insert(%User{name: "Dave", email: "dave@example.com", age: 40, active: false})

    assert {:ok, _} = TestRepo.delete(user)
    assert TestRepo.get(User, user.id) == nil
  end

  @tag :integration
  test "Repo.all/1 with where clause" do
    TestRepo.insert!(%User{name: "Eve", email: "eve@example.com", age: 22, active: true})
    TestRepo.insert!(%User{name: "Frank", email: "frank@example.com", age: 17, active: false})

    import Ecto.Query
    adults = TestRepo.all(from(u in User, where: u.age >= 18))
    assert length(adults) == 1
    assert hd(adults).name == "Eve"
  end

  @tag :integration
  test "Repo.update_all/2" do
    TestRepo.insert!(%User{name: "Grace", email: "grace@example.com", age: 25, active: false})

    import Ecto.Query
    {1, _} = TestRepo.update_all(from(u in User, where: u.name == "Grace"), set: [active: true])

    found = TestRepo.one!(from(u in User, where: u.name == "Grace"))
    assert found.active == true
  end

  @tag :integration
  test "Repo.delete_all/1 with where" do
    TestRepo.insert!(%User{name: "Heidi", email: "heidi@example.com", age: 30, active: false})
    TestRepo.insert!(%User{name: "Ivan", email: "ivan@example.com", age: 35, active: true})

    import Ecto.Query
    {1, _} = TestRepo.delete_all(from(u in User, where: u.active == false))

    remaining = TestRepo.all(User)
    assert length(remaining) == 1
    assert hd(remaining).name == "Ivan"
  end

  @tag :integration
  test "Repo.transaction/1 commit" do
    result =
      TestRepo.transaction(fn ->
        TestRepo.insert!(%User{name: "Judy", email: "judy@example.com", age: 28, active: true})
        :committed
      end)

    assert result == {:ok, :committed}
    assert TestRepo.aggregate(User, :count) == 1
  end

  @tag :integration
  test "Repo.transaction/1 rollback" do
    result =
      TestRepo.transaction(fn ->
        TestRepo.insert!(%User{name: "Karl", email: "karl@example.com", age: 33, active: true})
        TestRepo.rollback(:oops)
      end)

    assert result == {:error, :oops}
    assert TestRepo.aggregate(User, :count) == 0
  end

  @tag :integration
  test "boolean BIT round-trip" do
    TestRepo.insert!(%User{name: "Laura", email: "laura@example.com", age: 25, active: true})
    TestRepo.insert!(%User{name: "Mallory", email: "mallory@example.com", age: 25, active: false})

    import Ecto.Query
    actives = TestRepo.all(from(u in User, where: u.active == true))
    assert length(actives) == 1
    assert hd(actives).active == true
  end
end
