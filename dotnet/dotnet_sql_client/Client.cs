using System;
using System.Data.SqlClient;
using System.Collections.Generic;
using System.Data;

namespace DotnetSqlClient
{
    class Client
    {
        private IDbConnection _connection { get; set; }
        public object Connect(params object[] parameters)
        {
            var connectionString = Convert.ToString(parameters[0]);
            _connection = new SqlConnection(connectionString);
            _connection.Open();
            return _connection.State;
        }

        public object ExecuteScalar(params object[] parameters)
        {
            var sql = Convert.ToString(parameters[0]);

            using (var command = _connection.CreateCommand())
            {
                command.CommandText = sql;
                var result = command.ExecuteScalar();
                return result;
            }
        }
    }
}
