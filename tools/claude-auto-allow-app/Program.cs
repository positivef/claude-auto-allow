using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;

[assembly: AssemblyTitle("Claude Auto Allow")]
[assembly: AssemblyDescription("Windows helper for Claude permission prompts. Provenance: CAA-POSITIVEF-2026-07.")]
[assembly: AssemblyCompany("positivef")]
[assembly: AssemblyProduct("Claude Auto Allow")]
[assembly: AssemblyCopyright("Copyright (c) 2026 positivef. All rights reserved.")]
[assembly: AssemblyTrademark("CAA-POSITIVEF-2026-07")]
[assembly: AssemblyVersion("1.1.0.0")]
[assembly: AssemblyFileVersion("1.1.0.0")]

internal static class Program
{
    private const string Provenance = "CAA-POSITIVEF-2026-07";

    private static int Main(string[] args)
    {
        try
        {
            Console.WriteLine("Claude Auto Allow - positivef - " + Provenance);

            string scriptPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "claude-auto-allow.ps1");
            if (!File.Exists(scriptPath))
            {
                Console.Error.WriteLine("claude-auto-allow.ps1 was not found next to this executable:");
                Console.Error.WriteLine(scriptPath);
                return 1;
            }

            var powershellArgs = new List<string>
            {
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                scriptPath
            };
            powershellArgs.AddRange(args);

            var startInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = JoinWindowsCommandLine(powershellArgs),
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
            Console.Error.WriteLine(ex.Message);
            return 1;
        }
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
