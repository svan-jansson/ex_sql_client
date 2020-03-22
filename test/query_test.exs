defmodule QueryTest do
  use ExUnit.Case

  setup_all do
    connection_string =
      "Server=localhost; MultipleActiveResultSets=true; User Id=sa; Password=InsecurePassword123"

    {:ok, conn} = ExSqlClient.start_link(connection_string: connection_string)

    {:ok, _} =
      ExSqlClient.query(conn, """
          IF NOT EXISTS (SELECT * from sys.databases WHERE name = 'testing') BEGIN
              CREATE DATABASE [testing]
          END
      """)

    {:ok, _} =
      ExSqlClient.query(conn, """
         USE [testing]

         IF (NOT EXISTS (SELECT * 
                   FROM INFORMATION_SCHEMA.TABLES 
                   WHERE TABLE_SCHEMA = 'dbo' 
                   AND  TABLE_NAME = 'records'))
          BEGIN
              CREATE TABLE [dbo].[records] (
                  [id] int IDENTITY(1,1) PRIMARY KEY,
                  [timestamp] datetime NOT NULL,
                  [data] nvarchar(255)
              )
          END
      """)

    {:ok, _} = ExSqlClient.query(conn, "DELETE FROM [records]")

    {:ok, %{conn: conn}}
  end

  @tag :integration
  test "can insert and select multiple rows", %{conn: conn} do
    record_count = 100

    for i <- 1..record_count do
      {:ok, _} =
        ExSqlClient.query(
          conn,
          "INSERT INTO [records] ([timestamp], [data]) VALUES(@timestamp, @data)",
          %{
            timestamp: DateTime.utc_now(),
            data: "Record #{i}"
          }
        )
    end

    {:ok, records} = ExSqlClient.query(conn, "SELECT * FROM [records]")

    assert Enum.count(records) == record_count
  end
end
