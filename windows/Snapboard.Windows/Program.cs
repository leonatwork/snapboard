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
                MessageBox.Show("Snapboard läuft bereits im Infobereich (System Tray).", "Snapboard", MessageBoxButtons.OK, MessageBoxIcon.Information);
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
                    ? "Snapboard muss beendet werden. Bitte starten Sie die Anwendung erneut."
                    : "Sie können Snapboard weiter verwenden.";
                MessageBox.Show($"Ein unerwarteter Fehler ist aufgetreten.\n{consequence}\n\n{exception?.Message}",
                    "Snapboard", MessageBoxButtons.OK, MessageBoxIcon.Error);
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
        private const int HOTKEY_TEXT_ID = 3;
        private readonly CaptureGate captureGate = new CaptureGate();

        public SnapboardAppContext()
        {
            messageWindow = new MessageWindow(this);

            // Tray Menu
            ContextMenuStrip contextMenu = new ContextMenuStrip();
            contextMenu.Items.Add("📷 Bereich aufnehmen (Strg+Umschalt+1)", null, (s, e) => CaptureDirect());
            contextMenu.Items.Add("✏️ Bereich aufnehmen & bearbeiten (Strg+Umschalt+2)", null, (s, e) => CaptureForEdit());
            contextMenu.Items.Add("Text erkennen (Strg+Umschalt+3)", null, (s, e) => CaptureForText());
            contextMenu.Items.Add(new ToolStripSeparator());

            var autostartItem = new ToolStripMenuItem("Beim Windows-Start ausführen");
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
            contextMenu.Items.Add("ℹ️ Über Snapboard", null, (s, e) =>
            {
                MessageBox.Show("Snapboard v1.1 für Windows & macOS\n\n• Strg+Umschalt+1: Direkt in Zwischenablage (0 Klicks)\n• Strg+Umschalt+2: Bereich markieren & Editor öffnen\n• Strg+Umschalt+3: Text lokal erkennen und kopieren\n\nKeine Dateien auf der Festplatte gespeichert.", "Über Snapboard", MessageBoxButtons.OK, MessageBoxIcon.Information);
            });
            contextMenu.Items.Add("Beenden", null, (s, e) => Exit());

            // Tray Icon
            trayIcon = new NotifyIcon
            {
                Icon = SystemIcons.Application,
                ContextMenuStrip = contextMenu,
                Text = "Snapboard (Strg+Umschalt+1: Direkt / Strg+Umschalt+2: Editor)",
                Visible = true
            };

            // Register only after the tray is ready: startup dialogs also pump WM_HOTKEY.
            uint modifiers = HotKeyHelper.MOD_CONTROL | HotKeyHelper.MOD_SHIFT | HotKeyHelper.MOD_NOREPEAT;
            var unavailableHotkeys = new List<string>();
            if (!HotKeyHelper.RegisterHotKey(messageWindow.Handle, HOTKEY_DIRECT_ID, modifiers, 0x31))
                unavailableHotkeys.Add("Strg+Umschalt+1");
            if (!HotKeyHelper.RegisterHotKey(messageWindow.Handle, HOTKEY_EDIT_ID, modifiers, 0x32))
                unavailableHotkeys.Add("Strg+Umschalt+2");
            if (!HotKeyHelper.RegisterHotKey(messageWindow.Handle, HOTKEY_TEXT_ID, modifiers, 0x33))
                unavailableHotkeys.Add("Strg+Umschalt+3");
            if (unavailableHotkeys.Count > 0)
            {
                MessageBox.Show($"Diese Tastenkürzel konnten nicht registriert werden: {string.Join(", ", unavailableHotkeys)}.\n" +
                    "Möglicherweise werden sie bereits von einer anderen Anwendung verwendet. Die Aufnahme ist weiterhin über das Tray-Menü verfügbar.",
                    "Snapboard", MessageBoxButtons.OK, MessageBoxIcon.Warning);
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

        public async void CaptureForText()
        {
            await captureGate.TryRunAsync(async () =>
            {
                using var snipper = new SnippingOverlay();
                if (snipper.ShowDialog() != DialogResult.OK || snipper.SelectedImage == null) return;
                using var image = snipper.SelectedImage;
                await OcrService.CopyTextAsync(image, Array.Empty<RectangleF>());
            });
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
                            trayIcon.ShowBalloonTip(5000, "Snapboard",
                                "Die Zwischenablage ist belegt. Das Bild konnte nach 3 Versuchen nicht kopiert werden. Bitte versuchen Sie es erneut.",
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
                MessageBox.Show($"Der Autostart-Status konnte nicht gelesen werden.\n\n{ex.Message}",
                    "Snapboard", MessageBoxButtons.OK, MessageBoxIcon.Warning);
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
                    if (key == null) throw new InvalidOperationException("Der Autostart-Schlüssel konnte nicht geöffnet werden.");
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
                MessageBox.Show($"Der Autostart konnte nicht geändert werden.\n\n{ex.Message}",
                    "Snapboard", MessageBoxButtons.OK, MessageBoxIcon.Warning);
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
            else if (id == HOTKEY_TEXT_ID)
            {
                CaptureForText();
            }
        }

        private void Exit()
        {
            HotKeyHelper.UnregisterHotKey(messageWindow.Handle, HOTKEY_DIRECT_ID);
            HotKeyHelper.UnregisterHotKey(messageWindow.Handle, HOTKEY_EDIT_ID);
            HotKeyHelper.UnregisterHotKey(messageWindow.Handle, HOTKEY_TEXT_ID);
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
