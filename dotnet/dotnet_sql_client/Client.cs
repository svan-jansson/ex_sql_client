using System;
using System.Data.SqlClient;
using System.Collections.Generic;
using System.Data;
using System.Linq;

namespace DotnetSqlClient
{
    class Client
    {
        private IDbConnection _connection { get; set; }
        private Dictionary<int, IDbTransaction> _transactions { get; set; }
        private Dictionary<int, IDbCommand> _preparedStatements { get; set; }

        public object Connect(params object[] parameters)
        {
            if (_connection == null)
            {
                var connectionString = Convert.ToString(parameters[0]);
                _connection = new SqlConnection(connectionString);
                _connection.Open();
            }
            _transactions = new Dictionary<int, IDbTransaction>();
            _preparedStatements = new Dictionary<int, IDbCommand>();
            return _connection.State == ConnectionState.Open;
        }

        public object Disconnect(params object[] parameters)
        {
            if (_connection != null)
            {
                _connection.Close();
                _connection.Dispose();
                _connection = null;
                _transactions = null;
                _preparedStatements = null;
            }
            return true;
        }

        public object BeginTransaction(params object[] _parameters)
        {
            var transaction = _connection.BeginTransaction();
            var transactionId = transaction.GetHashCode();
            _transactions.Add(transactionId, transaction);
            return transactionId;
        }

        public object RollbackTransaction(params object[] parameters)
        {
            var transactionId = Convert.ToInt32(parameters[0]);
            var transaction = _transactions[transactionId];
            try
            {
                transaction.Rollback();
            }
            catch
            {
                _transactions.Remove(transactionId);
                transaction.Dispose();
                throw;
            }
            return true;
        }

        public object CommitTransaction(params object[] parameters)
        {
            var transactionId = Convert.ToInt32(parameters[0]);
            var transaction = _transactions[transactionId];
            try
            {
                transaction.Commit();
            }
            catch
            {
                _transactions.Remove(transactionId);
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
            var transaction = _transactions[transactionId];
            return ExecuteStatement(sql, variables, transaction);
        }

        public object ExecutePreparedStatement(params object[] parameters)
        {
            var sql = Convert.ToString(parameters[0]);
            var variables = parameters[1] as IDictionary<object, object>;
            var statementId = Convert.ToInt32(parameters[2]);
            var command = _preparedStatements[statementId];
            return ExecuteStatement(sql, variables, command: command);
        }

        public object ExecutePreparedStatementInTransaction(params object[] parameters)
        {
            var sql = Convert.ToString(parameters[0]);
            var variables = parameters[1] as IDictionary<object, object>;
            var transactionId = Convert.ToInt32(parameters[2]);
            var statementId = Convert.ToInt32(parameters[3]);
            var transaction = _transactions[transactionId];
            var command = _preparedStatements[statementId];
            return ExecuteStatement(sql, variables, transaction, command);
        }

        public object ClosePreparedStatement(params object[] parameters)
        {
            var statementId = Convert.ToInt32(parameters[0]);
            var command = _preparedStatements[statementId];
            _preparedStatements.Remove(statementId);
            command.Dispose();
            return true;
        }

        public object PrepareStatement(params object[] parameters)
        {
            var sql = Convert.ToString(parameters[0]);
            var command = _connection.CreateCommand();
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
            _preparedStatements.Add(statementId, command);
            return statementId;
        }

        private object ExecuteStatement(string sql, IDictionary<object, object> variables, IDbTransaction transaction = null, IDbCommand command = null)
        {
            var results = new List<IDictionary<string, object>>();
            var disposeCommand = false;
            if (command == null)
            {
                command = _connection.CreateCommand();
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
                            }, i => reader.GetValue(i)));
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
