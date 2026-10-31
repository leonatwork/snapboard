using System;
using System.Collections.Generic;
using System.Drawing;
using System.Media;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace Snapboard
{
    internal static class Program
    {
        private static Mutex? singleInstanceMutex;
        private static int reportingException;

        [STAThread]
        static void Main()
        {
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
            Application.ThreadException += (s, e) => ReportUnexpectedException(e.Exception, false);
            AppDomain.CurrentDomain.UnhandledException += (s, e) =>
                ReportUnexpectedException(e.ExceptionObject as Exception, e.IsTerminating);

            // Single instance lock
            singleInstanceMutex = new Mutex(true, "Snapboard_SingleInstance_Mutex", out bool createdNew);
            if (!createdNew)
            {
                MessageBox.Show(L10n.Get("windows.alreadyRunning"), L10n.Get("common.appName"), MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            ApplicationConfiguration.Initialize();
            Application.Run(new SnapboardAppContext());
        }

        private static void ReportUnexpectedException(Exception? exception, bool terminating)
        {
            if (Interlocked.Exchange(ref reportingException, 1) != 0) return;
            try
            {
                string consequence = terminating
                    ? L10n.Get("windows.error.restart")
                    : L10n.Get("windows.error.continue");
                MessageBox.Show(L10n.Format("windows.error.unexpected", consequence, exception?.Message ?? string.Empty),
                    L10n.Get("common.appName"), MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally { Interlocked.Exchange(ref reportingException, 0); }
        }
    }

    public class SnapboardAppContext : ApplicationContext
    {
        private NotifyIcon trayIcon;
        private MessageWindow messageWindow;
        private const int HOTKEY_DIRECT_ID = 1;
        private const int HOTKEY_EDIT_ID = 2;
        private readonly CaptureGate captureGate = new CaptureGate();

        public SnapboardAppContext()
        {
            messageWindow = new MessageWindow(this);

            // Tray Menu
            ContextMenuStrip contextMenu = new ContextMenuStrip();
            contextMenu.Items.Add(L10n.Get("windows.menu.captureDirect"), null, (s, e) => CaptureDirect());
            contextMenu.Items.Add(L10n.Get("windows.menu.captureEdit"), null, (s, e) => CaptureForEdit());
            contextMenu.Items.Add(new ToolStripSeparator());

            var autostartItem = new ToolStripMenuItem(L10n.Get("windows.menu.autostart"));
            RefreshAutostartItem(autostartItem);
            autostartItem.Click += (s, e) =>
            {
                bool newState = !autostartItem.Checked;
                SetAutostart(newState);
                RefreshAutostartItem(autostartItem);
            };
            contextMenu.Opening += (s, e) => RefreshAutostartItem(autostartItem);
            contextMenu.Items.Add(autostartItem);

            contextMenu.Items.Add(new ToolStripSeparator());
            contextMenu.Items.Add(L10n.Get("menu.about"), null, (s, e) =>
            {
                MessageBox.Show(L10n.AboutMessage, L10n.Get("menu.about"), MessageBoxButtons.OK, MessageBoxIcon.Information);
            });
            contextMenu.Items.Add(L10n.Get("menu.quit"), null, (s, e) => Exit());

            // Tray Icon
            trayIcon = new NotifyIcon
            {
                Icon = SystemIcons.Application,
                ContextMenuStrip = contextMenu,
                Text = L10n.Get("windows.statusItem.tooltip"),
                Visible = true
            };

            // Register only after the tray is ready: startup dialogs also pump WM_HOTKEY.
            uint modifiers = HotKeyHelper.MOD_CONTROL | HotKeyHelper.MOD_SHIFT | HotKeyHelper.MOD_NOREPEAT;
            var unavailableHotkeys = new List<string>();
            if (!HotKeyHelper.RegisterHotKey(messageWindow.Handle, HOTKEY_DIRECT_ID, modifiers, 0x31))
                unavailableHotkeys.Add(L10n.Get("windows.shortcut.direct"));
            if (!HotKeyHelper.RegisterHotKey(messageWindow.Handle, HOTKEY_EDIT_ID, modifiers, 0x32))
                unavailableHotkeys.Add(L10n.Get("windows.shortcut.edit"));
            if (unavailableHotkeys.Count > 0)
            {
                MessageBox.Show(L10n.Format("windows.error.hotkeys", string.Join(L10n.Get("common.listSeparator"), unavailableHotkeys)),
                    L10n.Get("common.appName"), MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        public void CaptureDirect()
        {
            captureGate.TryRun(() => Capture(false));
        }

        public void CaptureForEdit()
        {
            captureGate.TryRun(() => Capture(true));
        }

        private void Capture(bool edit)
        {
            using (var snipper = new SnippingOverlay())
            {
                if (snipper.ShowDialog() == DialogResult.OK && snipper.SelectedImage != null)
                {
                    using (var selectedImage = snipper.SelectedImage)
                    {
                        if (edit)
                        {
                            var editor = new EditorForm(selectedImage);
                            editor.Show();
                        }
                        else if (ClipboardRetry.TrySetImage(selectedImage))
                        {
                            SystemSounds.Asterisk.Play();
                        }
                        else
                        {
                            trayIcon.ShowBalloonTip(5000, L10n.Get("common.appName"),
                                L10n.Get("windows.error.clipboardDirect"),
                                ToolTipIcon.Warning);
                        }
                    }
                }
            }
        }

        private void RefreshAutostartItem(ToolStripMenuItem item)
        {
            bool? enabled = IsAutostartEnabled();
            item.CheckState = enabled.HasValue
                ? (enabled.Value ? CheckState.Checked : CheckState.Unchecked)
                : CheckState.Indeterminate;
            item.Enabled = enabled.HasValue;
        }

        private bool? IsAutostartEnabled()
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", false))
                {
                    return key?.GetValue("Snapboard") != null;
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(L10n.Format("windows.error.autostartRead", ex.Message),
                    L10n.Get("common.appName"), MessageBoxButtons.OK, MessageBoxIcon.Warning);
                // A failed read is unknown, not proof that autostart is disabled.
                return null;
            }
        }

        private void SetAutostart(bool enable)
        {
            try
            {
                using (var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true))
                {
                    if (key == null) throw new InvalidOperationException(L10n.Get("windows.error.autostartKey"));
                    if (enable)
                    {
                        key.SetValue("Snapboard", $"\"{Application.ExecutablePath}\"");
                    }
                    else
                    {
                        key.DeleteValue("Snapboard", false);
                    }
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(L10n.Format("windows.error.autostartWrite", ex.Message),
                    L10n.Get("common.appName"), MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        public void HandleHotKey(int id)
        {
            if (id == HOTKEY_DIRECT_ID)
            {
                CaptureDirect();
            }
            else if (id == HOTKEY_EDIT_ID)
            {
                CaptureForEdit();
            }
        }

        private void Exit()
        {
            HotKeyHelper.UnregisterHotKey(messageWindow.Handle, HOTKEY_DIRECT_ID);
            HotKeyHelper.UnregisterHotKey(messageWindow.Handle, HOTKEY_EDIT_ID);
            trayIcon.Visible = false;
            trayIcon.Dispose();
            messageWindow.DestroyHandle();
            Application.Exit();
        }

        private class MessageWindow : NativeWindow
        {
            private SnapboardAppContext context;

            public MessageWindow(SnapboardAppContext context)
            {
                this.context = context;
                CreateHandle(new CreateParams());
            }

            protected override void WndProc(ref Message m)
            {
                if (m.Msg == HotKeyHelper.WM_HOTKEY)
                {
                    int id = m.WParam.ToInt32();
                    context.HandleHotKey(id);
                }
                base.WndProc(ref m);
            }
        }
    }
}
