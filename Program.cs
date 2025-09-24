using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;

namespace PIMGlobalLauncher
{
    class Program
    {
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("kernel32.dll")]
        public static extern IntPtr GetConsoleWindow();

        static void Main(string[] args)
        {
            try
            {
                // Create temp directory for runtime files
                string tempDir = Path.Combine(Path.GetTempPath(), "PIM-Global-" + Guid.NewGuid().ToString("N")[..8]);
                Directory.CreateDirectory(tempDir);

                // Extract embedded resources silently
                ExtractResource("PIMGlobalMSTLauncher.PIM-Global-SelfActivate.ps1", Path.Combine(tempDir, "PIM-Global-SelfActivate.ps1"));
                
                string msalDir = Path.Combine(tempDir, "MSAL", "netstandard2.0");
                Directory.CreateDirectory(msalDir);
                ExtractResource("PIMGlobalMSTLauncher.MSAL.netstandard2._0.Microsoft.Identity.Client.dll", 
                               Path.Combine(msalDir, "Microsoft.Identity.Client.dll"));
                ExtractResource("PIMGlobalMSTLauncher.MSAL.netstandard2._0.Microsoft.IdentityModel.Abstractions.dll", 
                               Path.Combine(msalDir, "Microsoft.IdentityModel.Abstractions.dll"));

                // Find PowerShell 7+ (pwsh.exe)
                string pwshPath = FindPowerShell7();
                if (string.IsNullOrEmpty(pwshPath))
                {
                    Console.WriteLine("ERROR: PowerShell 7+ (pwsh.exe) not found in PATH.");
                    Console.WriteLine("Please install PowerShell 7+ from: https://github.com/PowerShell/PowerShell/releases");
                    Console.WriteLine("Press any key to exit...");
                    Console.ReadKey();
                    return;
                }

                // Set up process start info
                var startInfo = new ProcessStartInfo
                {
                    FileName = pwshPath,
                    Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{Path.Combine(tempDir, "PIM-Global-SelfActivate.ps1")}\"",
                    WorkingDirectory = tempDir,
                    UseShellExecute = false,
                    CreateNoWindow = false,
                    RedirectStandardOutput = false,
                    RedirectStandardError = false
                };

                // Launch PowerShell
                using var process = Process.Start(startInfo);
                if (process != null)
                {
                    // Wait a moment for the window to appear, then bring to foreground
                    Thread.Sleep(1000);
                    BringConsoleToForeground();
                    
                    // Wait for PowerShell to complete
                    process.WaitForExit();
                }

                // Clean up temp directory
                try
                {
                    Directory.Delete(tempDir, true);
                }
                catch
                {
                    // Ignore cleanup errors
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"ERROR: {ex.Message}");
                Console.WriteLine("Press any key to exit...");
                Console.ReadKey();
            }
        }

        static void ExtractResource(string resourceName, string outputPath)
        {
            using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName);
            if (stream == null)
            {
                throw new Exception($"Resource '{resourceName}' not found in assembly.");
            }

            using var fileStream = File.Create(outputPath);
            stream.CopyTo(fileStream);
        }

        static string FindPowerShell7()
        {
            // Check common installation paths
            string[] possiblePaths = {
                @"C:\Program Files\PowerShell\7\pwsh.exe",
                @"C:\Program Files (x86)\PowerShell\7\pwsh.exe",
                @"C:\Users\{0}\AppData\Local\Microsoft\WinGet\Packages\Microsoft.Powershell_8wekyb3d8bbwe\LocalState\Microsoft.PowerShell\pwsh.exe"
            };

            foreach (string path in possiblePaths)
            {
                if (File.Exists(path))
                    return path;
            }

            // Check PATH
            try
            {
                using var process = Process.Start(new ProcessStartInfo
                {
                    FileName = "where",
                    Arguments = "pwsh",
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    CreateNoWindow = true
                });

                if (process != null)
                {
                    string output = process.StandardOutput.ReadToEnd();
                    process.WaitForExit();
                    
                    if (process.ExitCode == 0 && !string.IsNullOrWhiteSpace(output))
                    {
                        string[] lines = output.Split('\n');
                        foreach (string line in lines)
                        {
                            string trimmed = line.Trim();
                            if (trimmed.EndsWith("pwsh.exe") && File.Exists(trimmed))
                                return trimmed;
                        }
                    }
                }
            }
            catch
            {
                // Ignore errors
            }

            return null;
        }

        static void BringConsoleToForeground()
        {
            try
            {
                IntPtr hwnd = GetConsoleWindow();
                if (hwnd != IntPtr.Zero)
                {
                    ShowWindow(hwnd, 5); // SW_SHOW
                    SetForegroundWindow(hwnd);
                }
            }
            catch
            {
                // Ignore errors
            }
        }
    }
}
