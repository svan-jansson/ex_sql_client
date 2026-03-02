using System;
using System.Collections.Generic;
using System.Data;
using Microsoft.Data.SqlClient;

namespace DotnetSqlClient;

public class SqlAdapter
{
    private IDbConnection Connection { get; set; }
    private Dictionary<int, IDbTransaction> Transactions { get; set; }
    private Dictionary<int, IDbCommand> PreparedStatements { get; set; }
    private int _nextId = 0;

    // Returns immediately without touching SQL Server.
    // Used by the Elixir benchmarks to isolate pure Netler IPC overhead.
    public static bool NoOp() => true;

    public bool Connect(string connectionString)
    {
        if (Connection == null)
        {
            Connection = new SqlConnection(connectionString);
            Connection.Open();
        }
        Transactions = new Dictionary<int, IDbTransaction>();
        PreparedStatements = new Dictionary<int, IDbCommand>();
        return Connection.State == ConnectionState.Open;
    }

    public bool Disconnect()
    {
        if (Connection != null)
        {
            Connection.Close();
            Connection.Dispose();
            Connection = null;
            Transactions = null;
            PreparedStatements = null;
        }
        return true;
    }

    public int BeginTransaction()
    {
        var transaction = Connection.BeginTransaction();
        var transactionId = System.Threading.Interlocked.Increment(ref _nextId);
        Transactions.Add(transactionId, transaction);
        return transactionId;
    }

    public bool RollbackTransaction(int transactionId)
    {
        var transaction = Transactions[transactionId];
        try
        {
            transaction.Rollback();
        }
        finally
        {
            Transactions.Remove(transactionId);
            transaction.Dispose();
        }
        return true;
    }

    public bool CommitTransaction(int transactionId)
    {
        var transaction = Transactions[transactionId];
        try
        {
            transaction.Commit();
        }
        finally
        {
            Transactions.Remove(transactionId);
            transaction.Dispose();
        }
        return true;
    }

    public List<IDictionary<string, object>> Execute(string sql, IDictionary<object, object> variables)
    {
        return ExecuteStatement(sql, variables);
    }

    public List<IDictionary<string, object>> ExecuteInTransaction(string sql, IDictionary<object, object> variables, int transactionId)
    {
        var transaction = Transactions[transactionId];
        return ExecuteStatement(sql, variables, transaction);
    }

    public List<IDictionary<string, object>> ExecutePreparedStatement(string sql, IDictionary<object, object> variables, int statementId)
    {
        var command = PreparedStatements[statementId];
        return ExecuteStatement(sql, variables, command: command);
    }

    public List<IDictionary<string, object>> ExecutePreparedStatementInTransaction(string sql, IDictionary<object, object> variables, int transactionId, int statementId)
    {
        var transaction = Transactions[transactionId];
        var command = PreparedStatements[statementId];
        return ExecuteStatement(sql, variables, transaction, command);
    }

    public bool ClosePreparedStatement(int statementId)
    {
        var command = PreparedStatements[statementId];
        PreparedStatements.Remove(statementId);
        command.Dispose();
        return true;
    }

    public int PrepareStatement(string sql)
    {
        var command = Connection.CreateCommand();
        try
        {
            command.CommandText = sql;
            command.Prepare();
        }
        catch
        {
            command.Dispose();
            throw;
        }
        var statementId = System.Threading.Interlocked.Increment(ref _nextId);
        PreparedStatements.Add(statementId, command);
        return statementId;
    }

    private List<IDictionary<string, object>> ExecuteStatement(string sql, IDictionary<object, object> variables, IDbTransaction transaction = null, IDbCommand command = null)
    {
        var results = new List<IDictionary<string, object>>();
        var disposeCommand = command == null;
        if (disposeCommand)
        {
            command = Connection.CreateCommand();
            command.CommandText = sql;
        }
        else
        {
            command.Parameters.Clear();
        }

        try
        {
            if (transaction != null)
                command.Transaction = transaction;

            if (variables != null)
            {
                foreach (var pair in variables)
                {
                    var key = pair.Key.ToString();
                    if (!IsValidParameterName(key))
                        throw new ArgumentException($"Invalid parameter name: {key}");
                    command.Parameters.Add(new SqlParameter("@" + key, NormalizeValue(pair.Value)));
                }
            }

            using (var reader = command.ExecuteReader())
            {
                do
                {
                    while (reader.Read())
                    {
                        var row = new Dictionary<string, object>(reader.FieldCount);
                        for (int i = 0; i < reader.FieldCount; i++)
                        {
                            var name = reader.GetName(i);
                            if (string.IsNullOrEmpty(name))
                                name = i.ToString();
                            row[name] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                        }
                        results.Add(row);
                    }
                } while (reader.NextResult());
            }
        }
        finally
        {
            if (disposeCommand)
                command.Dispose();
        }

        return results;
    }

    // MessagePack encodes integers using the minimum byte width, so Elixir
    // integers arrive as byte/ushort/uint/ulong depending on magnitude.
    // SQL Server rejects all unsigned integer types, so we promote them to
    // their signed equivalents before building SqlParameter.
    private static object NormalizeValue(object value) => value switch
    {
        null => DBNull.Value,
        byte b => (int)b,
        ushort us => (int)us,
        uint ui => (long)ui,
        ulong ul => (long)ul,
        _ => value
    };

    private static bool IsValidParameterName(string name)
    {
        if (string.IsNullOrEmpty(name)) return false;
        foreach (var c in name)
        {
            if (!char.IsLetterOrDigit(c) && c != '_')
                return false;
        }
        return true;
    }
}