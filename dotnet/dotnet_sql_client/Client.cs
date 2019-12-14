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

        public object Connect(params object[] parameters)
        {
            if (_connection == null)
            {
                var connectionString = Convert.ToString(parameters[0]);
                _connection = new SqlConnection(connectionString);
                _connection.Open();
            }
            return _connection.State == ConnectionState.Open;
        }

        public object Execute(params object[] parameters)
        {
            var sql = Convert.ToString(parameters[0]);
            var variables = parameters[1] as IDictionary<object, object>;

            var results = new List<IDictionary<string, object>>();
            using (var command = _connection.CreateCommand())
            {
                command.CommandText = sql;
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
