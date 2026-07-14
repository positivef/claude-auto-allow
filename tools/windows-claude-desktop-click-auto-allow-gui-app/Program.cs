using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

[assembly: AssemblyTitle("Windows Claude Desktop Click Auto Allow GUI")]
[assembly: AssemblyDescription("GUI launcher for Windows Claude Desktop Click Auto Allow. Provenance: CAA-POSITIVEF-2026-07.")]
[assembly: AssemblyCompany("positivef")]
[assembly: AssemblyProduct("Windows Claude Desktop Click Auto Allow")]
[assembly: AssemblyCopyright("Copyright (c) 2026 positivef. All rights reserved.")]
[assembly: AssemblyTrademark("CAA-POSITIVEF-2026-07")]
[assembly: AssemblyVersion("1.4.0.0")]
[assembly: AssemblyFileVersion("1.4.0.0")]

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
    private readonly RadioButton policyAskRadioButton;
    private readonly RadioButton policyBlockRadioButton;
    private readonly RadioButton alwaysAllowRadioButton;
    private readonly RadioButton disabledRadioButton;
    private readonly ComboBox preferenceComboBox;
    private readonly CheckBox cliAutoPermissionCheckBox;
    private readonly CheckBox dryRunCheckBox;
    private readonly CheckBox diagnosticCheckBox;
    private readonly Label statusLabel;
    private readonly TextBox logBox;
    private Process worker;
    private bool loadingPolicy;

    public AutoAllowForm()
    {
        Text = "Windows Claude Desktop Click Auto Allow - positivef";
        Width = 1160;
        Height = 560;
        MinimumSize = new Size(980, 440);
        StartPosition = FormStartPosition.CenterScreen;

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 3,
            Padding = new Padding(12)
        };
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 72));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        Controls.Add(root);

        var toolbar = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = true
        };
        root.Controls.Add(toolbar, 0, 0);

        startButton = new Button { Text = "Start", Width = 92, Height = 30 };
        stopButton = new Button { Text = "Stop", Width = 92, Height = 30, Enabled = false };
        clearButton = new Button { Text = "Clear Log", Width = 92, Height = 30 };
        var modeLabel = new Label
        {
            Text = "Desktop:",
            AutoSize = true,
            Padding = new Padding(12, 8, 0, 0)
        };
        policyAskRadioButton = new RadioButton { Text = "Ask", AutoSize = true, Checked = true, Padding = new Padding(0, 6, 0, 0) };
        policyBlockRadioButton = new RadioButton { Text = "Block", AutoSize = true, Padding = new Padding(0, 6, 0, 0) };
        alwaysAllowRadioButton = new RadioButton { Text = "Always", AutoSize = true, Padding = new Padding(0, 6, 0, 0) };
        disabledRadioButton = new RadioButton { Text = "Disabled", AutoSize = true, Padding = new Padding(0, 6, 0, 0) };
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
        cliAutoPermissionCheckBox = new CheckBox { Text = "CLI auto mode", AutoSize = true, Checked = true, Padding = new Padding(12, 6, 0, 0) };
        dryRunCheckBox = new CheckBox { Text = "Dry run", AutoSize = true, Padding = new Padding(12, 6, 0, 0) };
        diagnosticCheckBox = new CheckBox { Text = "Diagnostic", AutoSize = true, Padding = new Padding(12, 6, 0, 0) };

        toolbar.Controls.Add(startButton);
        toolbar.Controls.Add(stopButton);
        toolbar.Controls.Add(clearButton);
        toolbar.Controls.Add(modeLabel);
        toolbar.Controls.Add(policyAskRadioButton);
        toolbar.Controls.Add(policyBlockRadioButton);
        toolbar.Controls.Add(alwaysAllowRadioButton);
        toolbar.Controls.Add(disabledRadioButton);
        toolbar.Controls.Add(preferenceLabel);
        toolbar.Controls.Add(preferenceComboBox);
        toolbar.Controls.Add(cliAutoPermissionCheckBox);
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
        policyAskRadioButton.CheckedChanged += delegate(object sender, EventArgs e) { SavePolicyFromCheckedRadio(sender); };
        policyBlockRadioButton.CheckedChanged += delegate(object sender, EventArgs e) { SavePolicyFromCheckedRadio(sender); };
        alwaysAllowRadioButton.CheckedChanged += delegate(object sender, EventArgs e) { SavePolicyFromCheckedRadio(sender); };
        disabledRadioButton.CheckedChanged += delegate(object sender, EventArgs e) { SavePolicyFromCheckedRadio(sender); };
        preferenceComboBox.SelectedIndexChanged += delegate { SavePolicyFromControls("Policy updated."); };
        cliAutoPermissionCheckBox.CheckedChanged += delegate { SavePolicyFromControls("Policy updated."); };
        dryRunCheckBox.CheckedChanged += delegate { SavePolicyFromControls("Policy updated."); };
        diagnosticCheckBox.CheckedChanged += delegate { SavePolicyFromControls("Policy updated."); };
        FormClosing += delegate { StopWorker(null); };

        LoadPolicyIntoControls();
        SavePolicyFromControls(null);

        Shown += delegate { StartWorker(); };
    }

    private void StartWorker()
    {
        SavePolicyFromControls(null);

        if (worker != null && !worker.HasExited)
        {
            AppendLog("Already running.");
            return;
        }

        string scriptPath;
        try
        {
            scriptPath = ResolveSafeSiblingFile("windows-claude-desktop-click-auto-allow.ps1");
        }
        catch (Exception ex)
        {
            AppendLog("ERROR: " + ex.Message);
            return;
        }

        var args = new StringBuilder();
        args.Append("-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File ");
        args.Append(Quote(scriptPath));
        args.Append(" -PolicyFile ");
        args.Append(Quote(GetPolicyFilePath()));

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

    private void LoadPolicyIntoControls()
    {
        loadingPolicy = true;
        try
        {
            string policyPath = GetPolicyFilePath();
            if (!File.Exists(policyPath))
            {
                SelectModeValue("PolicyAsk");
                SelectComboBoxValue(preferenceComboBox, "Always");
                cliAutoPermissionCheckBox.Checked = true;
                dryRunCheckBox.Checked = false;
                diagnosticCheckBox.Checked = false;
                return;
            }

            string json = File.ReadAllText(policyPath, Encoding.UTF8);
            SelectModeValue(ExtractJsonString(json, "mode", "PolicyAsk"));
            SelectComboBoxValue(preferenceComboBox, ExtractJsonString(json, "prefer", "Always"));
            cliAutoPermissionCheckBox.Checked = string.Equals(ExtractJsonString(json, "cliPermissionMode", "Auto"), "Auto", StringComparison.OrdinalIgnoreCase);
            dryRunCheckBox.Checked = ExtractJsonBool(json, "dryRun", false);
            diagnosticCheckBox.Checked = ExtractJsonBool(json, "diagnostic", false);
        }
        catch (Exception ex)
        {
            AppendLog("ERROR loading policy: " + ex.Message);
            SelectModeValue("PolicyAsk");
            SelectComboBoxValue(preferenceComboBox, "Always");
            cliAutoPermissionCheckBox.Checked = true;
            dryRunCheckBox.Checked = false;
            diagnosticCheckBox.Checked = false;
        }
        finally
        {
            loadingPolicy = false;
        }
    }

    private void SavePolicyFromControls(string message)
    {
        if (loadingPolicy)
        {
            return;
        }

        try
        {
            string policyPath = GetPolicyFilePath();
            string mode = GetSelectedMode();
            string prefer = preferenceComboBox.SelectedItem == null ? "Always" : preferenceComboBox.SelectedItem.ToString();
            string cliPermissionMode = cliAutoPermissionCheckBox.Checked ? "Auto" : "Manual";

            var json = new StringBuilder();
            json.AppendLine("{");
            json.AppendLine("  \"mode\": \"" + EscapeJson(mode) + "\",");
            json.AppendLine("  \"prefer\": \"" + EscapeJson(prefer) + "\",");
            json.AppendLine("  \"cliPermissionMode\": \"" + EscapeJson(cliPermissionMode) + "\",");
            json.AppendLine("  \"dryRun\": " + (dryRunCheckBox.Checked ? "true" : "false") + ",");
            json.AppendLine("  \"diagnostic\": " + (diagnosticCheckBox.Checked ? "true" : "false") + ",");
            json.AppendLine("  \"updatedAt\": \"" + DateTime.UtcNow.ToString("o") + "\",");
            json.AppendLine("  \"schema\": \"claude-auto-allow-policy-v1\"");
            json.AppendLine("}");

            File.WriteAllText(policyPath, json.ToString(), new UTF8Encoding(false));

            if (!string.IsNullOrEmpty(message))
            {
                string running = worker != null && !worker.HasExited ? " Applied to running worker." : string.Empty;
                AppendLog(message + " DesktopMode=" + mode + " Prefer=" + prefer + " CliPermissionMode=" + cliPermissionMode + " DryRun=" + dryRunCheckBox.Checked + " Diagnostic=" + diagnosticCheckBox.Checked + "." + running);
            }
        }
        catch (Exception ex)
        {
            AppendLog("ERROR saving policy: " + ex.Message);
        }
    }

    private void SavePolicyFromCheckedRadio(object sender)
    {
        var radioButton = sender as RadioButton;
        if (radioButton != null && radioButton.Checked)
        {
            SavePolicyFromControls("Policy updated.");
        }
    }

    private void SetRunningState(bool running)
    {
        startButton.Enabled = !running;
        stopButton.Enabled = running;
        policyAskRadioButton.Enabled = true;
        policyBlockRadioButton.Enabled = true;
        alwaysAllowRadioButton.Enabled = true;
        disabledRadioButton.Enabled = true;
        preferenceComboBox.Enabled = true;
        cliAutoPermissionCheckBox.Enabled = true;
        dryRunCheckBox.Enabled = true;
        diagnosticCheckBox.Enabled = true;
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

    private static string GetPolicyFilePath()
    {
        return Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "auto-allow-policy.json"));
    }

    private string GetSelectedMode()
    {
        if (policyBlockRadioButton.Checked)
        {
            return "PolicyBlock";
        }

        if (alwaysAllowRadioButton.Checked)
        {
            return "AlwaysAllow";
        }

        if (disabledRadioButton.Checked)
        {
            return "Disabled";
        }

        return "PolicyAsk";
    }

    private void SelectModeValue(string value)
    {
        if (string.Equals(value, "PolicyBlock", StringComparison.OrdinalIgnoreCase))
        {
            policyBlockRadioButton.Checked = true;
            return;
        }

        if (string.Equals(value, "AlwaysAllow", StringComparison.OrdinalIgnoreCase))
        {
            alwaysAllowRadioButton.Checked = true;
            return;
        }

        if (string.Equals(value, "Disabled", StringComparison.OrdinalIgnoreCase))
        {
            disabledRadioButton.Checked = true;
            return;
        }

        policyAskRadioButton.Checked = true;
    }

    private static void SelectComboBoxValue(ComboBox comboBox, string value)
    {
        for (int i = 0; i < comboBox.Items.Count; i++)
        {
            if (string.Equals(comboBox.Items[i].ToString(), value, StringComparison.OrdinalIgnoreCase))
            {
                comboBox.SelectedIndex = i;
                return;
            }
        }

        if (comboBox.Items.Count > 0)
        {
            comboBox.SelectedIndex = 0;
        }
    }

    private static string ExtractJsonString(string json, string name, string fallback)
    {
        var match = Regex.Match(json, "\"" + Regex.Escape(name) + "\"\\s*:\\s*\"(?<value>(?:\\\\.|[^\"])*)\"");
        if (!match.Success)
        {
            return fallback;
        }

        return Regex.Unescape(match.Groups["value"].Value);
    }

    private static bool ExtractJsonBool(string json, string name, bool fallback)
    {
        var match = Regex.Match(json, "\"" + Regex.Escape(name) + "\"\\s*:\\s*(?<value>true|false)", RegexOptions.IgnoreCase);
        if (!match.Success)
        {
            return fallback;
        }

        return string.Equals(match.Groups["value"].Value, "true", StringComparison.OrdinalIgnoreCase);
    }

    private static string EscapeJson(string value)
    {
        if (value == null)
        {
            return string.Empty;
        }

        return value.Replace("\\", "\\\\").Replace("\"", "\\\"");
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
