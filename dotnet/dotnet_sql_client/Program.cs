using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using DotnetSqlClient;
using Netler;
using Netler.Contracts;

namespace Dotnetadapter;

class Program
{
    private static async Task Main(string[] args)
    {
        var port = Convert.ToInt32(args[0]);
        var clientPid = Convert.ToInt32(args[1]);
        var adapter = new SqlAdapter();

        var server = Server.Create(config =>
        {
            config.UsePort(port);
            config.UseClientPid(clientPid);
            config.UseLogger(new ElixirLogger("dotnet_sql_client"));
            config.UseRoutes(routes =>
            {
                routes.AddTyped("NoOp", SqlAdapter.NoOp);
                routes.AddTyped<string, bool>("Connect", adapter.Connect);
                routes.AddTyped("Disconnect", adapter.Disconnect);
                routes.AddTyped<string, IDictionary<object, object>, List<IDictionary<string, object>>>("Execute", adapter.Execute);
                routes.AddTyped<string, IDictionary<object, object>, int, List<IDictionary<string, object>>>("ExecuteInTransaction", adapter.ExecuteInTransaction);
                routes.AddTyped<string, IDictionary<object, object>, int, List<IDictionary<string, object>>>("ExecutePreparedStatement", adapter.ExecutePreparedStatement);
                routes.AddTyped<string, IDictionary<object, object>, int, int, List<IDictionary<string, object>>>("ExecutePreparedStatementInTransaction", adapter.ExecutePreparedStatementInTransaction);
                routes.AddTyped("BeginTransaction", adapter.BeginTransaction);
                routes.AddTyped<int, bool>("RollbackTransaction", adapter.RollbackTransaction);
                routes.AddTyped<int, bool>("CommitTransaction", adapter.CommitTransaction);
                routes.AddTyped<string, int>("PrepareStatement", adapter.PrepareStatement);
                routes.AddTyped<int, bool>("ClosePreparedStatement", adapter.ClosePreparedStatement);
            });
        });

        await server.Start();
    }
}