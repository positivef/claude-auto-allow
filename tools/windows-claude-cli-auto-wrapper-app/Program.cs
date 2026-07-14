using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;

[assembly: AssemblyTitle("Windows Claude CLI Auto Wrapper")]
[assembly: AssemblyDescription("Windows CLI wrapper that starts Claude Code with permission-mode auto. Provenance: CLAUDE-CLI-AUTO-POSITIVEF-2026-07.")]
[assembly: AssemblyCompany("positivef")]
[assembly: AssemblyProduct("Windows Claude CLI Auto Wrapper")]
[assembly: AssemblyCopyright("Copyright (c) 2026 positivef. All rights reserved.")]
[assembly: AssemblyTrademark("CLAUDE-CLI-AUTO-POSITIVEF-2026-07")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

internal static class Program
{
    private const string Provenance = "CLAUDE-CLI-AUTO-POSITIVEF-2026-07";

    private static int Main(string[] args)
    {
        try
        {
            var claudeArgs = new List<string>(args);
            bool hasPermissionOverride = HasPermissionOverride(claudeArgs);
            var finalArgs = new List<string>();

            if (!hasPermissionOverride)
            {
                finalArgs.Add("--permission-mode");
                finalArgs.Add("auto");
            }

            finalArgs.AddRange(claudeArgs);

            string projectPath = Environment.CurrentDirectory;
            string projectName = new DirectoryInfo(projectPath).Name;
            string taskSummary = GetTaskSummary(claudeArgs);
            SetConsoleTitle(projectName, taskSummary, hasPermissionOverride);
            WriteBanner(projectName, projectPath, taskSummary, hasPermissionOverride);

            string claudePath = ResolveClaudeExecutable();
            WriteLaunchLine(claudePath, finalArgs);

            var startInfo = new ProcessStartInfo
            {
                FileName = claudePath,
                Arguments = JoinWindowsCommandLine(finalArgs),
                WorkingDirectory = projectPath,
                UseShellExecute = false
            };

            using (var process = Process.Start(startInfo))
            {
                if (process == null)
                {
                    Console.Error.WriteLine("Failed to start Claude Code.");
                    return 1;
                }

                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex.Message);
            return 1;
        }
    }

    private static bool HasPermissionOverride(IEnumerable<string> args)
    {
        foreach (string arg in args)
        {
            if (
                arg == "--dangerously-skip-permissions" ||
                arg == "--allow-dangerously-skip-permissions" ||
                arg == "--permission-mode" ||
                arg.StartsWith("--permission-mode=", StringComparison.Ordinal)
            )
            {
                return true;
            }
        }

        return false;
    }

    private static string GetTaskSummary(IList<string> args)
    {
        var summaryParts = new List<string>();
        bool skipNext = false;

        foreach (string arg in args)
        {
            if (skipNext)
            {
                skipNext = false;
                continue;
            }

            if (arg == "--permission-mode" || arg == "--model" || arg == "--agent" || arg == "--name")
            {
                skipNext = true;
                continue;
            }

            if (arg.StartsWith("--permission-mode=", StringComparison.Ordinal))
            {
                continue;
            }

            if (arg.StartsWith("-", StringComparison.Ordinal))
            {
                continue;
            }

            summaryParts.Add(arg);
        }

        string summary = string.Join(" ", summaryParts.ToArray()).Trim();
        if (summary.Length == 0)
        {
            return "interactive session";
        }

        return Truncate(summary, 72);
    }

    private static void SetConsoleTitle(string projectName, string taskSummary, bool hasPermissionOverride)
    {
        string mode = hasPermissionOverride ? "PERMISSION OVERRIDE" : "AUTO COMMAND ACCEPT";
        string title = "[CLAUDE CLI WRAPPER][" + mode + "] " + projectName + " | " + taskSummary;

        try
        {
            Console.Title = Truncate(title, 240);
        }
        catch
        {
        }
    }

    private static void WriteBanner(string projectName, string projectPath, string taskSummary, bool hasPermissionOverride)
    {
        ConsoleColor previousColor = Console.ForegroundColor;
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine("=== CLAUDE CLI AUTO WRAPPER ACTIVE ===");
        Console.ForegroundColor = previousColor;
        Console.WriteLine("Project : " + projectName);
        Console.WriteLine("Path    : " + projectPath);
        Console.WriteLine("Task    : " + taskSummary);
        Console.WriteLine("Mode    : " + (hasPermissionOverride ? "permission override supplied by user" : "--permission-mode auto injected"));
        Console.WriteLine("Owner   : positivef");
        Console.WriteLine("Marker  : " + Provenance);
        Console.WriteLine();
    }

    private static string ResolveClaudeExecutable()
    {
        string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        string npmClaudeExe = Path.Combine(
            appData,
            "npm",
            "node_modules",
            "@anthropic-ai",
            "claude-code",
            "bin",
            "claude.exe"
        );

        if (File.Exists(npmClaudeExe))
        {
            return npmClaudeExe;
        }

        foreach (string pathDir in GetPathDirectories())
        {
            string shimPath = Path.Combine(pathDir, "claude.cmd");
            if (File.Exists(shimPath))
            {
                string exeBesideShim = Path.Combine(
                    pathDir,
                    "node_modules",
                    "@anthropic-ai",
                    "claude-code",
                    "bin",
                    "claude.exe"
                );

                if (File.Exists(exeBesideShim))
                {
                    return exeBesideShim;
                }
            }

            string directExe = Path.Combine(pathDir, "claude.exe");
            if (File.Exists(directExe) && !IsCurrentProcess(directExe))
            {
                return directExe;
            }
        }

        throw new FileNotFoundException("Claude Code CLI executable was not found. Install Claude Code first, then run this wrapper again.");
    }

    private static IEnumerable<string> GetPathDirectories()
    {
        string pathValue = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        return pathValue
            .Split(new[] { Path.PathSeparator }, StringSplitOptions.RemoveEmptyEntries)
            .Select(path => path.Trim())
            .Where(Directory.Exists);
    }

    private static bool IsCurrentProcess(string candidatePath)
    {
        string currentPath = GetCurrentProcessPath();
        if (string.IsNullOrEmpty(currentPath))
        {
            return false;
        }

        return string.Equals(
            Path.GetFullPath(candidatePath),
            Path.GetFullPath(currentPath),
            StringComparison.OrdinalIgnoreCase
        );
    }

    private static string GetCurrentProcessPath()
    {
        using (var currentProcess = Process.GetCurrentProcess())
        {
            return currentProcess.MainModule == null ? string.Empty : currentProcess.MainModule.FileName;
        }
    }

    private static void WriteLaunchLine(string claudePath, IEnumerable<string> args)
    {
        ConsoleColor previousColor = Console.ForegroundColor;
        Console.ForegroundColor = ConsoleColor.DarkGray;
        Console.WriteLine("[windows-claude-cli-auto-wrapper] " + QuoteForDisplay(claudePath) + " " + string.Join(" ", args.Select(QuoteForDisplay).ToArray()));
        Console.ForegroundColor = previousColor;
    }

    private static string Truncate(string value, int maxLength)
    {
        if (value.Length <= maxLength)
        {
            return value;
        }

        return value.Substring(0, Math.Max(0, maxLength - 3)) + "...";
    }

    private static string QuoteForDisplay(string value)
    {
        if (value.Length == 0)
        {
            return "\"\"";
        }

        return value.Any(char.IsWhiteSpace) ? "\"" + value.Replace("\"", "\\\"") + "\"" : value;
    }

    private static string JoinWindowsCommandLine(IEnumerable<string> args)
    {
        return string.Join(" ", args.Select(QuoteForCreateProcess).ToArray());
    }

    private static string QuoteForCreateProcess(string arg)
    {
        if (arg.Length == 0)
        {
            return "\"\"";
        }

        bool needsQuotes = arg.Any(ch => char.IsWhiteSpace(ch) || ch == '"');
        if (!needsQuotes)
        {
            return arg;
        }

        var result = new StringBuilder();
        result.Append('"');

        int backslashes = 0;
        foreach (char ch in arg)
        {
            if (ch == '\\')
            {
                backslashes++;
                continue;
            }

            if (ch == '"')
            {
                result.Append('\\', backslashes * 2 + 1);
                result.Append('"');
                backslashes = 0;
                continue;
            }

            result.Append('\\', backslashes);
            backslashes = 0;
            result.Append(ch);
        }

        result.Append('\\', backslashes * 2);
        result.Append('"');
        return result.ToString();
    }
}
