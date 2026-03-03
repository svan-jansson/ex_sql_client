if Code.ensure_loaded?(Ecto.Adapters.SQL.Connection) do
defmodule ExSqlClient.Ecto.Connection do
  @moduledoc false

  @behaviour Ecto.Adapters.SQL.Connection

  alias ExSqlClient.Query
  alias Ecto.Query.Tagged

  @parent_as __MODULE__
  alias Ecto.Query, as: EctoQuery
  alias Ecto.Query.{BooleanExpr, ByExpr, JoinExpr, QueryExpr, WithExpr}

  # ---------------------------------------------------------------------------
  # Execution callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def child_spec(opts) do
    DBConnection.child_spec(ExSqlClient.Protocol, opts)
  end

  @impl true
  def prepare_execute(conn, _name, sql, params, opts) do
    query = %Query{statement: IO.iodata_to_binary(sql)}
    encoded = encode_params(params)
    col_order = column_order_from_sql(query.statement)

    case DBConnection.prepare_execute(conn, query, encoded, opts) do
      {:ok, q, result} -> {:ok, q, normalize_result(result, col_order)}
      {:error, _} = err -> err
    end
  end

  @impl true
  def execute(conn, %Query{} = query, params, opts) do
    encoded = encode_params(params)
    col_order = column_order_from_sql(query.statement)

    case DBConnection.execute(conn, query, encoded, opts) do
      {:ok, q, result} -> {:ok, q, normalize_result(result, col_order)}
      {:error, _} = err -> err
    end
  end

  def execute(conn, sql, params, opts) when is_binary(sql) or is_list(sql) do
    query = %Query{statement: IO.iodata_to_binary(sql)}
    encoded = encode_params(params)
    col_order = column_order_from_sql(query.statement)

    case DBConnection.prepare_execute(conn, query, encoded, opts) do
      {:ok, q, result} -> {:ok, q, normalize_result(result, col_order)}
      {:error, _} = err -> err
    end
  end

  @impl true
  def query(conn, sql, params, opts) do
    query = %Query{statement: IO.iodata_to_binary(sql)}
    encoded = encode_params(params)
    col_order = column_order_from_sql(query.statement)

    case DBConnection.prepare_execute(conn, query, encoded, opts) do
      {:ok, _q, result} -> {:ok, normalize_result(result, col_order)}
      {:error, _} = err -> err
    end
  end

  @impl true
  def query_many(_conn, _sql, _params, _opts) do
    raise RuntimeError, "query_many/4 is not supported by ExSqlClient.Ecto"
  end

  @impl true
  def stream(_conn, _sql, _params, _opts) do
    raise RuntimeError,
          "Repo.stream/2 is not supported by ExSqlClient.Ecto — cursors are not implemented"
  end

  @impl true
  def to_constraints(%DBConnection.ConnectionError{message: msg}, _opts) do
    cond do
      # Unique key violation (duplicate key)
      msg =~ "2601" or msg =~ "2627" ->
        [unique: extract_constraint_name(msg)]

      # Foreign key violation
      msg =~ "547" ->
        [foreign_key: extract_constraint_name(msg)]

      true ->
        []
    end
  end

  def to_constraints(_, _opts), do: []

  @impl true
  def explain_query(conn, sql, params, opts) do
    explain_sql =
      "SET STATISTICS IO ON; SET STATISTICS TIME ON; #{sql}; SET STATISTICS IO OFF; SET STATISTICS TIME OFF;"

    query(conn, explain_sql, params, opts)
  end

  @impl true
  def execute_ddl(_command) do
    raise RuntimeError,
          "DDL/migrations are not supported by ExSqlClient.Ecto. " <>
            "Use ExSqlClient.query/4 directly for DDL statements."
  end

  @impl true
  def ddl_logs(_result), do: []

  @impl true
  def table_exists_query(table) do
    {"SELECT 1 FROM sys.tables WHERE [name] = @1", [table]}
  end

  # ---------------------------------------------------------------------------
  # Result normalisation
  # ---------------------------------------------------------------------------

  # Synthetic row injected by the .NET side for DML without an OUTPUT clause.
  # The C# layer sets this when ExecuteReader returns no rows but RecordsAffected >= 0.
  defp normalize_result([%{"__rows_affected__" => n}], _col_order) do
    %{columns: nil, rows: nil, num_rows: n}
  end

  defp normalize_result(nil, _col_order), do: %{columns: nil, rows: [], num_rows: 0}
  # For an empty result (SELECT with 0 rows or DDL), return an empty row list
  # so that Ecto's Enum.map/2 over rows succeeds.  DML without OUTPUT never
  # reaches here after the C# __rows_affected__ injection.
  defp normalize_result([], col_order), do: %{columns: col_order, rows: [], num_rows: 0}

  defp normalize_result(rows, col_order) when is_list(rows) do
    raw_keys = rows |> List.first() |> Map.keys()

    # Use the SQL-derived column order when it covers exactly the same set of
    # keys.  Elixir maps (small maps ≤ 32 keys) sort string keys alphabetically,
    # which loses the SELECT order Ecto relies on for positional row loading.
    ordered_keys =
      if col_order && length(col_order) == length(raw_keys) &&
           Enum.sort(col_order) == Enum.sort(raw_keys) do
        col_order
      else
        raw_keys
      end

    normalized = Enum.map(rows, fn row -> Enum.map(ordered_keys, &Map.get(row, &1)) end)
    %{columns: ordered_keys, rows: normalized, num_rows: length(normalized)}
  end

  # ---------------------------------------------------------------------------
  # Column-order extraction from SQL
  # ---------------------------------------------------------------------------

  # Returns the ordered list of result-column names as the SQL SELECT (or OUTPUT)
  # clause prescribes them, so that normalize_result/2 can re-key the unordered
  # Elixir maps returned by Netler/MessagePack into the correct positional order.
  defp column_order_from_sql(sql) when is_binary(sql) do
    # OUTPUT clause takes precedence (INSERT/UPDATE/DELETE with RETURNING).
    # Match the entire OUTPUT ... sequence and then scan within it.
    case Regex.run(
           ~r/OUTPUT\s+((?:(?:INSERTED|DELETED)\.\[[^\]]+\](?:,\s*)?)+)/i,
           sql
         ) do
      [_, output_clause] ->
        Regex.scan(~r/(?:INSERTED|DELETED)\.\[([^\]]+)\]/, output_clause)
        |> Enum.map(fn [_, col] -> col end)

      nil ->
        # SELECT … FROM: capture the projection list and extract the trailing
        # [identifier] of each comma-separated item (handles "t0.[col]" and
        # "expr AS [alias]").
        case Regex.run(
               ~r/\ASELECT\s+(?:DISTINCT\s+)?(?:TOP\([^)]+\)\s+)?(.+?)\s+FROM\s/is,
               sql
             ) do
          [_, select_clause] ->
            select_clause
            |> split_select_list()
            |> Enum.map(&extract_bracketed_name/1)
            |> Enum.reject(&is_nil/1)

          _ ->
            nil
        end
    end
  end

  defp column_order_from_sql(_), do: nil

  defp extract_bracketed_name(item) do
    case Regex.run(~r/\[([^\]]+)\]\s*\z/, String.trim(item)) do
      [_, name] -> name
      _ -> nil
    end
  end

  # Split a SELECT projection list on commas that are NOT inside parentheses.
  defp split_select_list(str) do
    {items, current, _depth} =
      String.graphemes(str)
      |> Enum.reduce({[], "", 0}, fn
        "(", {items, current, depth} -> {items, current <> "(", depth + 1}
        ")", {items, current, depth} -> {items, current <> ")", depth - 1}
        ",", {items, current, 0} -> {[current | items], "", 0}
        char, {items, current, depth} -> {items, current <> char, depth}
      end)

    Enum.reverse([current | items])
  end

  # ---------------------------------------------------------------------------
  # Parameter encoding
  # ---------------------------------------------------------------------------

  # Ecto passes params as positional list [v1, v2, ...].
  # The .NET side expects named params: @1, @2, ... → %{"1" => v1, "2" => v2, ...}
  defp encode_params([]), do: %{}

  defp encode_params(params) when is_list(params) do
    params
    |> Enum.with_index(1)
    |> Map.new(fn {val, idx} -> {Integer.to_string(idx), encode_value(val)} end)
  end

  defp encode_params(%{} = params), do: params

  defp encode_value(nil), do: nil
  defp encode_value(true), do: 1
  defp encode_value(false), do: 0
  defp encode_value(%{} = map), do: map
  defp encode_value(v), do: v

  defp extract_constraint_name(msg) do
    case Regex.run(~r/'([^']+)'/, msg) do
      [_, name] -> name
      _ -> "unknown_constraint"
    end
  end

  # ---------------------------------------------------------------------------
  # SQL generation  (MSSQL / SQL Server dialect)
  # Based on Ecto.Adapters.Tds.Connection, Apache 2.0 licensed.
  # Key MSSQL differences: TOP(n), OFFSET…FETCH, OUTPUT INSERTED/DELETED,
  # [bracket] identifiers, @1 @2 … parameter markers.
  # ---------------------------------------------------------------------------

  binary_ops = [
    ==: " = ",
    !=: " <> ",
    <=: " <= ",
    >=: " >= ",
    <: " < ",
    >: " > ",
    +: " + ",
    -: " - ",
    *: " * ",
    /: " / ",
    and: " AND ",
    or: " OR ",
    ilike: " LIKE ",
    like: " LIKE "
  ]

  @binary_ops Keyword.keys(binary_ops)

  Enum.map(binary_ops, fn {op, str} ->
    defp handle_call(unquote(op), 2), do: {:binary_op, unquote(str)}
  end)

  defp handle_call(fun, _arity), do: {:fun, Atom.to_string(fun)}

  @impl true
  def all(query, as_prefix \\ []) do
    sources = create_names(query, as_prefix)

    cte = cte(query, sources)
    from = from(query, sources)
    select = select(query, sources)
    join = join(query, sources)
    where = where(query, sources)
    group_by = group_by(query, sources)
    having = having(query, sources)
    combinations = combinations(query, as_prefix)
    order_by = order_by(query, sources)
    offset = offset(query, sources)
    lock = lock(query, sources)

    if query.offset != nil and query.order_bys == [],
      do: error!(query, "ORDER BY is mandatory when OFFSET is set")

    [cte, select, from, join, where, group_by, having, combinations, order_by, lock | offset]
  end

  @impl true
  def update_all(query) do
    sources = create_names(query, [])
    cte = cte(query, sources)
    {table, name, _model} = elem(sources, 0)

    fields = update_fields(query, sources)
    from = " FROM #{table} AS #{name}"
    join = join(query, sources)
    where = where(query, sources)
    lock = lock(query, sources)

    [
      cte,
      "UPDATE ",
      name,
      " SET ",
      fields,
      returning(query, 0, "INSERTED"),
      from,
      join,
      where | lock
    ]
  end

  @impl true
  def delete_all(query) do
    sources = create_names(query, [])
    cte = cte(query, sources)
    {table, name, _model} = elem(sources, 0)

    delete = "DELETE #{name}"
    from = " FROM #{table} AS #{name}"
    join = join(query, sources)
    where = where(query, sources)
    lock = lock(query, sources)

    [cte, delete, returning(query, 0, "DELETED"), from, join, where | lock]
  end

  @impl true
  def insert(prefix, table, header, rows, on_conflict, returning, placeholders) do
    counter_offset = length(placeholders) + 1
    [] = on_conflict(on_conflict, header)
    returning = returning(returning, "INSERTED")

    values =
      if header == [] do
        [returning, " DEFAULT VALUES"]
      else
        [
          ?\s,
          ?(,
          quote_names(header),
          ?),
          returning
          | insert_all(rows, counter_offset)
        ]
      end

    ["INSERT INTO ", quote_table(prefix, table), values]
  end

  defp on_conflict({:raise, _, []}, _header), do: []

  defp on_conflict({_, _, _}, _header) do
    error!(nil, "ExSqlClient.Ecto adapter supports only on_conflict: :raise")
  end

  defp insert_all(%EctoQuery{} = query, _counter) do
    [?\s, all(query)]
  end

  defp insert_all(rows, counter) do
    sql =
      intersperse_reduce(rows, ",", counter, fn row, counter ->
        {row, counter} = insert_each(row, counter)
        {[?(, row, ?)], counter}
      end)
      |> elem(0)

    [" VALUES " | sql]
  end

  defp insert_each(values, counter) do
    intersperse_reduce(values, ", ", counter, fn
      nil, counter ->
        {"DEFAULT", counter}

      {%EctoQuery{} = query, params_counter}, counter ->
        {[?(, all(query), ?)], counter + params_counter}

      {:placeholder, placeholder_index}, counter ->
        {[?@ | placeholder_index], counter}

      _, counter ->
        {[?@ | Integer.to_string(counter)], counter + 1}
    end)
  end

  @impl true
  def update(prefix, table, fields, filters, returning) do
    {fields, count} =
      intersperse_reduce(fields, ", ", 1, fn field, acc ->
        {[quote_name(field), " = @", Integer.to_string(acc)], acc + 1}
      end)

    {filters, _count} =
      intersperse_reduce(filters, " AND ", count, fn
        {field, nil}, acc ->
          {[quote_name(field), " IS NULL"], acc}

        {field, _value}, acc ->
          {[quote_name(field), " = @", Integer.to_string(acc)], acc + 1}

        field, acc ->
          {[quote_name(field), " = @", Integer.to_string(acc)], acc + 1}
      end)

    [
      "UPDATE ",
      quote_table(prefix, table),
      " SET ",
      fields,
      returning(returning, "INSERTED"),
      " WHERE " | filters
    ]
  end

  @impl true
  def delete(prefix, table, filters, returning) do
    {filters, _} =
      intersperse_reduce(filters, " AND ", 1, fn
        {field, nil}, acc ->
          {[quote_name(field), " IS NULL"], acc}

        {field, _value}, acc ->
          {[quote_name(field), " = @", Integer.to_string(acc)], acc + 1}

        field, acc ->
          {[quote_name(field), " = @", Integer.to_string(acc)], acc + 1}
      end)

    [
      "DELETE FROM ",
      quote_table(prefix, table),
      returning(returning, "DELETED"),
      " WHERE " | filters
    ]
  end

  # ---------------------------------------------------------------------------
  # SELECT helpers
  # ---------------------------------------------------------------------------

  defp select(%{select: %{fields: fields}, distinct: distinct} = query, sources) do
    [
      "SELECT ",
      distinct(distinct, sources, query),
      limit(query, sources),
      select(fields, sources, query)
    ]
  end

  defp distinct(nil, _sources, _query), do: []
  defp distinct(%ByExpr{expr: true}, _sources, _query), do: "DISTINCT "
  defp distinct(%ByExpr{expr: false}, _sources, _query), do: []

  defp distinct(%ByExpr{expr: exprs}, _sources, query) when is_list(exprs) do
    error!(
      query,
      "DISTINCT with multiple columns is not supported by MSSQL. " <>
        "Please use distinct(true) if you need distinct resultset"
    )
  end

  defp select([], _sources, _query), do: "CAST(1 as bit)"

  defp select(fields, sources, query) do
    Enum.map_intersperse(fields, ", ", fn
      {:&, _, [idx]} ->
        case elem(sources, idx) do
          {nil, source, nil} ->
            error!(
              query,
              "ExSqlClient.Ecto does not support selecting all fields from fragment #{source}. " <>
                "Please specify exactly which fields you want to select"
            )

          {source, _, nil} ->
            error!(
              query,
              "ExSqlClient.Ecto does not support selecting all fields from #{source} without a schema. " <>
                "Please specify a schema or specify exactly which fields you want in projection"
            )

          {_, source, _} ->
            source
        end

      {key, value} ->
        [select_expr(value, sources, query), " AS ", quote_name(key)]

      value ->
        select_expr(value, sources, query)
    end)
  end

  defp select_expr({:not, _, [expr]}, sources, query) do
    [?~, ?(, select_expr(expr, sources, query), ?)]
  end

  defp select_expr(value, sources, query), do: expr(value, sources, query)

  defp from(%{from: %{source: source, hints: hints}} = query, sources) do
    {from, name} = get_source(query, sources, 0, source)
    [" FROM ", from, " AS ", name, hints(hints)]
  end

  # ---------------------------------------------------------------------------
  # CTE
  # ---------------------------------------------------------------------------

  defp cte(%{with_ctes: %WithExpr{queries: [_ | _] = queries}} = query, sources) do
    ctes = Enum.map_intersperse(queries, ", ", &cte_expr(&1, sources, query))
    ["WITH ", ctes, " "]
  end

  defp cte(%{with_ctes: _}, _), do: []

  defp cte_expr({_name, %{materialized: materialized}, _cte}, _sources, query)
       when is_boolean(materialized) do
    error!(query, "ExSqlClient.Ecto does not support materialized CTEs")
  end

  defp cte_expr({name, opts, cte}, sources, query) do
    operation_opt = Map.get(opts, :operation)

    [
      quote_name(name),
      cte_header(cte, query),
      " AS ",
      cte_query(cte, sources, query, operation_opt)
    ]
  end

  defp cte_header(%QueryExpr{}, query) do
    error!(query, "ExSqlClient.Ecto does not support fragment in CTE")
  end

  defp cte_header(%EctoQuery{select: %{fields: fields}} = query, _) do
    [
      " (",
      Enum.map_intersperse(fields, ",", fn
        {key, _} ->
          quote_name(key)

        other ->
          error!(
            query,
            "ExSqlClient.Ecto expected field name or alias in CTE header, instead got #{inspect(other)}"
          )
      end),
      ?)
    ]
  end

  defp cte_query(query, sources, parent_query, nil) do
    cte_query(query, sources, parent_query, :all)
  end

  defp cte_query(%EctoQuery{} = query, sources, parent_query, :all) do
    query = put_in(query.aliases[@parent_as], {parent_query, sources})
    [?(, all(query, subquery_as_prefix(sources)), ?)]
  end

  defp cte_query(%EctoQuery{} = query, _sources, _parent_query, operation) do
    error!(query, "ExSqlClient.Ecto does not support data-modifying CTEs (operation: #{operation})")
  end

  # ---------------------------------------------------------------------------
  # UPDATE fields
  # ---------------------------------------------------------------------------

  defp update_fields(%EctoQuery{updates: updates} = query, sources) do
    for(
      %{expr: expr} <- updates,
      {op, kw} <- expr,
      {key, value} <- kw,
      do: update_op(op, key, value, sources, query)
    )
    |> Enum.intersperse(", ")
  end

  defp update_op(:set, key, value, sources, query) do
    {_table, name, _model} = elem(sources, 0)
    [name, ?., quote_name(key), " = " | expr(value, sources, query)]
  end

  defp update_op(:inc, key, value, sources, query) do
    {_table, name, _model} = elem(sources, 0)
    quoted = quote_name(key)
    [name, ?., quoted, " = ", name, ?., quoted, " + " | expr(value, sources, query)]
  end

  defp update_op(command, _key, _value, _sources, query) do
    error!(query, "Unknown update operation #{inspect(command)} for ExSqlClient.Ecto")
  end

  # ---------------------------------------------------------------------------
  # JOIN
  # ---------------------------------------------------------------------------

  defp join(%{joins: []}, _sources), do: []

  defp join(%{joins: joins} = query, sources) do
    [
      ?\s,
      Enum.map_intersperse(joins, ?\s, fn
        %JoinExpr{on: %QueryExpr{expr: expr}, qual: qual, ix: ix, source: source, hints: hints} ->
          {join, name} = get_source(query, sources, ix, source)
          qual_text = join_qual(qual, query)
          join = join || ["(", expr(source, sources, query) | ")"]
          [qual_text, join, " AS ", name, hints(hints) | join_on(qual, expr, sources, query)]
      end)
    ]
  end

  defp join_on(:cross, true, _sources, _query), do: []
  defp join_on(:inner_lateral, true, _sources, _query), do: []
  defp join_on(:left_lateral, true, _sources, _query), do: []
  defp join_on(_qual, true, _sources, _query), do: [" ON 1 = 1"]
  defp join_on(_qual, expr, sources, query), do: [" ON " | expr(expr, sources, query)]

  defp join_qual(:inner, _), do: "INNER JOIN "
  defp join_qual(:left, _), do: "LEFT OUTER JOIN "
  defp join_qual(:right, _), do: "RIGHT OUTER JOIN "
  defp join_qual(:full, _), do: "FULL OUTER JOIN "
  defp join_qual(:cross, _), do: "CROSS JOIN "
  defp join_qual(:inner_lateral, _), do: "CROSS APPLY "
  defp join_qual(:left_lateral, _), do: "OUTER APPLY "

  defp join_qual(qual, query),
    do: error!(query, "join qualifier #{inspect(qual)} is not supported in ExSqlClient.Ecto")

  # ---------------------------------------------------------------------------
  # WHERE / HAVING
  # ---------------------------------------------------------------------------

  defp where(%EctoQuery{wheres: wheres} = query, sources) do
    boolean(" WHERE ", wheres, sources, query)
  end

  defp having(%EctoQuery{havings: havings} = query, sources) do
    boolean(" HAVING ", havings, sources, query)
  end

  defp group_by(%{group_bys: []}, _sources), do: []

  defp group_by(%{group_bys: group_bys} = query, sources) do
    [
      " GROUP BY "
      | Enum.map_intersperse(group_bys, ", ", fn %ByExpr{expr: expr} ->
          Enum.map_intersperse(expr, ", ", &top_level_expr(&1, sources, query))
        end)
    ]
  end

  defp order_by(%{order_bys: []}, _sources), do: []

  defp order_by(%{order_bys: order_bys} = query, sources) do
    [
      " ORDER BY "
      | Enum.map_intersperse(order_bys, ", ", fn %ByExpr{expr: expr} ->
          Enum.map_intersperse(expr, ", ", &order_by_expr(&1, sources, query))
        end)
    ]
  end

  defp order_by_expr({dir, expr}, sources, query) do
    str = top_level_expr(expr, sources, query)

    case dir do
      :asc -> str
      :desc -> [str | " DESC"]
      _ -> error!(query, "#{dir} is not supported in ORDER BY in MSSQL")
    end
  end

  # ---------------------------------------------------------------------------
  # LIMIT / OFFSET  (MSSQL: TOP(n) in SELECT; OFFSET…FETCH for pagination)
  # ---------------------------------------------------------------------------

  defp limit(%EctoQuery{limit: nil}, _sources), do: []

  defp limit(%EctoQuery{limit: %{with_ties: true}} = query, _sources) do
    error!(query, "ExSqlClient.Ecto does not support the :with_ties limit option")
  end

  defp limit(%EctoQuery{limit: %{expr: expr}} = query, sources) do
    case Map.get(query, :offset) do
      nil -> ["TOP(", expr(expr, sources, query), ") "]
      _ -> []
    end
  end

  defp offset(%{offset: nil}, _sources), do: []

  defp offset(%EctoQuery{offset: _, limit: nil} = query, _sources) do
    error!(query, "You must provide a limit while using an offset")
  end

  defp offset(%{offset: offset, limit: limit} = query, sources) do
    [
      " OFFSET ",
      expr(offset.expr, sources, query),
      " ROW",
      " FETCH NEXT ",
      expr(limit.expr, sources, query),
      " ROWS ONLY"
    ]
  end

  # ---------------------------------------------------------------------------
  # Hints / Lock / Combinations
  # ---------------------------------------------------------------------------

  defp hints([_ | _] = hints), do: [" WITH (", Enum.intersperse(hints, ", "), ?)]
  defp hints([]), do: []

  defp lock(%{lock: nil}, _sources), do: []
  defp lock(%{lock: binary}, _sources) when is_binary(binary), do: [" OPTION (", binary, ?)]
  defp lock(%{lock: expr} = query, sources), do: [" OPTION (", expr(expr, sources, query), ?)]

  defp combinations(%{combinations: combinations}, as_prefix) do
    Enum.map(combinations, fn
      {:union, query} -> [" UNION (", all(query, as_prefix), ")"]
      {:union_all, query} -> [" UNION ALL (", all(query, as_prefix), ")"]
      {:except, query} -> [" EXCEPT (", all(query, as_prefix), ")"]
      {:except_all, query} -> [" EXCEPT ALL (", all(query, as_prefix), ")"]
      {:intersect, query} -> [" INTERSECT (", all(query, as_prefix), ")"]
      {:intersect_all, query} -> [" INTERSECT ALL (", all(query, as_prefix), ")"]
    end)
  end

  # ---------------------------------------------------------------------------
  # Boolean expr builder
  # ---------------------------------------------------------------------------

  defp boolean(_name, [], _sources, _query), do: []

  defp boolean(name, [%{expr: expr, op: op} | query_exprs], sources, query) do
    [
      name
      | Enum.reduce(query_exprs, {op, paren_expr(expr, sources, query)}, fn
          %BooleanExpr{expr: expr, op: op}, {op, acc} ->
            {op, [acc, operator_to_boolean(op), paren_expr(expr, sources, query)]}

          %BooleanExpr{expr: expr, op: op}, {_, acc} ->
            {op, [?(, acc, ?), operator_to_boolean(op), paren_expr(expr, sources, query)]}
        end)
        |> elem(1)
    ]
  end

  defp operator_to_boolean(:and), do: " AND "
  defp operator_to_boolean(:or), do: " OR "

  defp parens_for_select([first_expr | _] = expr) do
    if is_binary(first_expr) and String.match?(first_expr, ~r/^\s*select\s/i) do
      [?(, expr, ?)]
    else
      expr
    end
  end

  defp paren_expr(true, _sources, _query), do: ["(1 = 1)"]
  defp paren_expr(false, _sources, _query), do: ["(1 = 0)"]
  defp paren_expr(expr, sources, query), do: [?(, expr(expr, sources, query), ?)]

  defp top_level_expr(%Ecto.SubQuery{query: query}, sources, parent_query) do
    combinations =
      Enum.map(query.combinations, fn {type, combo_query} ->
        {type, put_in(combo_query.aliases[@parent_as], {parent_query, sources})}
      end)

    query = put_in(query.combinations, combinations)
    query = put_in(query.aliases[@parent_as], {parent_query, sources})
    [all(query, subquery_as_prefix(sources))]
  end

  defp top_level_expr(other, sources, parent_query), do: expr(other, sources, parent_query)

  # ---------------------------------------------------------------------------
  # Expression compiler
  # ---------------------------------------------------------------------------

  # Parameter reference: {:^, [], [idx]} → @1, @2, …
  defp expr({:^, [], [idx]}, _sources, _query) do
    "@#{idx + 1}"
  end

  defp expr({{:., _, [{:parent_as, _, [as]}, field]}, _, []}, _sources, query)
       when is_atom(field) or is_binary(field) do
    {ix, sources} = get_parent_sources_ix(query, as)
    {_, name, _} = elem(sources, ix)
    [name, ?. | quote_name(field)]
  end

  defp expr({{:., _, [{:&, _, [idx]}, field]}, _, []}, sources, _query)
       when is_atom(field) or is_binary(field) do
    {_, name, _} = elem(sources, idx)
    [name, ?. | quote_name(field)]
  end

  defp expr({:&, _, [idx]}, sources, _query) do
    {_table, source, _schema} = elem(sources, idx)
    source
  end

  defp expr({:&, _, [idx, fields, _counter]}, sources, query) do
    {_table, name, schema} = elem(sources, idx)

    if is_nil(schema) and is_nil(fields) do
      error!(
        query,
        "ExSqlClient.Ecto requires a schema module when using selector #{inspect(name)} but " <>
          "none was given. Please specify a schema or specify exactly which fields you want."
      )
    end

    Enum.map_join(fields, ", ", &"#{name}.#{quote_name(&1)}")
  end

  defp expr({:in, _, [_left, []]}, _sources, _query), do: "0=1"

  defp expr({:in, _, [left, right]}, sources, query) when is_list(right) do
    args = Enum.map_join(right, ",", &expr(&1, sources, query))
    [expr(left, sources, query), " IN (", args | ")"]
  end

  defp expr({:in, _, [_, {:^, _, [_, 0]}]}, _sources, _query), do: "0=1"

  defp expr({:in, _, [left, {:^, _, [idx, length]}]}, sources, query) do
    args = list_param_to_args(idx, length)
    [expr(left, sources, query), " IN (", args | ")"]
  end

  defp expr({:in, _, [left, %Ecto.SubQuery{} = subquery]}, sources, query) do
    [expr(left, sources, query), " IN ", expr(subquery, sources, query)]
  end

  defp expr({:in, _, [left, right]}, sources, query) do
    [expr(left, sources, query), " = ANY(", expr(right, sources, query) | ")"]
  end

  defp expr({:is_nil, _, [arg]}, sources, query) do
    "#{expr(arg, sources, query)} IS NULL"
  end

  defp expr({:not, _, [expr]}, sources, query) do
    ["NOT (", expr(expr, sources, query) | ")"]
  end

  defp expr({:filter, _, _}, _sources, query) do
    error!(query, "ExSqlClient.Ecto does not support aggregate filters")
  end

  defp expr(%Ecto.SubQuery{} = subquery, sources, parent_query) do
    [?(, top_level_expr(subquery, sources, parent_query), ?)]
  end

  defp expr({:fragment, _, [kw]}, _sources, query) when is_list(kw) or tuple_size(kw) == 3 do
    error!(query, "ExSqlClient.Ecto does not support keyword or interpolated fragments")
  end

  defp expr({:fragment, _, parts}, sources, query) do
    Enum.map(parts, fn
      {:raw, part} -> part
      {:expr, expr} -> expr(expr, sources, query)
    end)
    |> parens_for_select()
  end

  defp expr({:values, _, [types, idx, num_rows]}, _, _query) do
    [?(, values_list(types, idx + 1, num_rows), ?)]
  end

  defp expr({:identifier, _, [literal]}, _sources, _query) do
    quote_name(literal)
  end

  defp expr({:constant, _, [literal]}, _sources, _query) when is_binary(literal) do
    [?', escape_string(literal), ?']
  end

  defp expr({:constant, _, [literal]}, _sources, _query) when is_number(literal) do
    [to_string(literal)]
  end

  defp expr({:splice, _, [{:^, _, [idx, length]}]}, _sources, _query) do
    list_param_to_args(idx, length)
  end

  defp expr({:selected_as, _, [name]}, _sources, _query) do
    [quote_name(name)]
  end

  defp expr({:datetime_add, _, [datetime, count, interval]}, sources, query) do
    [
      "DATEADD(",
      interval,
      ", ",
      interval_count(count, sources, query),
      ", CAST(",
      expr(datetime, sources, query),
      " AS datetime2(6)))"
    ]
  end

  defp expr({:date_add, _, [date, count, interval]}, sources, query) do
    [
      "CAST(DATEADD(",
      interval,
      ", ",
      interval_count(count, sources, query),
      ", CAST(",
      expr(date, sources, query),
      " AS datetime2(6))" | ") AS date)"
    ]
  end

  defp expr({:count, _, []}, _sources, _query), do: "count(*)"

  defp expr({:json_extract_path, _, _}, _sources, query) do
    error!(
      query,
      "ExSqlClient.Ecto does not support json_extract_path, use fragment with JSON_VALUE/JSON_QUERY"
    )
  end

  defp expr({fun, _, args}, sources, query) when is_atom(fun) and is_list(args) do
    {modifier, args} =
      case args do
        [rest, :distinct] -> {"DISTINCT ", [rest]}
        _ -> {"", args}
      end

    case handle_call(fun, length(args)) do
      {:binary_op, op} ->
        [left, right] = args
        [op_to_binary(left, sources, query), op | op_to_binary(right, sources, query)]

      {:fun, fun} ->
        [
          fun,
          ?(,
          modifier,
          Enum.map_intersperse(args, ", ", &top_level_expr(&1, sources, query)),
          ?)
        ]
    end
  end

  defp expr(list, sources, query) when is_list(list) do
    Enum.map_join(list, ", ", &expr(&1, sources, query))
  end

  defp expr(string, _sources, _query) when is_binary(string) do
    "N'#{escape_string(string)}'"
  end

  defp expr(%Decimal{exp: exp} = decimal, _sources, _query) do
    [
      "CAST(",
      Decimal.to_string(decimal, :normal),
      " as decimal(38, #{abs(exp)})",
      ?)
    ]
  end

  defp expr(%Tagged{value: binary, type: :binary}, _sources, _query) when is_binary(binary) do
    hex = Base.encode16(binary, case: :lower)
    "0x#{hex}"
  end

  defp expr(%Tagged{value: binary, type: :uuid}, _sources, _query) when is_binary(binary) do
    binary
  end

  defp expr(%Tagged{value: other, type: :integer}, sources, query) do
    "CAST(#{expr(other, sources, query)} AS bigint)"
  end

  defp expr(%Tagged{value: other, type: type}, sources, query) do
    "CAST(#{expr(other, sources, query)} AS #{column_type(type, [])})"
  end

  defp expr(nil, _sources, _query), do: "NULL"
  defp expr(true, _sources, _query), do: "1"
  defp expr(false, _sources, _query), do: "0"

  defp expr(literal, _sources, _query) when is_integer(literal) do
    Integer.to_string(literal)
  end

  defp expr(literal, _sources, _query) when is_float(literal) do
    Float.to_string(literal)
  end

  defp expr(field, _sources, query) do
    error!(query, "unsupported MSSQL expression: `#{inspect(field)}`")
  end

  defp values_list(types, idx, num_rows) do
    rows = :lists.seq(1, num_rows, 1)

    [
      "VALUES ",
      intersperse_reduce(rows, ?,, idx, fn _, idx ->
        {value, idx} = values_expr(types, idx)
        {[?(, value, ?)], idx}
      end)
      |> elem(0)
    ]
  end

  defp values_expr(types, idx) do
    intersperse_reduce(types, ?,, idx, fn {_field, type}, idx ->
      {["CAST(", ?@, Integer.to_string(idx), " AS ", column_type(type, []), ?)], idx + 1}
    end)
  end

  defp op_to_binary({op, _, [_, _]} = expr, sources, query) when op in @binary_ops do
    paren_expr(expr, sources, query)
  end

  defp op_to_binary({:is_nil, _, [_]} = expr, sources, query) do
    paren_expr(expr, sources, query)
  end

  defp op_to_binary(expr, sources, query), do: expr(expr, sources, query)

  defp interval_count(count, _sources, _query) when is_integer(count) do
    Integer.to_string(count)
  end

  defp interval_count(count, _sources, _query) when is_float(count) do
    :erlang.float_to_binary(count, [:compact, decimals: 16])
  end

  defp interval_count(count, sources, query), do: expr(count, sources, query)

  # ---------------------------------------------------------------------------
  # OUTPUT clause (MSSQL RETURNING equivalent)
  # ---------------------------------------------------------------------------

  defp returning([], _verb), do: []

  defp returning(returning, verb) when is_list(returning) do
    [" OUTPUT ", Enum.map_intersperse(returning, ", ", &[verb, ?., quote_name(&1)])]
  end

  defp returning(%{select: nil}, _, _), do: []

  defp returning(%{select: %{fields: fields}} = query, idx, verb) do
    [
      " OUTPUT "
      | Enum.map_intersperse(fields, ", ", fn
          {{:., _, [{:&, _, [^idx]}, key]}, _, _} -> [verb, ?., quote_name(key)]
          _ -> error!(query, "MSSQL can only return table #{verb} columns")
        end)
    ]
  end

  # ---------------------------------------------------------------------------
  # Source name generation
  # ---------------------------------------------------------------------------

  defp create_names(%{sources: sources}, as_prefix) do
    create_names(sources, 0, tuple_size(sources), as_prefix) |> List.to_tuple()
  end

  defp create_names(sources, pos, limit, as_prefix) when pos < limit do
    [create_name(sources, pos, as_prefix) | create_names(sources, pos + 1, limit, as_prefix)]
  end

  defp create_names(_sources, pos, pos, as_prefix), do: [as_prefix]

  defp subquery_as_prefix(sources) do
    [?s | :erlang.element(tuple_size(sources), sources)]
  end

  defp create_name(sources, pos, as_prefix) do
    case elem(sources, pos) do
      {:fragment, _, _} ->
        {nil, as_prefix ++ [?f | Integer.to_string(pos)], nil}

      {:values, _, _} ->
        {nil, as_prefix ++ [?v | Integer.to_string(pos)], nil}

      {table, model, prefix} ->
        name = as_prefix ++ [create_alias(table) | Integer.to_string(pos)]
        {quote_table(prefix, table), name, model}

      %Ecto.SubQuery{} ->
        {nil, as_prefix ++ [?s | Integer.to_string(pos)], nil}
    end
  end

  defp create_alias(<<first, _rest::binary>>)
       when first in ?a..?z or first in ?A..?Z,
       do: first

  defp create_alias(_), do: ?t

  # ---------------------------------------------------------------------------
  # Source helpers
  # ---------------------------------------------------------------------------

  defp get_source(query, sources, ix, source) do
    {expr, name, _schema} = elem(sources, ix)
    {expr || expr(source, sources, query), name}
  end

  defp get_parent_sources_ix(query, as) do
    case query.aliases[@parent_as] do
      {%{aliases: %{^as => ix}}, sources} -> {ix, sources}
      {%{aliases: aliases}, _sources} -> error!(query, "unknown alias `#{as}`, aliases: #{inspect(aliases)}")
    end
  end

  # ---------------------------------------------------------------------------
  # Quoting / identifier helpers
  # ---------------------------------------------------------------------------

  defp quote_name(name) when is_atom(name), do: quote_name(Atom.to_string(name))
  defp quote_name(name) when is_binary(name), do: [?[, name, ?]]

  defp quote_names(names), do: Enum.map_intersperse(names, ?,, &quote_name/1)

  defp quote_table(nil, name), do: quote_name(name)
  defp quote_table(prefix, name), do: [quote_name(prefix), ?., quote_name(name)]

  defp escape_string(value) when is_binary(value) do
    String.replace(value, "'", "''")
  end

  defp list_param_to_args(idx, length) do
    Enum.map_join(idx..(idx + length - 1), ", ", fn i -> "@#{i + 1}" end)
  end

  defp column_type(:string, _opts), do: "nvarchar(max)"
  defp column_type(:binary, _opts), do: "varbinary(max)"
  defp column_type(:boolean, _opts), do: "bit"
  defp column_type(:integer, _opts), do: "bigint"
  defp column_type(:float, _opts), do: "float"
  defp column_type(:decimal, _opts), do: "decimal"
  defp column_type(:date, _opts), do: "date"
  defp column_type(:time, _opts), do: "time"
  defp column_type(:naive_datetime, _opts), do: "datetime2"
  defp column_type(:utc_datetime, _opts), do: "datetimeoffset"
  defp column_type(:uuid, _opts), do: "uniqueidentifier"
  defp column_type({:array, _inner}, _opts), do: raise("MSSQL does not support array types")
  defp column_type(type, _opts), do: Atom.to_string(type)

  # ---------------------------------------------------------------------------
  # intersperse_reduce helper
  # ---------------------------------------------------------------------------

  defp intersperse_reduce(list, separator, user_acc, reducer, acc \\ [])

  defp intersperse_reduce([], _separator, user_acc, _reducer, acc) do
    {Enum.reverse(acc), user_acc}
  end

  defp intersperse_reduce([elem], _separator, user_acc, reducer, acc) do
    {item, user_acc} = reducer.(elem, user_acc)
    {Enum.reverse([item | acc]), user_acc}
  end

  defp intersperse_reduce([elem | rest], separator, user_acc, reducer, acc) do
    {item, user_acc} = reducer.(elem, user_acc)
    intersperse_reduce(rest, separator, user_acc, reducer, [separator, item | acc])
  end

  # ---------------------------------------------------------------------------
  # error!/2 helper
  # ---------------------------------------------------------------------------

  defp error!(nil, message) do
    raise ArgumentError, message
  end

  defp error!(query, message) do
    raise Ecto.QueryError, query: query, message: message
  end
end
end
