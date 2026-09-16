using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build.Reporting;

namespace NickSoin.SteamUploader
{
    internal static class SteamBuildService
    {
        public static string GetBuildRoot(SteamUploadTarget target)
        {
            return SteamUploaderPaths.ToAbsoluteProjectPath(target.buildDirectory);
        }

        public static string GetPlayerPath(SteamUploadTarget target)
        {
            var root = GetBuildRoot(target);
            var name = string.IsNullOrWhiteSpace(target.executableName) ? "Game" : target.executableName.Trim();

            switch (target.buildTarget)
            {
                case BuildTarget.StandaloneWindows64:
                    return Path.Combine(root, name + ".exe");
                case BuildTarget.StandaloneOSX:
                    return Path.Combine(root, name + ".app");
                case BuildTarget.StandaloneLinux64:
                    return Path.Combine(root, name);
                default:
                    throw new NotSupportedException($"Steam Build Uploader currently supports Windows, macOS, and Linux standalone targets. Selected: {target.buildTarget}");
            }
        }

        public static BuildReport Build(SteamUploadTarget target, Action<string> log)
        {
            if (target == null)
                throw new ArgumentNullException(nameof(target));

            var buildRoot = GetBuildRoot(target);
            if (target.cleanBuildDirectory && Directory.Exists(buildRoot))
            {
                log?.Invoke($"Cleaning build directory: {buildRoot}");
                Directory.Delete(buildRoot, true);
            }

            Directory.CreateDirectory(buildRoot);

            var scenes = EditorBuildSettings.scenes
                .Where(scene => scene.enabled)
                .Select(scene => scene.path)
                .ToArray();

            if (scenes.Length == 0)
                throw new InvalidOperationException("No enabled scenes found in Build Settings.");

            var options = BuildOptions.None;
            if (target.developmentBuild)
                options |= BuildOptions.Development;

            var playerPath = GetPlayerPath(target);
            log?.Invoke($"Building {target.buildTarget} to {playerPath}");

            var buildOptions = new BuildPlayerOptions
            {
                scenes = scenes,
                locationPathName = playerPath,
                target = target.buildTarget,
                options = options
            };

            var report = BuildPipeline.BuildPlayer(buildOptions);
            if (report.summary.result != BuildResult.Succeeded)
                throw new InvalidOperationException($"Unity build failed: {report.summary.result}. Errors: {report.summary.totalErrors}");

            log?.Invoke($"Unity build complete. Size: {FormatBytes(report.summary.totalSize)}");
            return report;
        }

        private static string FormatBytes(ulong bytes)
        {
            string[] suffixes = { "B", "KB", "MB", "GB", "TB" };
            double value = bytes;
            var index = 0;
            while (value >= 1024 && index < suffixes.Length - 1)
            {
                value /= 1024;
                index++;
            }

            return $"{value:0.##} {suffixes[index]}";
        }
    }
}
