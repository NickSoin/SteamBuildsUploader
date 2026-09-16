using System;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

namespace NickSoin.SteamUploader
{
    [Serializable]
    internal sealed class SteamUploadTarget
    {
        public string name = "Playtest";
        public string appId = "";
        public string depotId = "";
        public string branch = "";
        public BuildTarget buildTarget = BuildTarget.StandaloneWindows64;
        public string buildDirectory = "Builds/Steam/Windows";
        public string executableName = "Game";
        public bool developmentBuild;
        public bool cleanBuildDirectory = true;
    }

    [FilePath("ProjectSettings/SteamUploaderSettings.asset", FilePathAttribute.Location.ProjectFolder)]
    internal sealed class SteamUploaderSettings : ScriptableSingleton<SteamUploaderSettings>
    {
        public string steamCmdPath = "";
        public string steamUsername = "";
        public string steamPipeWorkingDirectory = "Library/SteamUploader";
        public List<SteamUploadTarget> targets = new List<SteamUploadTarget>();
        public int selectedTargetIndex;

        public void SaveSettings()
        {
            Save(true);
        }

        public SteamUploadTarget GetSelectedTarget()
        {
            if (targets == null || targets.Count == 0)
                return null;

            selectedTargetIndex = Mathf.Clamp(selectedTargetIndex, 0, targets.Count - 1);
            return targets[selectedTargetIndex];
        }

        public string GetAbsoluteWorkingDirectory()
        {
            return SteamUploaderPaths.ToAbsoluteProjectPath(steamPipeWorkingDirectory);
        }

        public void EnsureDefaults()
        {
            if (targets == null)
                targets = new List<SteamUploadTarget>();

            if (targets.Count == 0)
                targets.Add(new SteamUploadTarget());

            if (string.IsNullOrWhiteSpace(steamPipeWorkingDirectory))
                steamPipeWorkingDirectory = "Library/SteamUploader";
        }
    }

    internal static class SteamUploaderPaths
    {
        public static string ProjectRoot => Directory.GetParent(Application.dataPath)?.FullName ?? Application.dataPath;

        public static string ToAbsoluteProjectPath(string path)
        {
            if (string.IsNullOrWhiteSpace(path))
                return ProjectRoot;

            if (Path.IsPathRooted(path))
                return Path.GetFullPath(path);

            return Path.GetFullPath(Path.Combine(ProjectRoot, path));
        }

        public static string EscapeVdf(string value)
        {
            if (value == null)
                return string.Empty;

            return value.Replace("\\", "/").Replace("\"", "\\\"");
        }
    }
}
