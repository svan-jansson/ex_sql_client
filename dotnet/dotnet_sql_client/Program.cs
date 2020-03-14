using DotnetSqlClient;
using Netler;
using System;
using System.Threading.Tasks;

namespace Dotnetadapter
{
    class Program
    {
        static async Task Main(string[] args)
        {
            var port = Convert.ToInt32(args[0]);
            var clientPid = Convert.ToInt32(args[1]);
            var adapter = new SqlAdapter();

            var server = Server.Create((config) =>
                {
                    config.UsePort(port);
                    config.UseClientPid(clientPid);
                    config.UseRoutes((routes) =>
                    {
                        routes.Add("Connect", adapter.Connect);
                        routes.Add("Disconnect", adapter.Disconnect);
                        routes.Add("Execute", adapter.Execute);
                        routes.Add("ExecuteInTransaction", adapter.ExecuteInTransaction);
                        routes.Add("ExecutePreparedStatement", adapter.ExecutePreparedStatement);
                        routes.Add("ExecutePreparedStatementInTransaction", adapter.ExecutePreparedStatementInTransaction);
                        routes.Add("BeginTransaction", adapter.BeginTransaction);
                        routes.Add("RollbackTransaction", adapter.RollbackTransaction);
                        routes.Add("CommitTransaction", adapter.CommitTransaction);
                        routes.Add("PrepareStatement", adapter.PrepareStatement);
                        routes.Add("ClosePreparedStatement", adapter.ClosePreparedStatement);
                    });
                });

            await server.Start();
        }
    }
}
