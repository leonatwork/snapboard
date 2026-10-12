using System;
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

        [STAThread]
        static void Main()
        {
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
    }

    public class SnapboardAppContext : ApplicationContext
    {
        private NotifyIcon trayIcon;
        private MessageWindow messageWindow;
        private const int HOTKEY_DIRECT_ID = 1;
        private const int HOTKEY_EDIT_ID = 2;

        public SnapboardAppContext()
        {
            messageWindow = new MessageWindow(this);

            // Register Ctrl + Shift + 1 (0x31) and Ctrl + Shift + 2 (0x32)
            uint modifiers = HotKeyHelper.MOD_CONTROL | HotKeyHelper.MOD_SHIFT | HotKeyHelper.MOD_NOREPEAT;
            HotKeyHelper.RegisterHotKey(messageWindow.Handle, HOTKEY_DIRECT_ID, modifiers, 0x31);
            HotKeyHelper.RegisterHotKey(messageWindow.Handle, HOTKEY_EDIT_ID, modifiers, 0x32);

            // Tray Menu
            ContextMenuStrip contextMenu = new ContextMenuStrip();
            contextMenu.Items.Add("📷 Bereich aufnehmen (Strg+Umschalt+1)", null, (s, e) => CaptureDirect());
            contextMenu.Items.Add("✏️ Bereich aufnehmen & bearbeiten (Strg+Umschalt+2)", null, (s, e) => CaptureForEdit());
            contextMenu.Items.Add(new ToolStripSeparator());

            var autostartItem = new ToolStripMenuItem("Beim Windows-Start ausführen");
            autostartItem.Checked = IsAutostartEnabled();
            autostartItem.Click += (s, e) =>
            {
                bool newState = !autostartItem.Checked;
                SetAutostart(newState);
                autostartItem.Checked = newState;
            };
            contextMenu.Items.Add(autostartItem);

            contextMenu.Items.Add(new ToolStripSeparator());
            contextMenu.Items.Add("ℹ️ Über Snapboard", null, (s, e) =>
            {
                MessageBox.Show("Snapboard v1.1 für Windows & macOS\n\n• Strg+Umschalt+1: Direkt in Zwischenablage (0 Klicks)\n• Strg+Umschalt+2: Bereich markieren & Editor öffnen\n\nKeine Dateien auf der Festplatte gespeichert.", "Über Snapboard", MessageBoxButtons.OK, MessageBoxIcon.Information);
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
        }

        public void CaptureDirect()
        {
            using (var snipper = new SnippingOverlay())
            {
                if (snipper.ShowDialog() == DialogResult.OK && snipper.SelectedImage != null)
                {
                    Clipboard.SetImage(snipper.SelectedImage);
                    SystemSounds.Asterisk.Play();
                }
            }
        }

        public void CaptureForEdit()
        {
            using (var snipper = new SnippingOverlay())
            {
                if (snipper.ShowDialog() == DialogResult.OK && snipper.SelectedImage != null)
                {
                    var editor = new EditorForm(snipper.SelectedImage);
                    editor.Show();
                }
            }
        }

        private bool IsAutostartEnabled()
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", false))
                {
                    return key?.GetValue("Snapboard") != null;
                }
            }
            catch { return false; }
        }

        private void SetAutostart(bool enable)
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true))
                {
                    if (enable)
                    {
                        key?.SetValue("Snapboard", $"\"{Application.ExecutablePath}\"");
                    }
                    else
                    {
                        key?.DeleteValue("Snapboard", false);
                    }
                }
            }
            catch { }
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
