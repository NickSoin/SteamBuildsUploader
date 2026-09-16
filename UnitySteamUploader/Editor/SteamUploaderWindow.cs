using System;
using System.IO;
using System.Text;
using UnityEditor;
using UnityEngine;

namespace NickSoin.SteamUploader
{
    internal sealed class SteamUploaderWindow : EditorWindow
    {
        private SteamUploaderSettings _settings;
        private Vector2 _scroll;
        private Vector2 _logScroll;
        private readonly StringBuilder _log = new StringBuilder();
        private string _description = "";
        private bool _busy;
        private string _lastBuildId = "";

        [MenuItem("Tools/Steam/Build Uploader")]
        private static void Open()
        {
            var window = GetWindow<SteamUploaderWindow>("Steam Uploader");
            window.minSize = new Vector2(520, 520);
            window.Show();
        }

        private void OnEnable()
        {
            _settings = SteamUploaderSettings.instance;
            _settings.EnsureDefaults();
        }

        private void OnGUI()
        {
            if (_settings == null)
            {
                _settings = SteamUploaderSettings.instance;
                _settings.EnsureDefaults();
            }

            _scroll = EditorGUILayout.BeginScrollView(_scroll);
            DrawHeader();
            EditorGUILayout.Space(8);
            DrawGlobalSettings();
            EditorGUILayout.Space(12);
            DrawTargets();
            EditorGUILayout.Space(12);
            DrawActions();
            EditorGUILayout.Space(12);
            DrawLog();
            EditorGUILayout.EndScrollView();
        }

        private void DrawHeader()
        {
            EditorGUILayout.LabelField("Steam Build Uploader", EditorStyles.boldLabel);
            EditorGUILayout.LabelField("Build a Unity player and upload it to SteamPipe with SteamCMD.", EditorStyles.wordWrappedMiniLabel);
        }

        private void DrawGlobalSettings()
        {
            EditorGUILayout.LabelField("SteamCMD", EditorStyles.boldLabel);
            using (new EditorGUILayout.HorizontalScope())
            {
                _settings.steamCmdPath = EditorGUILayout.TextField("SteamCMD Path", _settings.steamCmdPath);
                if (GUILayout.Button("Browse", GUILayout.Width(70)))
                {
                    var start = string.IsNullOrWhiteSpace(_settings.steamCmdPath)
                        ? SteamUploaderPaths.ProjectRoot
                        : Path.GetDirectoryName(SteamUploaderPaths.ToAbsoluteProjectPath(_settings.steamCmdPath));
                    var chosen = EditorUtility.OpenFilePanel("Select SteamCMD", start ?? SteamUploaderPaths.ProjectRoot, "");
                    if (!string.IsNullOrWhiteSpace(chosen))
                        _settings.steamCmdPath = chosen;
                }
            }

            _settings.steamUsername = EditorGUILayout.TextField("Builder Username", _settings.steamUsername);
            _settings.steamPipeWorkingDirectory = EditorGUILayout.TextField("Working Directory", _settings.steamPipeWorkingDirectory);
            EditorGUILayout.HelpBox("Password is never stored. Log in to SteamCMD once manually so SteamCMD can reuse its cached authentication/Steam Guard session.", MessageType.Info);
        }

