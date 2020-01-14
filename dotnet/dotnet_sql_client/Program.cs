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
                    {"Execute", client.Execute},
                    {"ExecuteInTransaction", client.ExecuteInTransaction},
                    {"BeginTransaction", client.BeginTransaction},
                    {"RollbackTransaction", client.RollbackTransaction},
                    {"CommitTransaction", client.CommitTransaction}
                }
            );
        }


    }
}
