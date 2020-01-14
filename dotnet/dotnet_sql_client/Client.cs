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

        public object Connect(params object[] parameters)
        {
            if (_connection == null)
            {
                var connectionString = Convert.ToString(parameters[0]);
                _connection = new SqlConnection(connectionString);
                _connection.Open();
            }
            _transactions = new Dictionary<int, IDbTransaction>();
            return _connection.State == ConnectionState.Open;
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
            transaction.Rollback();
            _transactions.Remove(transactionId);
            transaction.Dispose();
            return true;
        }

        public object CommitTransaction(params object[] parameters)
        {
            var transactionId = Convert.ToInt32(parameters[0]);
            var transaction = _transactions[transactionId];
            transaction.Commit();
            _transactions.Remove(transactionId);
            transaction.Dispose();
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
        private object ExecuteStatement(string sql, IDictionary<object, object> variables, IDbTransaction transaction = null)
        {
            var results = new List<IDictionary<string, object>>();
            using (var command = _connection.CreateCommand())
            {
                command.CommandText = sql;
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
            }
            return results;
        }
    }
}
