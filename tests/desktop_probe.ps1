$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class VortexLaunchBridgeDesktopProbe
{
    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr GetThreadDesktop(uint threadId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool GetUserObjectInformation(
        IntPtr handle,
        int index,
        StringBuilder information,
        int length,
        out int needed
    );

    public static string CurrentName()
    {
        var desktop = GetThreadDesktop(GetCurrentThreadId());
        int needed;
        GetUserObjectInformation(desktop, 2, null, 0, out needed);
        if (needed <= 0)
        {
            return string.Empty;
        }
        var value = new StringBuilder(needed / 2);
        return GetUserObjectInformation(
            desktop,
            2,
            value,
            needed,
            out needed
        ) ? value.ToString() : string.Empty;
    }
}
'@

[Console]::Write([VortexLaunchBridgeDesktopProbe]::CurrentName())
