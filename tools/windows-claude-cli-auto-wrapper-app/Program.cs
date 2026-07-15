using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;

[assembly: AssemblyTitle("Windows Claude CLI Auto Wrapper")]
[assembly: AssemblyDescription("Windows CLI wrapper that starts Claude Code with permission-mode auto. Provenance: CLAUDE-CLI-AUTO-POSITIVEF-2026-07.")]
[assembly: AssemblyCompany("positivef")]
[assembly: AssemblyProduct("Windows Claude CLI Auto Wrapper")]
[assembly: AssemblyCopyright("Copyright (c) 2026 positivef. All rights reserved.")]
[assembly: AssemblyTrademark("CLAUDE-CLI-AUTO-POSITIVEF-2026-07")]
[assembly: AssemblyVersion("1.2.0.0")]
[assembly: AssemblyFileVersion("1.2.0.0")]

internal static class Program
{
    private const string Provenance = "CLAUDE-CLI-AUTO-POSITIVEF-2026-07";

    private static int Main(string[] args)
    {
        try
        {
            if (HasSelfTest(args))
            {
                return RunSelfTest();
            }

            var claudeArgs = new List<string>(args);
            bool hasPermissionOverride = HasPermissionOverride(claudeArgs);
            CliPolicy policy = ReadCliPolicy();
            var finalArgs = new List<string>();

            if (!hasPermissionOverride && policy.CliPermissionMode == "Auto")
            {
                finalArgs.Add("--permission-mode");
                finalArgs.Add("auto");
            }

            finalArgs.AddRange(claudeArgs);

            string projectPath = Environment.CurrentDirectory;
            string projectName = new DirectoryInfo(projectPath).Name;
            TopicInfo topic = GetTopicInfo(claudeArgs);
            SetConsoleTitle(projectName, topic.Text, hasPermissionOverride, policy.CliPermissionMode);
            WriteBanner(projectName, projectPath, topic, hasPermissionOverride, policy);

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

    private static bool HasSelfTest(IEnumerable<string> args)
    {
        return args.Any(arg => string.Equals(arg, "--self-test", StringComparison.OrdinalIgnoreCase));
    }

    private static int RunSelfTest()
    {
        CliPolicy policy = ReadCliPolicy();
        string claudePath = ResolveClaudeExecutable();

        Console.WriteLine("Windows Claude CLI Auto Wrapper self-test OK");
        Console.WriteLine("Claude : " + claudePath);
        Console.WriteLine("Policy : " + (string.IsNullOrEmpty(policy.PolicyPath) ? "not found; default CLI Auto" : policy.PolicyPath));
        Console.WriteLine("Mode   : " + policy.CliPermissionMode);
        Console.WriteLine("Marker : " + Provenance);
        return 0;
    }

    private static CliPolicy ReadCliPolicy()
    {
        foreach (string candidate in GetPolicyFileCandidates())
        {
            if (!File.Exists(candidate))
            {
                continue;
            }

            try
            {
                string json = File.ReadAllText(candidate, Encoding.UTF8);
                string mode = ExtractJsonString(json, "cliPermissionMode", "Auto");
                if (string.Equals(mode, "Manual", StringComparison.OrdinalIgnoreCase))
                {
                    return new CliPolicy("Manual", candidate);
                }

                if (string.Equals(mode, "Auto", StringComparison.OrdinalIgnoreCase))
                {
                    return new CliPolicy("Auto", candidate);
                }
            }
            catch
            {
                return new CliPolicy("Auto", candidate);
            }
        }

        return new CliPolicy("Auto", string.Empty);
    }

    private static IEnumerable<string> GetPolicyFileCandidates()
    {
        string envPolicyFile = Environment.GetEnvironmentVariable("CLAUDE_AUTO_ALLOW_POLICY_FILE") ?? string.Empty;
        if (!string.IsNullOrWhiteSpace(envPolicyFile))
        {
            yield return Path.GetFullPath(envPolicyFile);
        }

        string baseDirectory = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
        yield return Path.Combine(baseDirectory, "auto-allow-policy.json");
    }

    private static string ExtractJsonString(string json, string name, string fallback)
    {
        var match = Regex.Match(json, "\"" + Regex.Escape(name) + "\"\\s*:\\s*\"(?<value>(?:\\\\.|[^\"])*)\"", RegexOptions.IgnoreCase);
        if (!match.Success)
        {
            return fallback;
        }

        return Regex.Unescape(match.Groups["value"].Value);
    }

    private static TopicInfo GetTopicInfo(IList<string> args)
    {
        string envTopic = (Environment.GetEnvironmentVariable("CLAUDE_AUTO_ALLOW_TOPIC") ?? string.Empty).Trim();
        if (envTopic.Length > 0)
        {
            return new TopicInfo(Truncate(NormalizeTopicText(envTopic), 72), "CLAUDE_AUTO_ALLOW_TOPIC");
        }

        string argTopic = NormalizeTopicText(GetArgumentTopic(args));
        if (argTopic.Length > 0)
        {
            return new TopicInfo(Truncate(argTopic, 72), "command arguments");
        }

        return new TopicInfo("interactive session", "default");
    }

    private static string GetArgumentTopic(IList<string> args)
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

        return string.Join(" ", summaryParts.ToArray()).Trim();
    }

    private static string NormalizeTopicText(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        string withoutControlChars = Regex.Replace(value, "[\\x00-\\x1F\\x7F]", " ");
        return Regex.Replace(withoutControlChars, "\\s+", " ").Trim();
    }

    private static void SetConsoleTitle(string projectName, string topic, bool hasPermissionOverride, string cliPermissionMode)
    {
        string mode = GetShortModeLabel(hasPermissionOverride, cliPermissionMode);
        string title = "Claude CLI | Project=" + projectName + " | Mode=" + mode + " | Topic=" + topic;

        try
        {
            Console.Title = Truncate(title, 240);
        }
        catch
        {
        }
    }

    private static void WriteBanner(string projectName, string projectPath, TopicInfo topic, bool hasPermissionOverride, CliPolicy policy)
    {
        ConsoleColor previousColor = Console.ForegroundColor;
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine("=== CLAUDE CLI AUTO WRAPPER ACTIVE ===");
        Console.ForegroundColor = previousColor;
        Console.WriteLine("Project : " + projectName);
        Console.WriteLine("Path    : " + projectPath);
        Console.WriteLine("Status  : launching Claude Code under wrapper");
        Console.WriteLine("Topic   : " + topic.Text);
        Console.WriteLine("TopicSrc: " + topic.Source);
        Console.WriteLine("Mode    : " + GetModeText(hasPermissionOverride, policy.CliPermissionMode));
        Console.WriteLine("Policy  : " + (string.IsNullOrEmpty(policy.PolicyPath) ? "not found; default CLI Auto" : policy.PolicyPath));
        Console.WriteLine("Title   : Project + Mode + Topic are shown in the terminal title bar");
        Console.WriteLine("Owner   : positivef");
        Console.WriteLine("Marker  : " + Provenance);
        Console.WriteLine();
    }

    private static string GetShortModeLabel(bool hasPermissionOverride, string cliPermissionMode)
    {
        if (hasPermissionOverride)
        {
            return "OVERRIDE";
        }

        if (cliPermissionMode == "Manual")
        {
            return "MANUAL";
        }

        return "AUTO";
    }

    private static string GetModeText(bool hasPermissionOverride, string cliPermissionMode)
    {
        if (hasPermissionOverride)
        {
            return "permission override supplied by user";
        }

        if (cliPermissionMode == "Manual")
        {
            return "CLI policy Manual; no --permission-mode injected";
        }

        return "CLI policy Auto; --permission-mode auto injected";
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

    private sealed class CliPolicy
    {
        public CliPolicy(string cliPermissionMode, string policyPath)
        {
            CliPermissionMode = cliPermissionMode;
            PolicyPath = policyPath;
        }

        public string CliPermissionMode { get; private set; }
        public string PolicyPath { get; private set; }
    }

    private sealed class TopicInfo
    {
        public TopicInfo(string text, string source)
        {
            Text = text;
            Source = source;
        }

        public string Text { get; private set; }
        public string Source { get; private set; }
    }
}
