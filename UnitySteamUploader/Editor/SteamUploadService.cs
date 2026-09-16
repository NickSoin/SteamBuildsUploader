using System;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using UnityEditor;

namespace NickSoin.SteamUploader
{
    internal sealed class SteamUploadResult
    {
        public int exitCode;
        public string buildId;
        public string output;
    }

    internal static class SteamUploadService
    {
        private static readonly Regex BuildIdRegex = new Regex(@"BuildID\s*[:#]?\s*(\d+)", RegexOptions.IgnoreCase | RegexOptions.Compiled);

        public static async Task<SteamUploadResult> BuildAndUploadAsync(
            SteamUploaderSettings settings,
            SteamUploadTarget target,
            string description,
            bool buildFirst,
            Action<string> log)
        {
            settings.EnsureDefaults();
            ValidateSettings(settings, target);

            if (buildFirst)
                SteamBuildService.Build(target, log);

            var files = SteamVdfWriter.Write(settings, target, description);
            log?.Invoke($"Generated SteamPipe scripts: {files.appBuildPath}");
            log?.Invoke("Starting SteamCMD. Cached SteamCMD authentication is used; no password is stored by this package.");

            var result = await SteamCmdRunner.RunUploadAsync(
                SteamUploaderPaths.ToAbsoluteProjectPath(settings.steamCmdPath),
                settings.steamUsername,
                files.appBuildPath,
                line => EditorApplication.delayCall += () => log?.Invoke(line));

            var buildId = ExtractBuildId(result.output);
            if (result.exitCode != 0)
                throw new InvalidOperationException($"SteamCMD exited with code {result.exitCode}. Check the log above for the SteamPipe error.");

            log?.Invoke(string.IsNullOrEmpty(buildId)
                ? "SteamCMD completed successfully. Build ID was not detected in the output."
                : $"Upload complete. Steam Build ID: {buildId}");

            return new SteamUploadResult
            {
                exitCode = result.exitCode,
                buildId = buildId,
                output = result.output
            };
        }

        private static void ValidateSettings(SteamUploaderSettings settings, SteamUploadTarget target)
        {
            if (target == null)
                throw new InvalidOperationException("Create at least one upload target.");
            if (string.IsNullOrWhiteSpace(settings.steamCmdPath))
                throw new InvalidOperationException("Configure the SteamCMD path first.");
            if (string.IsNullOrWhiteSpace(settings.steamUsername))
                throw new InvalidOperationException("Configure the Steam builder username first.");
        }

        private static string ExtractBuildId(string output)
        {
            if (string.IsNullOrWhiteSpace(output))
                return string.Empty;

            var matches = BuildIdRegex.Matches(output);
            return matches.Count == 0 ? string.Empty : matches[matches.Count - 1].Groups[1].Value;
        }
    }
}
