using System;
using System.Collections.Generic;
using Netler;

namespace DotnetSqlClient
{
    class Program
    {
        static void Main(string[] args)
        {
            Netler.Server.Export(
                args,
                new Dictionary<string, Func<object[], object>> {
                    {"Add", Add}
                }
            );
        }

        static object Add(params object[] parameters)
        {
            var a = Convert.ToInt32(parameters[0]);
            var b = Convert.ToInt32(parameters[1]);
            return a + b;
        }
    }
}