        private void DrawTargets()
        {
            EditorGUILayout.LabelField("Upload Targets", EditorStyles.boldLabel);

            var names = new string[_settings.targets.Count];
            for (var i = 0; i < names.Length; i++)
                names[i] = string.IsNullOrWhiteSpace(_settings.targets[i].name) ? $"Target {i + 1}" : _settings.targets[i].name;

            _settings.selectedTargetIndex = EditorGUILayout.Popup("Selected", _settings.selectedTargetIndex, names);
            var target = _settings.GetSelectedTarget();
            if (target == null)
                return;

            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            target.name = EditorGUILayout.TextField("Name", target.name);
            target.appId = EditorGUILayout.TextField("App ID", target.appId);
            target.depotId = EditorGUILayout.TextField("Depot ID", target.depotId);
            target.branch = EditorGUILayout.TextField("Branch", target.branch);
            target.buildTarget = (BuildTarget)EditorGUILayout.EnumPopup("Build Target", target.buildTarget);
            target.buildDirectory = EditorGUILayout.TextField("Build Directory", target.buildDirectory);
            target.executableName = EditorGUILayout.TextField("Executable Name", target.executableName);
            target.developmentBuild = EditorGUILayout.Toggle("Development Build", target.developmentBuild);
            target.cleanBuildDirectory = EditorGUILayout.Toggle("Clean Before Build", target.cleanBuildDirectory);
            EditorGUILayout.EndVertical();

            using (new EditorGUILayout.HorizontalScope())
            {
                if (GUILayout.Button("Add Target"))
                {
                    _settings.targets.Add(new SteamUploadTarget { name = $"Target {_settings.targets.Count + 1}" });
                    _settings.selectedTargetIndex = _settings.targets.Count - 1;
                }

                using (new EditorGUI.DisabledScope(_settings.targets.Count <= 1))
                {
                    if (GUILayout.Button("Remove Target"))
                    {
                        _settings.targets.RemoveAt(_settings.selectedTargetIndex);
                        _settings.selectedTargetIndex = Mathf.Clamp(_settings.selectedTargetIndex, 0, _settings.targets.Count - 1);
                    }
                }
            }
        }

        private void DrawActions()
        {
            EditorGUILayout.LabelField("Upload", EditorStyles.boldLabel);
            _description = EditorGUILayout.TextField("Build Description", _description);

            using (new EditorGUI.DisabledScope(_busy))
            {
                using (new EditorGUILayout.HorizontalScope())
                {
                    if (GUILayout.Button("BUILD & UPLOAD", GUILayout.Height(34)))
                        RunUpload(true);
                    if (GUILayout.Button("UPLOAD EXISTING BUILD", GUILayout.Height(34)))
                        RunUpload(false);
                }
            }

            if (_busy)
                EditorGUILayout.HelpBox("Build/upload is running. Follow progress in the log below.", MessageType.Info);
            else if (!string.IsNullOrWhiteSpace(_lastBuildId))
                EditorGUILayout.HelpBox($"Last Steam Build ID: {_lastBuildId}", MessageType.Info);
        }

        private void DrawLog()
        {
            using (new EditorGUILayout.HorizontalScope())
            {
                EditorGUILayout.LabelField("Log", EditorStyles.boldLabel);
                GUILayout.FlexibleSpace();
                if (GUILayout.Button("Clear", GUILayout.Width(60)))
                    _log.Clear();
            }

            _logScroll = EditorGUILayout.BeginScrollView(_logScroll, EditorStyles.helpBox, GUILayout.MinHeight(180));
            EditorGUILayout.SelectableLabel(_log.ToString(), EditorStyles.wordWrappedLabel, GUILayout.ExpandHeight(true));
            EditorGUILayout.EndScrollView();
        }

        private async void RunUpload(bool buildFirst)
        {
            _settings.SaveSettings();
            _busy = true;
            _lastBuildId = "";
            AppendLog($"=== {(buildFirst ? "Build & Upload" : "Upload Existing Build")} ===");

            try
            {
                var result = await SteamUploadService.BuildAndUploadAsync(
                    _settings,
                    _settings.GetSelectedTarget(),
                    _description,
                    buildFirst,
                    AppendLog);

                _lastBuildId = result.buildId;
            }
            catch (Exception ex)
            {
                AppendLog("ERROR: " + ex.Message);
                Debug.LogException(ex);
            }
            finally
            {
                _busy = false;
                Repaint();
            }
        }

        private void AppendLog(string line)
        {
            if (string.IsNullOrEmpty(line))
                return;

            _log.AppendLine(line);
            _logScroll.y = float.MaxValue;
            Repaint();
        }

        private void OnLostFocus()
        {
            _settings?.SaveSettings();
        }

        private void OnDisable()
        {
            _settings?.SaveSettings();
        }
    }
}
