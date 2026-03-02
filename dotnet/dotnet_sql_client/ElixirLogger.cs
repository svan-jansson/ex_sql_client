#nullable enable
using Microsoft.Extensions.Logging;
using System;

namespace DotnetSqlClient;

/// <summary>
/// Routes .NET log messages to stderr so they appear inline in the Elixir / IEx console.
///
/// Netler starts the .NET process via Elixir's System.cmd/3, which captures stdout
/// (so Console.Out goes nowhere visible) but lets stderr pass through to the BEAM's
/// stderr — i.e. the same terminal that IEx is running in.
///
/// Output is formatted to match Elixir Logger's default timestamp layout:
///   HH:mm:ss.fff [level] category: message
/// </summary>
internal sealed class ElixirLogger : ILogger
{
    private readonly string _category;
    private readonly LogLevel _minLevel;

    public ElixirLogger(string category, LogLevel minLevel = LogLevel.Information)
    {
        _category = category;
        _minLevel = minLevel;
    }

    public IDisposable? BeginScope<TState>(TState _) where TState : notnull
        => NullScope.Instance;

    public bool IsEnabled(LogLevel logLevel) => logLevel >= _minLevel;

    public void Log<TState>(
        LogLevel logLevel,
        EventId _,
        TState state,
        Exception? exception,
        Func<TState, Exception?, string> formatter)
    {
        if (!IsEnabled(logLevel))
            return;

        var level = logLevel switch
        {
            LogLevel.Trace or LogLevel.Debug    => "debug",
            LogLevel.Information                => "info",
            LogLevel.Warning                    => "warning",
            LogLevel.Error or LogLevel.Critical => "error",
            _                                   => "info"
        };

        var timestamp = DateTime.Now.ToString("HH:mm:ss.fff");
        Console.Error.WriteLine($"{timestamp} [{level}] {_category}: {formatter(state, exception)}");

        if (exception is not null)
            Console.Error.WriteLine($"{timestamp} [error] {_category}: {exception}");
    }

    private sealed class NullScope : IDisposable
    {
        public static readonly NullScope Instance = new();
        public void Dispose() { }
    }
}