using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Linq;

namespace DotnetSqlClient
{
    public class SqlAdapter
    {
        private IDbConnection Connection { get; set; }
        private Dictionary<int, IDbTransaction> Transactions { get; set; }
        private Dictionary<int, IDbCommand> PreparedStatements { get; set; }

        public object Connect(params object[] parameters)
        {
            if (Connection == null)
            {
                var connectionString = Convert.ToString(parameters[0]);
                Connection = new SqlConnection(connectionString);
                Connection.Open();
            }
            Transactions = new Dictionary<int, IDbTransaction>();
            PreparedStatements = new Dictionary<int, IDbCommand>();
            return Connection.State == ConnectionState.Open;
        }

        public object Disconnect(params object[] _)
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

        public object BeginTransaction(params object[] _)
        {
            var transaction = Connection.BeginTransaction();
            var transactionId = transaction.GetHashCode();
            Transactions.Add(transactionId, transaction);
            return transactionId;
        }

        public object RollbackTransaction(params object[] parameters)
        {
            var transactionId = Convert.ToInt32(parameters[0]);
            var transaction = Transactions[transactionId];
            try
            {
                transaction.Rollback();
            }
            catch
            {
                Transactions.Remove(transactionId);
                transaction.Dispose();
                throw;
            }
            return true;
        }

        public object CommitTransaction(params object[] parameters)
        {
            var transactionId = Convert.ToInt32(parameters[0]);
            var transaction = Transactions[transactionId];
            try
            {
                transaction.Commit();
            }
            catch
            {
                Transactions.Remove(transactionId);
                transaction.Dispose();
                throw;
            }
            return true;
        }

        public object Execute(params object[] parameters)
        {
            var sql = Convert.ToString(parameters[0]);
            var variables = parameters[1] as IDictionary<object, object>;
            return ExecuteStatement(sql, variables);
        }

        public object ExecuteInTransaction(params object[] parameters)
        {
            var sql = Convert.ToString(parameters[0]);
            var variables = parameters[1] as IDictionary<object, object>;
            var transactionId = Convert.ToInt32(parameters[2]);
            var transaction = Transactions[transactionId];
            return ExecuteStatement(sql, variables, transaction);
        }

        public object ExecutePreparedStatement(params object[] parameters)
        {
            var sql = Convert.ToString(parameters[0]);
            var variables = parameters[1] as IDictionary<object, object>;
            var statementId = Convert.ToInt32(parameters[2]);
            var command = PreparedStatements[statementId];
            return ExecuteStatement(sql, variables, command: command);
        }

        public object ExecutePreparedStatementInTransaction(params object[] parameters)
        {
            var sql = Convert.ToString(parameters[0]);
            var variables = parameters[1] as IDictionary<object, object>;
            var transactionId = Convert.ToInt32(parameters[2]);
            var statementId = Convert.ToInt32(parameters[3]);
            var transaction = Transactions[transactionId];
            var command = PreparedStatements[statementId];
            return ExecuteStatement(sql, variables, transaction, command);
        }

        public object ClosePreparedStatement(params object[] parameters)
        {
            var statementId = Convert.ToInt32(parameters[0]);
            var command = PreparedStatements[statementId];
            PreparedStatements.Remove(statementId);
            command.Dispose();
            return true;
        }

        public object PrepareStatement(params object[] parameters)
        {
            var sql = Convert.ToString(parameters[0]);
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
            var statementId = command.GetHashCode();
            PreparedStatements.Add(statementId, command);
            return statementId;
        }

        private object ExecuteStatement(string sql, IDictionary<object, object> variables, IDbTransaction transaction = null, IDbCommand command = null)
        {
            var results = new List<IDictionary<string, object>>();
            var disposeCommand = false;
            if (command == null)
            {
                command = Connection.CreateCommand();
                command.CommandText = sql;
                disposeCommand = true;
            }
            else
            {
                command.Parameters.Clear();
            }

            try
            {
                if (transaction != null)
                {
                    command.Transaction = transaction;
                }

                if (variables != null)
                {
                    foreach (var pair in variables)
                    {
                        var parameter = new SqlParameter("@" + pair.Key.ToString(), pair.Value);
                        command.Parameters.Add(parameter);
                    }
                }
                var reader = command.ExecuteReader();
                var hasResults = true;
                while (hasResults)
                {
                    while (reader.Read())
                    {
                        results.Add(Enumerable.Range(0, reader.FieldCount)
                            .ToDictionary(i =>
                            {
                                var name = reader.GetName(i);
                                if (string.IsNullOrEmpty(name))
                                {
                                    name = i.ToString();
                                }
                                return name;
                            }, i => reader.IsDBNull(i) ? null : reader.GetValue(i)));
                    }
                    hasResults = reader.NextResult();
                }
                reader.Close();
            }
            catch
            {
                if (disposeCommand)
                {
                    command.Dispose();
                }
                throw;
            }
            return results;
        }
    }
}
