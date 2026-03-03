defmodule ExSqlClient.Ecto.QueryTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  alias ExSqlClient.Ecto.Connection

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp sql(iodata), do: IO.iodata_to_binary(iodata)

  # Normalise an Ecto query through the planner so query.sources is populated.
  defp plan(query, operation \\ :all) do
    {query, _params, _key} = Ecto.Query.Planner.plan(query, operation, ExSqlClient.Ecto)
    {query, _} = Ecto.Query.Planner.normalize(query, operation, ExSqlClient.Ecto, 0)
    query
  end

  # ---------------------------------------------------------------------------
  # Schema for tests
  # ---------------------------------------------------------------------------

  defmodule User do
    use Ecto.Schema

    schema "users" do
      field(:name, :string)
      field(:email, :string)
      field(:age, :integer)
      field(:active, :boolean)
      timestamps()
    end
  end

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:title, :string)
      field(:body, :string)
      belongs_to(:user, User)
      timestamps()
    end
  end

  # ---------------------------------------------------------------------------
  # all/1 — SELECT
  # ---------------------------------------------------------------------------

  describe "all/1 SELECT" do
    test "simple select all fields" do
      query = from(u in User) |> select([u], u) |> plan()
      result = sql(Connection.all(query))

      assert result =~ "SELECT"
      assert result =~ "FROM [users]"
    end

    test "select specific field" do
      query = from(u in User, select: u.name) |> plan()
      result = sql(Connection.all(query))

      assert result =~ "[name]"
      assert result =~ "FROM [users]"
    end

    test "select with where clause" do
      query = from(u in User, where: u.age > 18, select: u.name) |> plan()
      result = sql(Connection.all(query))

      assert result =~ "WHERE"
      assert result =~ "[age]"
      assert result =~ " > "
    end

    test "select with parameterised where clause" do
      query = from(u in User, where: u.name == ^"Alice", select: u.name) |> plan()
      result = sql(Connection.all(query))

      assert result =~ "@1"
      assert result =~ "WHERE"
    end

    test "TOP(n) for limit without offset" do
      query = from(u in User, limit: 10, select: u.name) |> plan()
      result = sql(Connection.all(query))

      assert result =~ "TOP(10)"
      refute result =~ "OFFSET"
    end

    test "OFFSET…FETCH for limit with offset" do
      query = from(u in User, order_by: u.id, limit: 10, offset: 5, select: u.name) |> plan()
      result = sql(Connection.all(query))

      refute result =~ "TOP("
      assert result =~ "OFFSET 5 ROW"
      assert result =~ "FETCH NEXT 10 ROWS ONLY"
    end

    test "order_by asc" do
      query = from(u in User, order_by: u.name, select: u.name) |> plan()
      result = sql(Connection.all(query))

      assert result =~ "ORDER BY"
      assert result =~ "[name]"
    end

    test "order_by desc" do
      query = from(u in User, order_by: [desc: u.name], select: u.name) |> plan()
      result = sql(Connection.all(query))

      assert result =~ "ORDER BY"
      assert result =~ "[name] DESC"
    end

    test "inner join" do
      query =
        from(u in User,
          join: p in Post,
          on: p.user_id == u.id,
          select: u.name
        )
        |> plan()

      result = sql(Connection.all(query))

      assert result =~ "INNER JOIN [posts]"
      assert result =~ "ON"
    end

    test "left join" do
      query =
        from(u in User,
          left_join: p in Post,
          on: p.user_id == u.id,
          select: u.name
        )
        |> plan()

      result = sql(Connection.all(query))

      assert result =~ "LEFT OUTER JOIN [posts]"
    end

    test "group_by" do
      query = from(u in User, group_by: u.age, select: u.age) |> plan()
      result = sql(Connection.all(query))

      assert result =~ "GROUP BY"
      assert result =~ "[age]"
    end

    test "having" do
      query =
        from(u in User,
          group_by: u.age,
          having: count(u.id) > 5,
          select: u.age
        )
        |> plan()

      result = sql(Connection.all(query))

      assert result =~ "HAVING"
      assert result =~ "count("
    end

    test "DISTINCT" do
      query = from(u in User, distinct: true, select: u.name) |> plan()
      result = sql(Connection.all(query))

      assert result =~ "DISTINCT"
    end

    test "identifier quoting uses brackets" do
      query = from(u in User, select: u.name) |> plan()
      result = sql(Connection.all(query))

      assert result =~ "[users]"
      assert result =~ "[name]"
    end

    test "error when offset without order_by" do
      query = from(u in User, limit: 10, offset: 5, select: u.name) |> plan()

      assert_raise Ecto.QueryError, ~r/ORDER BY is mandatory/, fn ->
        Connection.all(query)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # insert/7
  # ---------------------------------------------------------------------------

  describe "insert/7" do
    test "basic insert with OUTPUT INSERTED" do
      result =
        sql(
          Connection.insert("dbo", "users", [:name, :email], [[:name, :email]], {:raise, [], []}, [
            :id
          ], [])
        )

      assert result =~ "INSERT INTO [dbo].[users]"
      assert result =~ "([name],[email])"
      assert result =~ "OUTPUT INSERTED.[id]"
      assert result =~ "VALUES"
      assert result =~ "@1"
      assert result =~ "@2"
    end

    test "insert without returning" do
      result =
        sql(
          Connection.insert(nil, "users", [:name], [[:name]], {:raise, [], []}, [], [])
        )

      assert result =~ "INSERT INTO [users]"
      refute result =~ "OUTPUT"
      assert result =~ "@1"
    end

    test "insert DEFAULT VALUES when no header" do
      result = sql(Connection.insert(nil, "users", [], [], {:raise, [], []}, [:id], []))

      assert result =~ "DEFAULT VALUES"
      assert result =~ "OUTPUT INSERTED.[id]"
    end
  end

  # ---------------------------------------------------------------------------
  # update/5
  # ---------------------------------------------------------------------------

  describe "update/5" do
    test "basic update" do
      result = sql(Connection.update(nil, "users", [:name, :email], [:id], []))

      assert result =~ "UPDATE [users]"
      assert result =~ "SET"
      assert result =~ "[name] = @1"
      assert result =~ "[email] = @2"
      assert result =~ "WHERE [id] = @3"
    end

    test "update with OUTPUT INSERTED" do
      result = sql(Connection.update(nil, "users", [:name], [:id], [:name]))

      assert result =~ "OUTPUT INSERTED.[name]"
    end

    test "update with nil filter (IS NULL)" do
      result = sql(Connection.update(nil, "users", [:name], [{:id, nil}], []))

      assert result =~ "[id] IS NULL"
    end
  end

  # ---------------------------------------------------------------------------
  # delete/4
  # ---------------------------------------------------------------------------

  describe "delete/4" do
    test "basic delete" do
      result = sql(Connection.delete(nil, "users", [:id], []))

      assert result =~ "DELETE FROM [users]"
      assert result =~ "WHERE [id] = @1"
    end

    test "delete with OUTPUT DELETED" do
      result = sql(Connection.delete(nil, "users", [:id], [:id, :name]))

      assert result =~ "OUTPUT DELETED.[id]"
      assert result =~ "DELETED.[name]"
    end

    test "delete with nil filter (IS NULL)" do
      result = sql(Connection.delete(nil, "users", [{:id, nil}], []))

      assert result =~ "[id] IS NULL"
    end
  end

  # ---------------------------------------------------------------------------
  # update_all/1
  # ---------------------------------------------------------------------------

  describe "update_all/1" do
    test "basic update_all" do
      query = from(u in User, update: [set: [name: "Bob"]]) |> plan(:update_all)
      result = sql(Connection.update_all(query))

      assert result =~ "UPDATE"
      assert result =~ "SET"
      assert result =~ "[name]"
      assert result =~ "FROM [users]"
    end

    test "update_all with where clause" do
      query =
        from(u in User, where: u.active == true, update: [set: [name: "Bob"]])
        |> plan(:update_all)

      result = sql(Connection.update_all(query))

      assert result =~ "WHERE"
    end
  end

  # ---------------------------------------------------------------------------
  # delete_all/1
  # ---------------------------------------------------------------------------

  describe "delete_all/1" do
    test "basic delete_all" do
      query = from(u in User) |> plan(:delete_all)
      result = sql(Connection.delete_all(query))

      assert result =~ "DELETE"
      assert result =~ "FROM [users]"
    end

    test "delete_all with where clause" do
      query = from(u in User, where: u.age < 18) |> plan(:delete_all)
      result = sql(Connection.delete_all(query))

      assert result =~ "WHERE"
      assert result =~ "[age]"
    end
  end

  # ---------------------------------------------------------------------------
  # table_exists_query/1
  # ---------------------------------------------------------------------------

  test "table_exists_query/1" do
    {sql_str, params} = Connection.table_exists_query("users")

    assert sql_str =~ "sys.tables"
    assert sql_str =~ "@1"
    assert params == ["users"]
  end
end
