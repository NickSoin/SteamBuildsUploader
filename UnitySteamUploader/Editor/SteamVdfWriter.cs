using System;
using System.IO;

namespace NickSoin.SteamUploader
{
    internal sealed class SteamVdfFiles
    {
        public string appBuildPath;
        public string depotBuildPath;
    }

    internal static class SteamVdfWriter
    {
        public static SteamVdfFiles Write(SteamUploaderSettings settings, SteamUploadTarget target, string description)
        {
            ValidateTarget(target);

            var workRoot = settings.GetAbsoluteWorkingDirectory();
            var scriptsRoot = Path.Combine(workRoot, "scripts");
            var outputRoot = Path.Combine(workRoot, "output");
            Directory.CreateDirectory(scriptsRoot);
            Directory.CreateDirectory(outputRoot);

            var contentRoot = SteamBuildService.GetBuildRoot(target);
            if (!Directory.Exists(contentRoot))
                throw new DirectoryNotFoundException($"Build directory does not exist: {contentRoot}");

            var depotFileName = $"depot_build_{target.depotId}.vdf";
            var depotPath = Path.Combine(scriptsRoot, depotFileName);
            var appPath = Path.Combine(scriptsRoot, $"app_build_{target.appId}.vdf");

            var depot =
$"\"DepotBuildConfig\"\n{{\n" +
$"    \"DepotID\" \"{SteamUploaderPaths.EscapeVdf(target.depotId)}\"\n" +
$"    \"ContentRoot\" \"{SteamUploaderPaths.EscapeVdf(contentRoot)}\"\n" +
$"    \"FileMapping\"\n" +
$"    {{\n" +
$"        \"LocalPath\" \"*\"\n" +
$"        \"DepotPath\" \".\"\n" +
$"        \"recursive\" \"1\"\n" +
$"    }}\n" +
$"}}\n";

            var setLive = string.IsNullOrWhiteSpace(target.branch)
                ? string.Empty
                : $"    \"SetLive\" \"{SteamUploaderPaths.EscapeVdf(target.branch.Trim())}\"\n";

            var safeDescription = string.IsNullOrWhiteSpace(description)
                ? $"Unity upload {DateTime.Now:yyyy-MM-dd HH:mm:ss}"
                : description.Trim();

            var app =
$"\"AppBuild\"\n{{\n" +
$"    \"AppID\" \"{SteamUploaderPaths.EscapeVdf(target.appId)}\"\n" +
$"    \"Desc\" \"{SteamUploaderPaths.EscapeVdf(safeDescription)}\"\n" +
$"    \"BuildOutput\" \"{SteamUploaderPaths.EscapeVdf(outputRoot)}\"\n" +
$"    \"ContentRoot\" \"{SteamUploaderPaths.EscapeVdf(contentRoot)}\"\n" +
setLive +
$"    \"Depots\"\n" +
$"    {{\n" +
$"        \"{SteamUploaderPaths.EscapeVdf(target.depotId)}\" \"{SteamUploaderPaths.EscapeVdf(depotPath)}\"\n" +
$"    }}\n" +
$"}}\n";

            File.WriteAllText(depotPath, depot);
            File.WriteAllText(appPath, app);

            return new SteamVdfFiles
            {
                appBuildPath = appPath,
                depotBuildPath = depotPath
            };
        }

        private static void ValidateTarget(SteamUploadTarget target)
        {
            if (target == null)
                throw new ArgumentNullException(nameof(target));
            if (string.IsNullOrWhiteSpace(target.appId))
                throw new InvalidOperationException("App ID is required.");
            if (string.IsNullOrWhiteSpace(target.depotId))
                throw new InvalidOperationException("Depot ID is required.");
            if (string.Equals(target.branch?.Trim(), "default", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Steam does not allow SetLive for the default branch. Leave Branch empty and set the build live from Steamworks App Admin.");
        }
    }
}
