using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("Claude Auto Allow GUI")]
[assembly: AssemblyDescription("GUI launcher for Claude Auto Allow. Provenance: CAA-POSITIVEF-2026-07.")]
[assembly: AssemblyCompany("positivef")]
[assembly: AssemblyProduct("Claude Auto Allow")]
[assembly: AssemblyCopyright("Copyright (c) 2026 positivef. All rights reserved.")]
[assembly: AssemblyTrademark("CAA-POSITIVEF-2026-07")]
[assembly: AssemblyVersion("1.2.0.0")]
[assembly: AssemblyFileVersion("1.2.0.0")]

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new AutoAllowForm());
    }
}

internal sealed class AutoAllowForm : Form
{
    private const string Provenance = "CAA-POSITIVEF-2026-07";

    private readonly Button startButton;
    private readonly Button stopButton;
    private readonly Button clearButton;
    private readonly ComboBox preferenceComboBox;
    private readonly CheckBox dryRunCheckBox;
    private readonly CheckBox diagnosticCheckBox;
    private readonly Label statusLabel;
    private readonly TextBox logBox;
    private Process worker;

    public AutoAllowForm()
    {
        Text = "Claude Auto Allow - positivef";
        Width = 840;
        Height = 560;
        MinimumSize = new Size(720, 420);
        StartPosition = FormStartPosition.CenterScreen;

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 3,
            Padding = new Padding(12)
        };
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 44));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        Controls.Add(root);

        var toolbar = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false
        };
        root.Controls.Add(toolbar, 0, 0);

        startButton = new Button { Text = "Start", Width = 92, Height = 30 };
        stopButton = new Button { Text = "Stop", Width = 92, Height = 30, Enabled = false };
        clearButton = new Button { Text = "Clear Log", Width = 92, Height = 30 };
        var preferenceLabel = new Label
        {
            Text = "Prefer:",
            AutoSize = true,
            Padding = new Padding(12, 8, 0, 0)
        };
        preferenceComboBox = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Width = 112
        };
        preferenceComboBox.Items.Add("Always");
        preferenceComboBox.Items.Add("Once");
        preferenceComboBox.SelectedIndex = 0;
        dryRunCheckBox = new CheckBox { Text = "Dry run", AutoSize = true, Padding = new Padding(12, 6, 0, 0) };
        diagnosticCheckBox = new CheckBox { Text = "Diagnostic", AutoSize = true, Padding = new Padding(12, 6, 0, 0) };

        toolbar.Controls.Add(startButton);
        toolbar.Controls.Add(stopButton);
        toolbar.Controls.Add(clearButton);
        toolbar.Controls.Add(preferenceLabel);
        toolbar.Controls.Add(preferenceComboBox);
        toolbar.Controls.Add(dryRunCheckBox);
        toolbar.Controls.Add(diagnosticCheckBox);

        statusLabel = new Label
        {
            Dock = DockStyle.Fill,
            Text = "Stopped",
            ForeColor = Color.Firebrick,
            TextAlign = ContentAlignment.MiddleLeft
        };
        root.Controls.Add(statusLabel, 0, 1);

        logBox = new TextBox
        {
            Dock = DockStyle.Fill,
            Multiline = true,
            ReadOnly = true,
            ScrollBars = ScrollBars.Both,
            WordWrap = false,
            Font = new Font(FontFamily.GenericMonospace, 9.0f),
            BackColor = Color.FromArgb(18, 18, 18),
            ForeColor = Color.Gainsboro
        };
        root.Controls.Add(logBox, 0, 2);

        startButton.Click += delegate { StartWorker(); };
        stopButton.Click += delegate { StopWorker("Stopped by user."); };
        clearButton.Click += delegate { logBox.Clear(); };
        FormClosing += delegate { StopWorker(null); };

        Shown += delegate { StartWorker(); };
    }

    private void StartWorker()
    {
        if (worker != null && !worker.HasExited)
        {
            AppendLog("Already running.");
            return;
        }

        string scriptPath;
        try
        {
            scriptPath = ResolveSafeSiblingFile("claude-auto-allow.ps1");
        }
        catch (Exception ex)
        {
            AppendLog("ERROR: " + ex.Message);
            return;
        }

        var args = new StringBuilder();
        args.Append("-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File ");
        args.Append(Quote(scriptPath));
        args.Append(" -Prefer ");
        args.Append(preferenceComboBox.SelectedItem == null ? "Always" : preferenceComboBox.SelectedItem.ToString());
        if (dryRunCheckBox.Checked)
        {
            args.Append(" -DryRun");
        }
        if (diagnosticCheckBox.Checked)
        {
            args.Append(" -Diagnostic");
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = args.ToString(),
            WorkingDirectory = AppDomain.CurrentDomain.BaseDirectory,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };

        try
        {
            worker = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
            worker.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e)
            {
                if (e.Data != null) AppendLog(e.Data);
            };
            worker.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e)
            {
                if (e.Data != null) AppendLog("ERROR: " + e.Data);
            };
            worker.Exited += delegate
            {
                BeginInvokeIfNeeded(delegate
                {
                    SetRunningState(false);
                    AppendLog("Worker exited.");
                });
            };

            worker.Start();
            worker.BeginOutputReadLine();
            worker.BeginErrorReadLine();
            SetRunningState(true);
            AppendLog("Started. Owner=positivef Provenance=" + Provenance);
        }
        catch (Exception ex)
        {
            SetRunningState(false);
            AppendLog("ERROR: " + ex.Message);
        }
    }

    private void StopWorker(string message)
    {
        try
        {
            if (worker != null && !worker.HasExited)
            {
                worker.Kill();
                worker.WaitForExit(1000);
            }
        }
        catch (Exception ex)
        {
            AppendLog("ERROR stopping worker: " + ex.Message);
        }
        finally
        {
            SetRunningState(false);
            if (!string.IsNullOrEmpty(message))
            {
                AppendLog(message);
            }
        }
    }

    private void SetRunningState(bool running)
    {
        startButton.Enabled = !running;
        stopButton.Enabled = running;
        preferenceComboBox.Enabled = !running;
        dryRunCheckBox.Enabled = !running;
        diagnosticCheckBox.Enabled = !running;
        statusLabel.Text = running ? "Running" : "Stopped";
        statusLabel.ForeColor = running ? Color.ForestGreen : Color.Firebrick;
    }

    private void AppendLog(string line)
    {
        BeginInvokeIfNeeded(delegate
        {
            logBox.AppendText(line + Environment.NewLine);
        });
    }

    private void BeginInvokeIfNeeded(Action action)
    {
        if (IsDisposed)
        {
            return;
        }

        if (InvokeRequired)
        {
            BeginInvoke(action);
        }
        else
        {
            action();
        }
    }

    private static string Quote(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
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
}
