using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading.Tasks;

namespace NickSoin.SteamUploader
{
    internal sealed class SteamCmdResult
    {
        public int exitCode;
        public string output;
    }

    internal static class SteamCmdRunner
    {
        public static async Task<SteamCmdResult> RunUploadAsync(
            string steamCmdPath,
            string username,
            string appBuildPath,
            Action<string> onLine)
        {
            if (string.IsNullOrWhiteSpace(steamCmdPath))
                throw new InvalidOperationException("SteamCMD path is not configured.");
            if (!File.Exists(steamCmdPath))
                throw new FileNotFoundException("SteamCMD executable was not found.", steamCmdPath);
            if (string.IsNullOrWhiteSpace(username))
                throw new InvalidOperationException("Steam username is required.");
            if (!File.Exists(appBuildPath))
                throw new FileNotFoundException("Steam app build VDF was not found.", appBuildPath);

            var arguments = $"+login {Quote(username.Trim())} +run_app_build {Quote(appBuildPath)} +quit";
            var output = new StringBuilder();
            var tcs = new TaskCompletionSource<int>();

            var startInfo = new ProcessStartInfo
            {
                FileName = steamCmdPath,
                Arguments = arguments,
                WorkingDirectory = Path.GetDirectoryName(steamCmdPath) ?? Environment.CurrentDirectory,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };

            using (var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true })
            {
                process.OutputDataReceived += (_, args) => HandleLine(args.Data, output, onLine);
                process.ErrorDataReceived += (_, args) => HandleLine(args.Data, output, onLine);
                process.Exited += (_, __) => tcs.TrySetResult(process.ExitCode);

                if (!process.Start())
                    throw new InvalidOperationException("Failed to start SteamCMD.");

                process.BeginOutputReadLine();
                process.BeginErrorReadLine();

                var exitCode = await tcs.Task;
                process.WaitForExit();

                return new SteamCmdResult
                {
                    exitCode = exitCode,
                    output = output.ToString()
                };
            }
        }

        private static void HandleLine(string line, StringBuilder output, Action<string> onLine)
        {
            if (string.IsNullOrEmpty(line))
                return;

            lock (output)
            {
                output.AppendLine(line);
            }

            onLine?.Invoke(line);
        }

        private static string Quote(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }
    }
}
