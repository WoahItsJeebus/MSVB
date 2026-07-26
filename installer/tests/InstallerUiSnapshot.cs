using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Windows.Forms;

namespace VortexLaunchBridge.Installer
{
    internal static class InstallerUiSnapshot
    {
        [STAThread]
        private static int Main(string[] arguments)
        {
            if (arguments.Length != 1)
            {
                Console.Error.WriteLine("Usage: InstallerUiSnapshot.exe <output.png>");
                return 2;
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            using (InstallerForm form = new InstallerForm())
            {
                form.Show();
                Application.DoEvents();

                using (Bitmap bitmap = new Bitmap(form.Width, form.Height))
                {
                    form.DrawToBitmap(bitmap, new Rectangle(0, 0, form.Width, form.Height));
                    bitmap.Save(arguments[0], ImageFormat.Png);
                }

                form.Close();
            }

            return 0;
        }
    }
}
