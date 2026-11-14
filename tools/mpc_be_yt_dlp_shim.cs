using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;

namespace MpcBeYtDlpShim {
    public static class Program {
        private static string Quote(string argument) {
            if (argument.Length > 0 && argument.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0) {
                return argument;
            }
            var result = new StringBuilder("\"");
            int backslashes = 0;
            foreach (char c in argument) {
                if (c == '\\') {
                    backslashes++;
                } else if (c == '"') {
                    result.Append('\\', backslashes * 2 + 1);
                    result.Append('"');
                    backslashes = 0;
                } else {
                    result.Append('\\', backslashes);
                    result.Append(c);
                    backslashes = 0;
                }
            }
            result.Append('\\', backslashes * 2);
            result.Append('"');
            return result.ToString();
        }

        private static int Run(string executable, string arguments) {
            var info = new ProcessStartInfo(executable, arguments);
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            using (var process = Process.Start(info)) {
                if (process == null) {
                    throw new InvalidOperationException("Failed to start: " + executable);
                }
                process.WaitForExit();
                return process.ExitCode;
            }
        }

        public static int Main(string[] args) {
            try {
                string exePath = Assembly.GetExecutingAssembly().Location;
                string shimPath = Path.ChangeExtension(exePath, ".shim");
                if (!File.Exists(shimPath)) {
                    Console.Error.WriteLine("Shim configuration file not found: " + shimPath);
                    return 1;
                }
                string[] lines = File.ReadAllLines(shimPath);
                if (lines.Length != 2 || lines[1].Trim() != "--ignore-config") {
                    Console.Error.WriteLine("Invalid Shim configuration: " + shimPath);
                    return 1;
                }
                string target = lines[0].Trim();
                if (!File.Exists(target)) {
                    Console.Error.WriteLine("Target executable not found: " + target);
                    return 1;
                }

                string scriptsDir = Path.GetDirectoryName(target);
                string python = Path.Combine(scriptsDir, "python.exe");
                string updater = Path.GetFullPath(Path.Combine(scriptsDir, "..", "..", "auto_update.py"));
                if (Environment.GetEnvironmentVariable("YT_DLP_SKIP_UPDATE") != "1"
                        && File.Exists(python) && File.Exists(updater)) {
                    try {
                        Run(python, Quote(updater));
                    } catch (Exception error) {
                        Console.Error.WriteLine("yt-dlp update skipped: " + error.Message);
                    }
                }

                string forwarded = "--ignore-config";
                if (args.Length > 0) {
                    forwarded += " " + string.Join(" ", args.Select(Quote).ToArray());
                }
                return Run(target, forwarded);
            } catch (Exception error) {
                Console.Error.WriteLine("MPC-BE yt-dlp shim error: " + error.Message);
                return 1;
            }
        }
    }
}
