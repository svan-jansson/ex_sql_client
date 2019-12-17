defmodule ExSqlClient.Query do
  defstruct [:statement]

  defimpl DBConnection.Query, for: ExSqlClient.Query do
    def parse(query, _), do: query
    def describe(query, _), do: query
    def encode(_query, params, _), do: params
    def decode(_, result, _opts), do: result
  end
end
