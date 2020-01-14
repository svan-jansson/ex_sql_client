using System;
using System.Collections.Generic;
using Netler;

namespace DotnetSqlClient
{
    class Program
    {
        static void Main(string[] args)
        {
            var client = new Client();

            Netler.Server.Export(
                args,
                new Dictionary<string, Func<object[], object>> {
                    {"Connect", client.Connect},
                    {"Disconnect", client.Disconnect},
                    {"Execute", client.Execute},
                    {"ExecuteInTransaction", client.ExecuteInTransaction},
                    {"ExecutePreparedStatement", client.ExecutePreparedStatement},
                    {"ExecutePreparedStatementInTransaction", client.ExecutePreparedStatementInTransaction},
                    {"BeginTransaction", client.BeginTransaction},
                    {"RollbackTransaction", client.RollbackTransaction},
                    {"CommitTransaction", client.CommitTransaction},
                    {"PrepareStatement", client.PrepareStatement}
                }
            );
        }


    }
}
