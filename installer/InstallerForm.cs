using System;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace VortexLaunchBridge.Installer
{
    internal sealed class InstallerForm : Form
    {
        private TextBox millenniumPathTextBox;
        private Button browseButton;
        private Label destinationValueLabel;
        private TextBox logTextBox;
        private ProgressBar progressBar;
        private Button installButton;
        private Button deleteButton;
        private Button cancelButton;
        private CancellationTokenSource operationCancellation;
        private bool operationRunning;

        public InstallerForm()
        {
            Text = InstallerConstants.ProductName + " Setup";
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = true;
            ShowIcon = true;
            Icon = SystemIcons.Application;
            ClientSize = new Size(680, 485);
            MinimumSize = new Size(696, 524);
            Font = new Font("Segoe UI", 9F, FontStyle.Regular, GraphicsUnit.Point);
            AutoScaleMode = AutoScaleMode.Dpi;

            TableLayoutPanel root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.Padding = new Padding(18);
            root.ColumnCount = 1;
            root.RowCount = 6;
            root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 70F));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 105F));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 28F));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 22F));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 45F));
            Controls.Add(root);

            root.Controls.Add(CreateHeader(), 0, 0);
            root.Controls.Add(CreateDirectoryPanel(), 0, 1);

            Label statusLabel = new Label();
            statusLabel.Text = "Installation details";
            statusLabel.Dock = DockStyle.Fill;
            statusLabel.TextAlign = ContentAlignment.BottomLeft;
            statusLabel.Font = new Font(Font, FontStyle.Bold);
            root.Controls.Add(statusLabel, 0, 2);

            logTextBox = new TextBox();
            logTextBox.Dock = DockStyle.Fill;
            logTextBox.Multiline = true;
            logTextBox.ReadOnly = true;
            logTextBox.ScrollBars = ScrollBars.Vertical;
            logTextBox.BackColor = SystemColors.Window;
            logTextBox.WordWrap = true;
            root.Controls.Add(logTextBox, 0, 3);

            progressBar = new ProgressBar();
            progressBar.Dock = DockStyle.Fill;
            progressBar.Style = ProgressBarStyle.Continuous;
            progressBar.Minimum = 0;
            progressBar.Maximum = 100;
            root.Controls.Add(progressBar, 0, 4);

            FlowLayoutPanel buttons = new FlowLayoutPanel();
            buttons.Dock = DockStyle.Fill;
            buttons.FlowDirection = FlowDirection.RightToLeft;
            buttons.WrapContents = false;
            buttons.Padding = new Padding(0, 8, 0, 0);

            cancelButton = CreateButton("Cancel", 94);
            cancelButton.DialogResult = DialogResult.None;
            cancelButton.Click += CancelButtonClick;

            deleteButton = CreateButton("Delete", 94);
            deleteButton.Click += DeleteButtonClick;

            installButton = CreateButton("Install/Repair", 116);
            installButton.Click += InstallButtonClick;

            buttons.Controls.Add(cancelButton);
            buttons.Controls.Add(deleteButton);
            buttons.Controls.Add(installButton);
            root.Controls.Add(buttons, 0, 5);

            AcceptButton = installButton;
            CancelButton = cancelButton;

            Load += InstallerFormLoad;
            FormClosing += InstallerFormClosing;
        }

        private Control CreateHeader()
        {
            TableLayoutPanel header = new TableLayoutPanel();
            header.Dock = DockStyle.Fill;
            header.ColumnCount = 2;
            header.RowCount = 2;
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 52F));
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            header.RowStyles.Add(new RowStyle(SizeType.Absolute, 34F));
            header.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

            PictureBox icon = new PictureBox();
            icon.Image = SystemIcons.Application.ToBitmap();
            icon.SizeMode = PictureBoxSizeMode.CenterImage;
            icon.Dock = DockStyle.Fill;
            header.Controls.Add(icon, 0, 0);
            header.SetRowSpan(icon, 2);

            Label title = new Label();
            title.Text = InstallerConstants.ProductName;
            title.Font = new Font("Segoe UI Semibold", 16F, FontStyle.Bold, GraphicsUnit.Point);
            title.Dock = DockStyle.Fill;
            title.TextAlign = ContentAlignment.MiddleLeft;
            header.Controls.Add(title, 1, 0);

            Label description = new Label();
            description.Text = "Downloads the latest source, performs the pinned production build, and installs the validated plugin into Millennium.";
            description.Dock = DockStyle.Fill;
            description.ForeColor = SystemColors.GrayText;
            description.TextAlign = ContentAlignment.TopLeft;
            header.Controls.Add(description, 1, 1);
            return header;
        }

        private Control CreateDirectoryPanel()
        {
            GroupBox group = new GroupBox();
            group.Text = "Millennium location";
            group.Dock = DockStyle.Fill;

            TableLayoutPanel layout = new TableLayoutPanel();
            layout.Dock = DockStyle.Fill;
            layout.Padding = new Padding(9, 6, 9, 7);
            layout.ColumnCount = 2;
            layout.RowCount = 3;
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 92F));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 28F));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 22F));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 22F));
            group.Controls.Add(layout);

            millenniumPathTextBox = new TextBox();
            millenniumPathTextBox.Dock = DockStyle.Fill;
            millenniumPathTextBox.TextChanged += MillenniumPathTextChanged;
            layout.Controls.Add(millenniumPathTextBox, 0, 0);

            browseButton = CreateButton("Browse...", 84);
            browseButton.Dock = DockStyle.Fill;
            browseButton.Margin = new Padding(7, 0, 0, 2);
            browseButton.Click += BrowseButtonClick;
            layout.Controls.Add(browseButton, 1, 0);

            Label destinationLabel = new Label();
            destinationLabel.Text = "Plugin destination:";
            destinationLabel.Dock = DockStyle.Fill;
            destinationLabel.TextAlign = ContentAlignment.MiddleLeft;
            destinationLabel.ForeColor = SystemColors.GrayText;
            layout.Controls.Add(destinationLabel, 0, 1);
            layout.SetColumnSpan(destinationLabel, 2);

            destinationValueLabel = new Label();
            destinationValueLabel.Dock = DockStyle.Fill;
            destinationValueLabel.TextAlign = ContentAlignment.MiddleLeft;
            destinationValueLabel.AutoEllipsis = true;
            layout.Controls.Add(destinationValueLabel, 0, 2);
            layout.SetColumnSpan(destinationValueLabel, 2);

            return group;
        }

        private static Button CreateButton(string text, int width)
        {
            Button button = new Button();
            button.Text = text;
            button.Width = width;
            button.Height = 30;
            button.UseVisualStyleBackColor = true;
            return button;
        }

        private void InstallerFormLoad(object sender, EventArgs eventArgs)
        {
            string detected = MillenniumPathResolver.DiscoverMillenniumDirectory();
            if (!String.IsNullOrWhiteSpace(detected))
            {
                millenniumPathTextBox.Text = detected;
                AppendLog("Detected Millennium at " + detected + ".");
            }
            else
            {
                AppendLog("Millennium was not detected automatically. Select its installation directory.");
            }

            AppendLog("Source: " + InstallerConstants.RepositoryUrl + " (" + InstallerConstants.RepositoryBranch + ")");
            AppendLog("Steam must be fully closed before installing, repairing, or deleting the plugin.");
        }

        private void BrowseButtonClick(object sender, EventArgs eventArgs)
        {
            using (FolderBrowserDialog dialog = new FolderBrowserDialog())
            {
                dialog.Description = "Select the Millennium directory, Steam directory, or Millennium plugins directory.";
                dialog.ShowNewFolderButton = false;
                if (Directory.Exists(millenniumPathTextBox.Text))
                {
                    dialog.SelectedPath = millenniumPathTextBox.Text;
                }

                if (dialog.ShowDialog(this) == DialogResult.OK)
                {
                    millenniumPathTextBox.Text = dialog.SelectedPath;
                }
            }
        }

        private void MillenniumPathTextChanged(object sender, EventArgs eventArgs)
        {
            ResolvedInstallPaths paths;
            string error;
            if (MillenniumPathResolver.TryResolve(millenniumPathTextBox.Text, out paths, out error))
            {
                destinationValueLabel.Text = paths.PluginDirectory;
                destinationValueLabel.ForeColor = SystemColors.ControlText;
                installButton.Enabled = !operationRunning;
                deleteButton.Enabled = !operationRunning;
            }
            else
            {
                destinationValueLabel.Text = error;
                destinationValueLabel.ForeColor = Color.Firebrick;
                installButton.Enabled = false;
                deleteButton.Enabled = false;
            }
        }

        private async void InstallButtonClick(object sender, EventArgs eventArgs)
        {
            ResolvedInstallPaths paths;
            string error;
            if (!MillenniumPathResolver.TryResolve(millenniumPathTextBox.Text, out paths, out error))
            {
                MessageBox.Show(this, error, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            if (!EnsureSteamIsClosed())
            {
                return;
            }

            SetOperationRunning(true);
            operationCancellation = new CancellationTokenSource();
            AppendLog("");
            AppendLog("Starting Install/Repair...");

            Progress<InstallerProgressInfo> operationProgress = new Progress<InstallerProgressInfo>(UpdateProgress);
            try
            {
                InstallOperationResult result;
                using (VortexPluginInstallerService service = new VortexPluginInstallerService(operationProgress))
                {
                    result = await service.InstallOrRepairAsync(paths, operationCancellation.Token);
                }

                AppendLog("Installed Vortex Launch Bridge " + result.PluginVersion
                    + " from commit " + ShortCommit(result.Commit) + ".");
                AppendLog("Installed to " + result.PluginDirectory + ".");

                MessageBox.Show(
                    this,
                    "Vortex Launch Bridge " + result.PluginVersion + " was installed successfully.\r\n\r\n"
                    + "Start Steam, open Millennium Settings > Plugins, and enable the plugin if it is not already enabled.",
                    InstallerConstants.ProductName + " Setup",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
            }
            catch (OperationCanceledException)
            {
                AppendLog("Operation cancelled. The previously installed plugin was left unchanged.");
            }
            catch (Exception ex)
            {
                AppendLog("ERROR: " + ex.Message);
                MessageBox.Show(
                    this,
                    "Install/Repair failed:\r\n\r\n" + ex.Message
                    + "\r\n\r\nThe previously installed plugin was left unchanged whenever rollback was possible.",
                    InstallerConstants.ProductName + " Setup",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            finally
            {
                if (operationCancellation != null)
                {
                    operationCancellation.Dispose();
                    operationCancellation = null;
                }
                SetOperationRunning(false);
            }
        }

        private void DeleteButtonClick(object sender, EventArgs eventArgs)
        {
            ResolvedInstallPaths paths;
            string error;
            if (!MillenniumPathResolver.TryResolve(millenniumPathTextBox.Text, out paths, out error))
            {
                MessageBox.Show(this, error, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            if (!Directory.Exists(paths.PluginDirectory))
            {
                MessageBox.Show(
                    this,
                    "Vortex Launch Bridge is not installed at:\r\n\r\n" + paths.PluginDirectory,
                    InstallerConstants.ProductName + " Setup",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
                return;
            }

            DialogResult confirmation = MessageBox.Show(
                this,
                "Delete the Vortex Launch Bridge plugin folder?\r\n\r\n"
                + paths.PluginDirectory
                + "\r\n\r\nLocal plugin settings under your Windows profile will not be removed.",
                "Delete Vortex Launch Bridge",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning,
                MessageBoxDefaultButton.Button2);

            if (confirmation != DialogResult.Yes || !EnsureSteamIsClosed())
            {
                return;
            }

            try
            {
                using (VortexPluginInstallerService service = new VortexPluginInstallerService(null))
                {
                    service.DeletePlugin(paths);
                }

                AppendLog("Deleted " + paths.PluginDirectory + ".");
                progressBar.Style = ProgressBarStyle.Continuous;
                progressBar.Value = 0;
                MessageBox.Show(
                    this,
                    "Vortex Launch Bridge was deleted from Millennium.",
                    InstallerConstants.ProductName + " Setup",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                AppendLog("ERROR: Delete failed: " + ex.Message);
                MessageBox.Show(
                    this,
                    "Delete failed:\r\n\r\n" + ex.Message,
                    InstallerConstants.ProductName + " Setup",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
        }

        private void CancelButtonClick(object sender, EventArgs eventArgs)
        {
            if (!operationRunning)
            {
                Close();
                return;
            }

            if (operationCancellation != null && !operationCancellation.IsCancellationRequested)
            {
                AppendLog("Cancelling...");
                operationCancellation.Cancel();
                cancelButton.Enabled = false;
            }
        }

        private void InstallerFormClosing(object sender, FormClosingEventArgs eventArgs)
        {
            if (!operationRunning)
            {
                return;
            }

            eventArgs.Cancel = true;
            DialogResult result = MessageBox.Show(
                this,
                "An installation operation is still running. Cancel it?",
                InstallerConstants.ProductName + " Setup",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question,
                MessageBoxDefaultButton.Button2);

            if (result == DialogResult.Yes && operationCancellation != null)
            {
                operationCancellation.Cancel();
                cancelButton.Enabled = false;
            }
        }

        private bool EnsureSteamIsClosed()
        {
            if (!SafeFileSystem.IsSteamRunning())
            {
                return true;
            }

            MessageBox.Show(
                this,
                "Steam is currently running. Fully exit Steam, including its notification-area process, and try again.",
                InstallerConstants.ProductName + " Setup",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return false;
        }

        private void SetOperationRunning(bool running)
        {
            operationRunning = running;
            millenniumPathTextBox.Enabled = !running;
            browseButton.Enabled = !running;
            installButton.Enabled = !running;
            deleteButton.Enabled = !running;
            cancelButton.Enabled = true;
            cancelButton.Text = "Cancel";

            if (!running)
            {
                progressBar.Style = ProgressBarStyle.Continuous;
                MillenniumPathTextChanged(this, EventArgs.Empty);
            }
        }

        private void UpdateProgress(InstallerProgressInfo info)
        {
            if (info == null)
            {
                return;
            }

            if (info.IsIndeterminate && info.Percent == 0)
            {
                progressBar.Style = ProgressBarStyle.Marquee;
            }
            else
            {
                progressBar.Style = info.IsIndeterminate
                    ? ProgressBarStyle.Marquee
                    : ProgressBarStyle.Continuous;
                if (!info.IsIndeterminate)
                {
                    progressBar.Value = info.Percent;
                }
            }

            AppendLog(info.Message);
        }

        private void AppendLog(string message)
        {
            if (logTextBox.TextLength > 0)
            {
                logTextBox.AppendText(Environment.NewLine);
            }
            logTextBox.AppendText(message);
            logTextBox.SelectionStart = logTextBox.TextLength;
            logTextBox.ScrollToCaret();
        }

        private static string ShortCommit(string commit)
        {
            return !String.IsNullOrWhiteSpace(commit) && commit.Length > 12
                ? commit.Substring(0, 12)
                : commit;
        }
    }
}
