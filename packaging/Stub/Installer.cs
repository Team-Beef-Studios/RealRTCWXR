using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace RealRTCWXRSetup
{
    internal static class Program
    {
        public const string ProductName = "RealRTCW XR";
        public const string ProductVersion = "@@VERSION@@";
        public const string DataNeeded = "@@DATA_NEEDED@@";
        public const string SetupScript = "Setup-RealRTCWXR.ps1";
        public const string GameExe = "RealRTCWXR.exe";

        // Setup-RealRTCWXR.ps1 returns this when it needs the user to supply game files.
        public const int ExitNeedsFiles = 2;

        [DllImport("kernel32.dll")]
        private static extern bool AttachConsole(int processId);

        [STAThread]
        private static int Main(string[] args)
        {
            string target = null;
            bool silent = false;
            bool force = false;
            bool manual = false;
            bool shortcut = true;

            foreach (string a in args)
            {
                if (a.StartsWith("/D=", StringComparison.OrdinalIgnoreCase))
                    target = a.Substring(3).Trim('"');
                else if (a.Equals("/S", StringComparison.OrdinalIgnoreCase))
                    silent = true;
                else if (a.Equals("/FORCE", StringComparison.OrdinalIgnoreCase))
                    force = true;
                else if (a.Equals("/MANUAL", StringComparison.OrdinalIgnoreCase))
                    manual = true;
                else if (a.Equals("/NOSHORTCUT", StringComparison.OrdinalIgnoreCase))
                    shortcut = false;
            }

            if (string.IsNullOrEmpty(target))
                target = DefaultInstallPath();

            if (silent)
            {
                // A winexe owns no console, so borrow the caller's to make /S readable.
                AttachConsole(-1);
                return RunSilent(target, force, manual, shortcut);
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            using (MainForm form = new MainForm(target, force))
            {
                Application.Run(form);
                return form.ExitCode;
            }
        }

        public static string DefaultInstallPath()
        {
            string root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return Path.Combine(Path.Combine(root, "Programs"), ProductName);
        }

        private static int RunSilent(string target, bool force, bool manual, bool shortcut)
        {
            try
            {
                Installer.Extract(target, null);
                return Installer.RunSetup(target, force, manual, shortcut, Console.WriteLine);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex.Message);
                return 1;
            }
        }
    }

    // A read-only window onto part of another stream. ZipArchive reads the central
    // directory from the end of the stream, so the payload must not include the footer.
    internal sealed class SubStream : Stream
    {
        private readonly Stream _inner;
        private readonly long _origin;
        private readonly long _length;
        private long _position;

        public SubStream(Stream inner, long origin, long length)
        {
            _inner = inner;
            _origin = origin;
            _length = length;
            _inner.Position = origin;
        }

        public override bool CanRead { get { return true; } }
        public override bool CanSeek { get { return true; } }
        public override bool CanWrite { get { return false; } }
        public override long Length { get { return _length; } }

        public override long Position
        {
            get { return _position; }
            set { Seek(value, SeekOrigin.Begin); }
        }

        public override int Read(byte[] buffer, int offset, int count)
        {
            long remaining = _length - _position;
            if (remaining <= 0) return 0;
            if (count > remaining) count = (int)remaining;

            _inner.Position = _origin + _position;
            int read = _inner.Read(buffer, offset, count);
            _position += read;
            return read;
        }

        public override long Seek(long offset, SeekOrigin origin)
        {
            long p;
            if (origin == SeekOrigin.Begin) p = offset;
            else if (origin == SeekOrigin.Current) p = _position + offset;
            else p = _length + offset;

            if (p < 0 || p > _length)
                throw new IOException("Seek outside the payload.");

            _position = p;
            _inner.Position = _origin + p;
            return p;
        }

        public override void Flush() { }
        public override void SetLength(long value) { throw new NotSupportedException(); }
        public override void Write(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }

        protected override void Dispose(bool disposing)
        {
            if (disposing) _inner.Dispose();
            base.Dispose(disposing);
        }
    }

    internal static class Installer
    {
        // Make-Package.ps1 appends: [zip][int64 zip length][8 byte magic].
        private static readonly byte[] Magic = Encoding.ASCII.GetBytes("RTCWXRP1");
        private const int FooterSize = 16;

        private static SubStream OpenPayload()
        {
            string self = Process.GetCurrentProcess().MainModule.FileName;
            FileStream fs = new FileStream(self, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);

            try
            {
                if (fs.Length < FooterSize)
                    throw new InvalidOperationException("The installer is corrupt: it is too small to hold a payload.");

                byte[] footer = new byte[FooterSize];
                fs.Position = fs.Length - FooterSize;
                if (fs.Read(footer, 0, FooterSize) != FooterSize)
                    throw new InvalidOperationException("The installer is corrupt: the footer is unreadable.");

                for (int i = 0; i < Magic.Length; i++)
                {
                    if (footer[8 + i] != Magic[i])
                        throw new InvalidOperationException("The installer is corrupt: the payload marker is absent.");
                }

                long zipLength = BitConverter.ToInt64(footer, 0);
                long origin = fs.Length - FooterSize - zipLength;
                if (zipLength <= 0 || origin < 0)
                    throw new InvalidOperationException("The installer is corrupt: the payload length is wrong.");

                return new SubStream(fs, origin, zipLength);
            }
            catch
            {
                fs.Dispose();
                throw;
            }
        }

        public static void Extract(string target, Action<int, int, string> progress)
        {
            Directory.CreateDirectory(target);

            using (SubStream payload = OpenPayload())
            using (ZipArchive zip = new ZipArchive(payload, ZipArchiveMode.Read))
            {
                List<ZipArchiveEntry> files = new List<ZipArchiveEntry>();
                foreach (ZipArchiveEntry e in zip.Entries)
                {
                    if (!string.IsNullOrEmpty(e.Name))
                        files.Add(e);
                }

                for (int i = 0; i < files.Count; i++)
                {
                    ZipArchiveEntry entry = files[i];
                    string full = SafeCombine(target, entry.FullName);
                    Directory.CreateDirectory(Path.GetDirectoryName(full));

                    if (progress != null)
                        progress(i + 1, files.Count, entry.FullName);

                    using (Stream src = entry.Open())
                    using (FileStream dst = new FileStream(full, FileMode.Create, FileAccess.Write, FileShare.None))
                        src.CopyTo(dst);

                    File.SetLastWriteTime(full, entry.LastWriteTime.LocalDateTime);
                }
            }
        }

        // Rejects zip entries that would escape the install folder (zip-slip).
        private static string SafeCombine(string root, string entryName)
        {
            string combined = Path.GetFullPath(Path.Combine(root, entryName.Replace('/', '\\')));
            string rootFull = Path.GetFullPath(root);
            if (!rootFull.EndsWith("\\"))
                rootFull += "\\";

            if (!combined.StartsWith(rootFull, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("The payload contains an unsafe path: " + entryName);

            return combined;
        }

        public static int RunSetup(string target, bool force, bool manual, bool shortcut, Action<string> log)
        {
            string script = Path.Combine(target, Program.SetupScript);
            if (!File.Exists(script))
                throw new FileNotFoundException("The setup script is missing: " + script);

            StringBuilder cmd = new StringBuilder();
            cmd.Append("-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"").Append(script).Append("\"");
            cmd.Append(" -InstallRoot \"").Append(target.TrimEnd('\\')).Append("\"");
            if (force) cmd.Append(" -SkipVersionCheck");
            if (manual) cmd.Append(" -ManualData");
            if (shortcut) cmd.Append(" -CreateShortcut");

            ProcessStartInfo psi = new ProcessStartInfo("powershell.exe", cmd.ToString());
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.WorkingDirectory = target;

            using (Process p = new Process())
            {
                p.StartInfo = psi;
                p.OutputDataReceived += delegate(object s, DataReceivedEventArgs e)
                {
                    if (e.Data != null) log(e.Data);
                };
                p.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e)
                {
                    if (e.Data != null) log("ERROR: " + e.Data);
                };
                p.Start();
                p.BeginOutputReadLine();
                p.BeginErrorReadLine();
                p.WaitForExit();
                return p.ExitCode;
            }
        }
    }

    internal sealed class MainForm : Form
    {
        private readonly TextBox _path;
        private readonly Button _browse;
        private readonly Button _install;
        private readonly Button _play;
        private readonly Button _close;
        private readonly TextBox _log;
        private readonly ProgressBar _bar;
        private readonly RadioButton _fromSteam;
        private readonly RadioButton _fromUser;
        private readonly CheckBox _shortcut;
        private readonly bool _force;

        public int ExitCode { get; private set; }

        public MainForm(string defaultPath, bool force)
        {
            _force = force;
            ExitCode = 1;

            Text = Program.ProductName + " " + Program.ProductVersion + " - Setup";
            Font = new Font("Segoe UI", 9f);
            // WinForms auto-scaling rescales the hand-coded layout by a factor that depends
            // on the runtime font metrics, which shrank the form. Size off the font height
            // instead: it already grows with the display DPI.
            AutoScaleMode = AutoScaleMode.None;
            StartPosition = FormStartPosition.CenterScreen;
            MinimizeBox = false;

            int em = Font.Height;
            ClientSize = new Size(em * 44, em * 35);
            MinimumSize = new Size(em * 38, em * 31);

            Label intro = new Label();
            intro.Text = "This installs " + Program.ProductName + ". " + Program.DataNeeded;
            intro.AutoSize = true;
            intro.Dock = DockStyle.Fill;
            intro.Margin = new Padding(0, 0, 0, 10);

            Label lbl = new Label();
            lbl.Text = "Install folder:";
            lbl.AutoSize = true;
            lbl.Anchor = AnchorStyles.Left;
            lbl.Margin = new Padding(0, 0, 8, 0);

            _path = new TextBox();
            _path.Text = defaultPath;
            _path.Dock = DockStyle.Fill;
            _path.Margin = new Padding(0, 0, 8, 0);

            _browse = new Button();
            _browse.Text = "Browse...";
            _browse.AutoSize = true;
            _browse.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            _browse.Anchor = AnchorStyles.Left;
            _browse.Padding = new Padding(10, 2, 10, 2);
            _browse.Margin = new Padding(0);
            _browse.Click += OnBrowse;

            TableLayoutPanel pathRow = new TableLayoutPanel();
            pathRow.Dock = DockStyle.Fill;
            pathRow.AutoSize = true;
            pathRow.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            pathRow.ColumnCount = 3;
            pathRow.RowCount = 1;
            pathRow.Margin = new Padding(0);
            pathRow.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            pathRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
            pathRow.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            pathRow.Controls.Add(lbl, 0, 0);
            pathRow.Controls.Add(_path, 1, 0);
            pathRow.Controls.Add(_browse, 2, 0);

            _fromSteam = new RadioButton();
            _fromSteam.Text = "Copy the game data from my Steam installation";
            _fromSteam.Checked = true;
            _fromSteam.AutoSize = true;
            _fromSteam.Margin = new Padding(0, 2, 0, 2);

            _fromUser = new RadioButton();
            _fromUser.Text = "I will provide the game files myself (GOG, disc, or another copy)";
            _fromUser.AutoSize = true;
            _fromUser.Margin = new Padding(0, 2, 0, 2);

            GroupBox source = new GroupBox();
            source.Text = "Game data";
            source.Dock = DockStyle.Fill;
            source.AutoSize = true;
            source.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            source.Margin = new Padding(0, 10, 0, 0);
            source.Padding = new Padding(10, 4, 10, 8);

            FlowLayoutPanel sourceFlow = new FlowLayoutPanel();
            sourceFlow.Dock = DockStyle.Fill;
            sourceFlow.AutoSize = true;
            sourceFlow.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            sourceFlow.FlowDirection = FlowDirection.TopDown;
            sourceFlow.WrapContents = false;
            sourceFlow.Margin = new Padding(0);
            sourceFlow.Controls.Add(_fromSteam);
            sourceFlow.Controls.Add(_fromUser);
            source.Controls.Add(sourceFlow);

            _shortcut = new CheckBox();
            _shortcut.Text = "Put a RealRTCW XR shortcut on my desktop";
            _shortcut.Checked = true;
            _shortcut.AutoSize = true;
            _shortcut.Dock = DockStyle.Fill;
            _shortcut.Margin = new Padding(0, 10, 0, 0);

            _bar = new ProgressBar();
            _bar.Height = 14;
            _bar.Anchor = AnchorStyles.Left | AnchorStyles.Right;
            _bar.Margin = new Padding(0, 10, 0, 8);

            _log = new TextBox();
            _log.Multiline = true;
            _log.ReadOnly = true;
            _log.ScrollBars = ScrollBars.Both;
            _log.WordWrap = false;
            _log.BackColor = SystemColors.Window;
            _log.Font = new Font("Consolas", 8.5f);
            _log.Dock = DockStyle.Fill;
            _log.Margin = new Padding(0);

            _install = new Button();
            _install.Text = "Install";
            _install.Click += OnInstall;

            _play = new Button();
            _play.Text = "Play";
            _play.Enabled = false;
            _play.Click += OnPlay;

            _close = new Button();
            _close.Text = "Close";
            _close.Click += delegate { Close(); };

            FlowLayoutPanel buttons = new FlowLayoutPanel();
            buttons.Dock = DockStyle.Fill;
            buttons.AutoSize = true;
            buttons.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            buttons.FlowDirection = FlowDirection.RightToLeft;
            buttons.WrapContents = false;
            buttons.Margin = new Padding(0, 10, 0, 0);

            // RightToLeft flow puts the first control added on the right edge.
            foreach (Button b in new Button[] { _close, _play, _install })
            {
                b.AutoSize = true;
                b.AutoSizeMode = AutoSizeMode.GrowAndShrink;
                b.Padding = new Padding(14, 3, 14, 3);
                b.Margin = new Padding(8, 0, 0, 0);
                b.MinimumSize = new Size(84, 0);
                buttons.Controls.Add(b);
            }

            TableLayoutPanel root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.Padding = new Padding(12);
            root.ColumnCount = 1;
            root.RowCount = 7;
            root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.Controls.Add(intro, 0, 0);
            root.Controls.Add(pathRow, 0, 1);
            root.Controls.Add(source, 0, 2);
            root.Controls.Add(_shortcut, 0, 3);
            root.Controls.Add(_bar, 0, 4);
            root.Controls.Add(_log, 0, 5);
            root.Controls.Add(buttons, 0, 6);

            Controls.Add(root);
            AcceptButton = _install;

            // A long default path otherwise opens scrolled to its end and fully selected.
            Shown += delegate
            {
                _path.SelectionStart = 0;
                _path.SelectionLength = 0;
                _install.Focus();
            };
        }

        private void OnBrowse(object sender, EventArgs e)
        {
            using (FolderBrowserDialog dlg = new FolderBrowserDialog())
            {
                dlg.Description = "Choose the folder to install " + Program.ProductName + " into.";
                dlg.ShowNewFolderButton = true;
                if (dlg.ShowDialog(this) != DialogResult.OK)
                    return;

                string chosen = dlg.SelectedPath;
                // Do not scatter the game across a folder the user already keeps other things in.
                if (!string.Equals(Path.GetFileName(chosen.TrimEnd('\\')), Program.ProductName, StringComparison.OrdinalIgnoreCase))
                    chosen = Path.Combine(chosen, Program.ProductName);

                _path.Text = chosen;
            }
        }

        private void OnPlay(object sender, EventArgs e)
        {
            string exe = Path.Combine(_path.Text.Trim(), Program.GameExe);
            if (!File.Exists(exe))
            {
                MessageBox.Show(this, "Cannot find " + exe, Program.ProductName, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            ProcessStartInfo psi = new ProcessStartInfo(exe);
            psi.WorkingDirectory = _path.Text.Trim();
            psi.UseShellExecute = true;
            Process.Start(psi);
            Close();
        }

        private void OnInstall(object sender, EventArgs e)
        {
            string target = _path.Text.Trim();
            if (target.Length == 0)
            {
                MessageBox.Show(this, "Choose an install folder.", Program.ProductName, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            bool manual = _fromUser.Checked;
            bool shortcut = _shortcut.Checked;

            SetBusy(true);
            _log.Clear();
            _bar.Style = ProgressBarStyle.Continuous;
            _bar.Value = 0;

            Thread worker = new Thread(delegate() { Work(target, manual, shortcut); });
            worker.IsBackground = true;
            worker.Start();
        }

        private void Work(string target, bool manual, bool shortcut)
        {
            try
            {
                Log("Unpacking to " + target);
                Installer.Extract(target, delegate(int done, int total, string name)
                {
                    Invoke((MethodInvoker)delegate
                    {
                        _bar.Maximum = total;
                        _bar.Value = done;
                    });
                    Log("  " + name);
                });

                Log("");
                Invoke((MethodInvoker)delegate { _bar.Style = ProgressBarStyle.Marquee; });

                int code = Installer.RunSetup(target, _force, manual, shortcut, Log);

                Invoke((MethodInvoker)delegate
                {
                    _bar.Style = ProgressBarStyle.Continuous;
                    _bar.Value = _bar.Maximum;
                    ExitCode = code;
                    _play.Enabled = (code == 0);
                    SetBusy(false);
                });

                if (code == 0)
                {
                    Log("\r\nInstall complete. Press Play to start " + Program.ProductName + ".");
                }
                else if (code == Program.ExitNeedsFiles)
                {
                    Log("\r\nCopy the files listed above, then press Install again.");
                    OpenMainFolder(target);
                }
                else
                {
                    Log("\r\nInstall did not finish. Read the messages above.");
                }
            }
            catch (Exception ex)
            {
                Log("ERROR: " + ex.Message);
                Invoke((MethodInvoker)delegate
                {
                    _bar.Style = ProgressBarStyle.Continuous;
                    _bar.Value = 0;
                    ExitCode = 1;
                    SetBusy(false);
                });
            }
        }

        private void OpenMainFolder(string target)
        {
            try
            {
                string main = Path.Combine(target, "Main");
                if (Directory.Exists(main))
                    Process.Start("explorer.exe", "\"" + main + "\"");
            }
            catch
            {
                // Explorer is a convenience. The log already names the folder.
            }
        }

        private void SetBusy(bool busy)
        {
            _install.Enabled = !busy;
            _browse.Enabled = !busy;
            _path.Enabled = !busy;
            _fromSteam.Enabled = !busy;
            _fromUser.Enabled = !busy;
            _shortcut.Enabled = !busy;
        }

        private void Log(string line)
        {
            if (InvokeRequired)
            {
                BeginInvoke((MethodInvoker)delegate { Log(line); });
                return;
            }

            _log.AppendText(line + "\r\n");
        }
    }
}
