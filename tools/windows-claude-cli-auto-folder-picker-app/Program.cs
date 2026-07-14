using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("Windows Claude CLI Auto Folder Picker")]
[assembly: AssemblyDescription("Windows folder picker launcher for Claude CLI Auto Wrapper. Provenance: CLAUDE-CLI-AUTO-POSITIVEF-2026-07.")]
[assembly: AssemblyCompany("positivef")]
[assembly: AssemblyProduct("Windows Claude CLI Auto Folder Picker")]
[assembly: AssemblyCopyright("Copyright (c) 2026 positivef. All rights reserved.")]
[assembly: AssemblyTrademark("CLAUDE-CLI-AUTO-POSITIVEF-2026-07")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

internal static class Program
{
    private const string Provenance = "CLAUDE-CLI-AUTO-POSITIVEF-2026-07";

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            if (args.Any(arg => string.Equals(arg, "--self-test", StringComparison.OrdinalIgnoreCase)))
            {
                ResolveSafeSiblingFile("windows-claude-cli-auto-wrapper.exe");
                return 0;
            }

            string wrapperPath = ResolveSafeSiblingFile("windows-claude-cli-auto-wrapper.exe");
            string selectedFolder;
            if (!TrySelectFolder(out selectedFolder))
            {
                return 0;
            }

            StartWrapperInCmd(wrapperPath, selectedFolder, args);
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                ex.Message,
                "Windows Claude CLI Auto Folder Picker",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
            return 1;
        }
    }

    private static bool TrySelectFolder(out string selectedFolder)
    {
        selectedFolder = string.Empty;

        if (VistaFolderDialog.TryShow(out selectedFolder))
        {
            return true;
        }

        using (var dialog = new FolderBrowserDialog())
        {
            dialog.Description = "Select the project folder for Claude Code CLI auto wrapper.";
            dialog.ShowNewFolderButton = true;
            dialog.SelectedPath = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);

            if (dialog.ShowDialog() != DialogResult.OK)
            {
                return false;
            }

            selectedFolder = dialog.SelectedPath;
            return !string.IsNullOrWhiteSpace(selectedFolder);
        }
    }

    private static void StartWrapperInCmd(string wrapperPath, string selectedFolder, IEnumerable<string> args)
    {
        string commandLine = QuoteForCmdArgument(wrapperPath);
        foreach (string arg in args)
        {
            commandLine += " " + QuoteForCmdArgument(arg);
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = "cmd.exe",
            Arguments = "/k " + QuoteForCmdCommand(commandLine),
            WorkingDirectory = selectedFolder,
            UseShellExecute = true
        };

        Process.Start(startInfo);
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

    private static string QuoteForCmdCommand(string value)
    {
        return "\"" + value + "\"";
    }

    private static string QuoteForCmdArgument(string value)
    {
        if (value.Length == 0)
        {
            return "\"\"";
        }

        bool needsQuotes = value.Any(ch => char.IsWhiteSpace(ch) || ch == '"');
        if (!needsQuotes)
        {
            return value;
        }

        return "\"" + value.Replace("\"", "\"\"") + "\"";
    }

    private static class VistaFolderDialog
    {
        private const uint FOS_PICKFOLDERS = 0x00000020;
        private const uint FOS_FORCEFILESYSTEM = 0x00000040;
        private const uint FOS_PATHMUSTEXIST = 0x00000800;
        private const uint FOS_NOCHANGEDIR = 0x00000008;
        private const uint SIGDN_FILESYSPATH = 0x80058000;
        private const int ERROR_CANCELLED = unchecked((int)0x800704C7);

        public static bool TryShow(out string selectedFolder)
        {
            selectedFolder = string.Empty;

            IFileOpenDialog dialog = null;
            IShellItem result = null;
            IntPtr pathPointer = IntPtr.Zero;

            try
            {
                dialog = (IFileOpenDialog)new FileOpenDialog();
                uint options;
                dialog.GetOptions(out options);
                dialog.SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR);
                dialog.SetTitle("Select the project folder for Claude Code CLI auto wrapper");

                int hr = dialog.Show(IntPtr.Zero);
                if (hr == ERROR_CANCELLED)
                {
                    return false;
                }

                Marshal.ThrowExceptionForHR(hr);
                dialog.GetResult(out result);
                result.GetDisplayName(SIGDN_FILESYSPATH, out pathPointer);
                selectedFolder = Marshal.PtrToStringUni(pathPointer) ?? string.Empty;
                return !string.IsNullOrWhiteSpace(selectedFolder);
            }
            catch (COMException ex)
            {
                if (ex.ErrorCode == ERROR_CANCELLED)
                {
                    return false;
                }

                selectedFolder = string.Empty;
                return false;
            }
            finally
            {
                if (pathPointer != IntPtr.Zero)
                {
                    Marshal.FreeCoTaskMem(pathPointer);
                }

                if (result != null)
                {
                    Marshal.ReleaseComObject(result);
                }

                if (dialog != null)
                {
                    Marshal.ReleaseComObject(dialog);
                }
            }
        }

        [ComImport]
        [Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")]
        private class FileOpenDialog
        {
        }

        [ComImport]
        [Guid("42f85136-db7e-439c-85f1-e4075d135fc8")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IFileOpenDialog
        {
            [PreserveSig]
            int Show(IntPtr parent);
            void SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
            void SetFileTypeIndex(uint iFileType);
            void GetFileTypeIndex(out uint piFileType);
            void Advise(IntPtr pfde, out uint pdwCookie);
            void Unadvise(uint dwCookie);
            void SetOptions(uint fos);
            void GetOptions(out uint pfos);
            void SetDefaultFolder(IShellItem psi);
            void SetFolder(IShellItem psi);
            void GetFolder(out IShellItem ppsi);
            void GetCurrentSelection(out IShellItem ppsi);
            void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
            void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
            void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
            void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
            void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
            void GetResult(out IShellItem ppsi);
            void AddPlace(IShellItem psi, uint fdap);
            void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
            void Close(int hr);
            void SetClientGuid(ref Guid guid);
            void ClearClientData();
            void SetFilter(IntPtr pFilter);
            void GetResults(IntPtr ppenum);
            void GetSelectedItems(IntPtr ppsai);
        }

        [ComImport]
        [Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IShellItem
        {
            void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppv);
            void GetParent(out IShellItem ppsi);
            void GetDisplayName(uint sigdnName, out IntPtr ppszName);
            void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
            void Compare(IShellItem psi, uint hint, out int piOrder);
        }
    }
}
