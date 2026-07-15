using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;

[assembly: AssemblyTitle("Windows Copilot Desktop Click Auto Allow")]
[assembly: AssemblyDescription("Windows desktop-click helper for Copilot permission prompts. Provenance: COPILOT-AA-POSITIVEF-2026-07.")]
[assembly: AssemblyCompany("positivef")]
[assembly: AssemblyProduct("Windows Copilot Desktop Click Auto Allow")]
[assembly: AssemblyCopyright("Copyright (c) 2026 positivef. All rights reserved.")]
[assembly: AssemblyTrademark("COPILOT-AA-POSITIVEF-2026-07")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

internal static class Program
{
    private const string Provenance = "COPILOT-AA-POSITIVEF-2026-07";

    private static int Main(string[] args)
    {
        try
        {
            Console.WriteLine("Windows Copilot Desktop Click Auto Allow - positivef - " + Provenance);

            string scriptPath = ResolveSafeSiblingFile("windows-copilot-desktop-click-auto-allow.ps1");
            if (args.Any(arg => string.Equals(arg, "--self-test", StringComparison.OrdinalIgnoreCase)))
            {
                Console.WriteLine("Self-test OK");
                Console.WriteLine("Script: " + scriptPath);
                Console.WriteLine("PowerShell: " + ResolvePowerShellExecutable());
                Console.WriteLine("Cmd: " + ResolveCmdExecutable());
                return 0;
            }

            var powershellArgs = new List<string>
            {
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "RemoteSigned",
                "-File",
                scriptPath
            };
            powershellArgs.AddRange(args);

            var startInfo = new ProcessStartInfo
            {
                FileName = ResolveCmdExecutable(),
                Arguments = BuildCmdPowerShellArguments(powershellArgs),
                WorkingDirectory = Environment.CurrentDirectory,
                UseShellExecute = false
            };

            using (Process process = Process.Start(startInfo))
            {
                if (process == null)
                {
                    Console.Error.WriteLine("Failed to start PowerShell.");
                    return 1;
                }

                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("ERROR: " + ex.Message);
            return 1;
        }
    }

    private static string ResolvePowerShellExecutable()
    {
        string windowsDirectory = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        if (!string.IsNullOrWhiteSpace(windowsDirectory))
        {
            string candidate = Path.Combine(windowsDirectory, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return "powershell.exe";
    }

    private static string ResolveCmdExecutable()
    {
        string systemDirectory = Environment.SystemDirectory;
        if (!string.IsNullOrWhiteSpace(systemDirectory))
        {
            string candidate = Path.Combine(systemDirectory, "cmd.exe");
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return "cmd.exe";
    }

    private static string BuildCmdPowerShellArguments(IEnumerable<string> powershellArgs)
    {
        var command = new StringBuilder();
        command.Append(QuoteForCmd(ResolvePowerShellExecutable()));
        foreach (string arg in powershellArgs)
        {
            command.Append(' ');
            command.Append(QuoteForCmd(arg));
        }

        return "/d /s /c \"" + command + "\"";
    }

    private static string QuoteForCmd(string value)
    {
        return "\"" + value
            .Replace("^", "^^")
            .Replace("&", "^&")
            .Replace("|", "^|")
            .Replace("<", "^<")
            .Replace(">", "^>")
            .Replace("\"", "^\"") + "\"";
    }

    private static string JoinWindowsCommandLine(IEnumerable<string> args)
    {
        return string.Join(" ", args.Select(QuoteForCreateProcess).ToArray());
    }

    private static string ResolveSafeSiblingFile(string fileName)
    {
        string baseDirectory = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
        string candidate = Path.GetFullPath(Path.Combine(baseDirectory, fileName));

        if (!candidate.StartsWith(baseDirectory, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(fileName + " resolved outside the executable directory.");
        }

        if (!File.Exists(candidate))
        {
            throw new FileNotFoundException(fileName + " was not found next to this executable.", candidate);
        }

        FileAttributes attributes = File.GetAttributes(candidate);
        if ((attributes & FileAttributes.ReparsePoint) == FileAttributes.ReparsePoint)
        {
            throw new InvalidOperationException(fileName + " must be a real file, not a reparse point or symbolic link.");
        }

        return candidate;
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
