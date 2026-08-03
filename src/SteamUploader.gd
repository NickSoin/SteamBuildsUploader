extends PanelContainer

const ENCRYPT_PW : String		= "STEAMUPLOADGUI"
const SETTINGS_FILE : String	= "/SteamUploadGUI_settings.bin"
const STEAMCMD : String			= "steamcmd.exe"
const RUNNER_FILE : String		= "/SteamUploadGUI_runner.ps1"
const LAST_LOG_FILE : String	= "/SteamUploadGUI_last_upload.log"
const EXIT_CODE_FILE : String	= "/SteamUploadGUI_upload_exit_code.txt"
const MAX_VISIBLE_LOG_CHARS : int = 80000
const TEXT_WAIT_DEPOT : String	= "SteamCMD is running in the background.\nUploading Depot ID '%s' for App ID '%s'"
const TEMP_DEPOT_BUILD_PREFIX : String = "_steam_upload_gui_depot_"
const DEPOT_APP_BUILD_TEMPLATE : String = "\"AppBuild\"\n{\n\t\"AppID\" \"%s\"\n\t\"Desc\" \"%s\"\n\t\"Preview\" \"0\"\n\t\"ContentRoot\" \"%s\"\n\t\"BuildOutput\" \"%s\"\n\n\t\"Depots\"\n\t{\n\t\t\"%s\"\n\t\t{\n\t\t\t\"FileMapping\"\n\t\t\t{\n\t\t\t\t\"LocalPath\" \"*\"\n\t\t\t\t\"DepotPath\" \".\"\n\t\t\t\t\"Recursive\" \"1\"\n\t\t\t}\n\t\t}\n\t}\n}\n"
const POWERSHELL_RUNNER : String = "param(\n\t[string]$SteamCmdPathB64,\n\t[string]$UsernameB64,\n\t[string]$PasswordB64,\n\t[string]$VdfPathB64,\n\t[string]$LogPathB64,\n\t[string]$ExitCodePathB64,\n\t[string]$UseCachedLogin\n)\n$utf8 = [Text.Encoding]::UTF8\n$steamCmdPath = $utf8.GetString([Convert]::FromBase64String($SteamCmdPathB64))\n$username = $utf8.GetString([Convert]::FromBase64String($UsernameB64))\n$password = $utf8.GetString([Convert]::FromBase64String($PasswordB64))\n$vdfPath = $utf8.GetString([Convert]::FromBase64String($VdfPathB64))\n$logPath = $utf8.GetString([Convert]::FromBase64String($LogPathB64))\n$exitCodePath = $utf8.GetString([Convert]::FromBase64String($ExitCodePathB64))\n$encoding = New-Object System.Text.UTF8Encoding($false)\n[IO.File]::WriteAllText($logPath, '', $encoding)\nfunction Write-UploadLog([string]$Line) {\n\t[IO.File]::AppendAllText($logPath, $Line + [Environment]::NewLine, $encoding)\n}\nfunction Invoke-SteamUpload([bool]$WithPassword) {\n\t$steamArgs = @(\n\t\t'+@ShutdownOnFailedCommand', '1',\n\t\t'+@NoPromptForPassword', '1',\n\t\t'+login', $username\n\t)\n\tif ($WithPassword) {\n\t\t$steamArgs += $password\n\t}\n\t$steamArgs += @('+run_app_build', $vdfPath, '+quit')\n\t& $steamCmdPath @steamArgs 2>&1 | ForEach-Object {\n\t\tWrite-UploadLog $_.ToString()\n\t}\n\treturn [int]$LASTEXITCODE\n}\n$useCache = $UseCachedLogin -eq '1'\nif ($useCache) {\n\tWrite-UploadLog 'Using cached SteamCMD login. Password login will only be used if the cached session expired.'\n\t$steamExitCode = Invoke-SteamUpload $false\n\t$logText = [IO.File]::ReadAllText($logPath)\n\t$authFailure = $logText -match '(?i)invalid password|no cached|login failure|failed to log|not logged on|account logon denied'\n\tif ($steamExitCode -ne 0 -and $authFailure -and $password.Length -gt 0) {\n\t\tWrite-UploadLog 'Cached SteamCMD login expired. Retrying once with the saved password.'\n\t\t$steamExitCode = Invoke-SteamUpload $true\n\t}\n} else {\n\tWrite-UploadLog 'No cached SteamCMD login found. Signing in once; later uploads will reuse the cached session.'\n\t$steamExitCode = Invoke-SteamUpload $true\n}\n[IO.File]::WriteAllText($exitCodePath, [string]$steamExitCode, $encoding)\nexit $steamExitCode\n"
var local_dir : String			= ""
var contentbuilder_dir : String = ""
var scripts_path : String		= ""
var builder_path : String		= ""
var users : Dictionary			= {}
var pending_uploads : Array		= []
var active_upload : Dictionary	= {}
var active_upload_pid : int		= -1
var active_log_text : String	= ""
var last_depot_build_path : String = ""
var last_depot_app_id : String	= ""
var last_depot_id : String		= ""

func _ready() -> void:
	local_dir = ProjectSettings.globalize_path("res://")
	if local_dir == "":
		local_dir = OS.get_executable_path().get_base_dir()
	else:
		local_dir = local_dir.get_base_dir()
	contentbuilder_dir = find_default_contentbuilder_dir()
	
	# Load local Settings saved from last Upload
	var save_pw_file := File.new()
	if save_pw_file.file_exists(local_dir + SETTINGS_FILE):
		var open_error : int = save_pw_file.open_encrypted_with_pass(local_dir + SETTINGS_FILE, File.READ, ENCRYPT_PW)
		if open_error == OK:
			var settings_json_result : JSONParseResult = JSON.parse(save_pw_file.get_as_text())
			if settings_json_result.error == OK and typeof(settings_json_result.result) == TYPE_DICTIONARY:
				if settings_json_result.result.has("users"):
					users = settings_json_result.result.users
				if settings_json_result.result.has("path"):
					contentbuilder_dir = settings_json_result.result.path
				if settings_json_result.result.has("last_depot_build_path"):
					last_depot_build_path = settings_json_result.result.last_depot_build_path
				if settings_json_result.result.has("last_depot_app_id"):
					last_depot_app_id = settings_json_result.result.last_depot_app_id
				if settings_json_result.result.has("last_depot_id"):
					last_depot_id = settings_json_result.result.last_depot_id
	save_pw_file.close()
	for u in users.keys():
		if not users[u].has("save_pw") or not users[u].has("pw") or not users[u].has("username"):
			users.erase(u)
	update_users()
	$"%ContentBuilderPathEdit".text = contentbuilder_dir
	if check_contentbuilder_path():
		restore_last_depot_values_from_temp_vdfs()


func find_default_contentbuilder_dir() -> String:
	var search_dir : String = local_dir
	var directory := Directory.new()
	for _index in range(5):
		var candidate : String = search_dir.plus_file("steamworks_sdk_164/sdk/tools/ContentBuilder")
		if directory.dir_exists(candidate):
			return candidate.replace("\\", "/")
		var parent_dir : String = search_dir.get_base_dir()
		if parent_dir == search_dir:
			break
		search_dir = parent_dir
	return local_dir.get_base_dir().plus_file("steamworks_sdk_164/sdk/tools/ContentBuilder").replace("\\", "/")


func check_contentbuilder_path() -> bool:
	var dir := Directory.new()
	var file := File.new()
	contentbuilder_dir = contentbuilder_dir.trim_suffix("/").trim_suffix("\\")
	var entered_path : String = contentbuilder_dir
	var nested_builder_path : String = entered_path + "/builder/"
	if dir.dir_exists(nested_builder_path):
		builder_path = nested_builder_path
	elif entered_path.get_file().to_lower() == "builder" or file.file_exists(entered_path + "/" + STEAMCMD):
		builder_path = entered_path + "/"
		contentbuilder_dir = entered_path.get_base_dir()
	else:
		builder_path = nested_builder_path
		$"%ContentBuilderStatus".text = "Select ContentBuilder or ContentBuilder/builder"
		$"%ContentBuilderStatus".modulate = Color(1, 0.35, 0.35, 1)
		$"%UploadDepotButton".disabled = true
		return false
	if !file.file_exists(builder_path + STEAMCMD):
		$"%ContentBuilderStatus".text = "steamcmd.exe not found in the selected folder"
		$"%ContentBuilderStatus".modulate = Color(1, 0.35, 0.35, 1)
		$"%UploadDepotButton".disabled = true
		return false
	scripts_path = contentbuilder_dir + "/scripts/"
	$"%ContentBuilderStatus".text = "SteamCMD ready"
	$"%ContentBuilderStatus".modulate = Color(0.4, 0.9, 0.55, 1)
	$"%UploadDepotButton".disabled = false
	return true


func list_vdf_files_in_directory(path:String) -> Array:
	var files = []
	var dir = Directory.new()
	dir.open(path)
	dir.list_dir_begin(true)
	
	while true:
		var file = dir.get_next()
		if file == "":
			break
		elif not file.begins_with(".") and file.ends_with(".vdf"):
			files.append(file)
	
	dir.list_dir_end()
	return files


func restore_last_depot_values_from_temp_vdfs() -> void:
	if last_depot_build_path != "" and last_depot_app_id != "" and last_depot_id != "":
		return
	var candidates : Array = []
	for file_name in list_vdf_files_in_directory(scripts_path):
		if file_name.begins_with(TEMP_DEPOT_BUILD_PREFIX):
			candidates.append(file_name)
	if candidates.empty():
		return
	candidates.sort()
	var content : String = read_text_file(scripts_path + candidates[candidates.size() - 1])
	var content_root_regex := RegEx.new()
	content_root_regex.compile("(?i)\"contentroot\"\\s*\"([^\"]+)\"")
	var depot_regex := RegEx.new()
	depot_regex.compile("(?i)\"depots\"\\s*\\{\\s*\"(\\d+)\"")
	var app_regex := RegEx.new()
	app_regex.compile("(?i)\"appid\"\\s*\"(\\d+)\"")
	var content_root_match : RegExMatch = content_root_regex.search(content)
	var depot_match : RegExMatch = depot_regex.search(content)
	var app_match : RegExMatch = app_regex.search(content)
	if last_depot_build_path == "" and content_root_match:
		last_depot_build_path = content_root_match.get_string(1)
	if last_depot_app_id == "" and app_match:
		last_depot_app_id = app_match.get_string(1)
	if last_depot_id == "" and depot_match:
		last_depot_id = depot_match.get_string(1)


func get_selected_username() -> String:
	var user_selection : OptionButton = $"%UserSelectionButton"
	if user_selection.get_item_count() == 0:
		return ""
	return user_selection.get_item_text(user_selection.get_selected())


func steamcmd_has_cached_account(username:String) -> bool:
	if username == "":
		return false
	var config_path : String = builder_path + "config/config.vdf"
	var config_content : String = read_text_file(config_path).to_lower()
	var accounts_position : int = config_content.find("\"accounts\"")
	if accounts_position < 0:
		return false
	return config_content.find("\"%s\"" % username.to_lower(), accounts_position) >= 0


func normalize_vdf_path(path:String) -> String:
	return path.replace("\\", "/").trim_suffix("/")


func get_depot_build_description(depot_id:String) -> String:
	var now : Dictionary = OS.get_datetime()
	return "Depot %s build %04d-%02d-%02d %02d:%02d" % [depot_id, now.year, now.month, now.day, now.hour, now.minute]


func set_depot_upload_error(message:String) -> void:
	$"%DepotUploadError".text = message
	$"%DepotUploadError".visible = message != ""


func set_upload_controls_disabled(disabled:bool) -> void:
	$"%UploadDepotButton".disabled = disabled


func cleanup_upload_file(path:String) -> void:
	if path == "":
		return
	var cleanup := Directory.new()
	if cleanup.file_exists(path):
		cleanup.remove(path)


func cleanup_pending_upload_files() -> void:
	for upload in pending_uploads:
		cleanup_upload_file(upload.get("cleanup_path", ""))
	pending_uploads.clear()


func read_text_file(path:String) -> String:
	var file := File.new()
	if not file.file_exists(path):
		return ""
	if file.open(path, File.READ) != OK:
		return ""
	var content : String = file.get_as_text()
	file.close()
	return content


func write_upload_runner() -> bool:
	var runner := File.new()
	if runner.open(local_dir + RUNNER_FILE, File.WRITE) != OK:
		return false
	runner.store_string(POWERSHELL_RUNNER)
	runner.close()
	return true


func refresh_upload_log() -> void:
	var latest_log : String = read_text_file(local_dir + LAST_LOG_FILE)
	if latest_log == active_log_text:
		return
	active_log_text = latest_log
	var visible_log : String = latest_log
	if visible_log.length() > MAX_VISIBLE_LOG_CHARS:
		visible_log = "... earlier output omitted from the window ...\n" + visible_log.right(MAX_VISIBLE_LOG_CHARS)
	$"%SteamUploadLog".text = visible_log
	$"%SteamUploadLog".scroll_vertical = 999999


func show_upload_result(message:String) -> void:
	$"%SteamUploadLabel".text = message
	$"%SteamUploadCloseButton".show()
	$"%SteamUploadingPopup".popup_centered(Vector2(900, 600))


func begin_steam_uploads(uploads:Array) -> bool:
	if active_upload_pid > 0 or not pending_uploads.empty():
		return false
	if uploads.empty():
		return false
	var username : String = get_selected_username()
	var password : String = $"%UserPasswordEdit".text
	var use_cached_login : bool = steamcmd_has_cached_account(username)
	if not use_cached_login and password == "":
		show_upload_result("No cached SteamCMD login was found. Enter the Steam password once; later uploads will reuse the cached session.")
		return false
	for upload in uploads:
		upload["username"] = username
		upload["password"] = password
		upload["use_cached_login"] = use_cached_login
		upload["steamcmd_path"] = builder_path + STEAMCMD
		pending_uploads.append(upload)
	set_upload_controls_disabled(true)
	$"%SteamUploadCloseButton".hide()
	$"%SteamUploadLog".text = ""
	$"%SteamUploadingPopup".popup_centered(Vector2(900, 600))
	start_next_steam_upload()
	return true


func start_next_steam_upload() -> void:
	if pending_uploads.empty():
		set_upload_controls_disabled(false)
		return
	active_upload = pending_uploads.pop_front()
	$"%SteamUploadLabel".text = TEXT_WAIT_DEPOT % [active_upload["depot_id"], active_upload["app_id"]]
	cleanup_upload_file(local_dir + LAST_LOG_FILE)
	cleanup_upload_file(local_dir + EXIT_CODE_FILE)
	cleanup_upload_file(local_dir + RUNNER_FILE)
	active_log_text = ""
	$"%SteamUploadLog".text = "Starting SteamCMD..."
	if not write_upload_runner():
		cleanup_upload_file(active_upload.get("cleanup_path", ""))
		cleanup_pending_upload_files()
		set_upload_controls_disabled(false)
		show_upload_result("Could not create the SteamCMD runner.")
		return
	var powershell_args : PoolStringArray = [
		"-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-File", local_dir + RUNNER_FILE,
		"-SteamCmdPathB64", Marshalls.utf8_to_base64(active_upload["steamcmd_path"]),
		"-UsernameB64", Marshalls.utf8_to_base64(active_upload["username"]),
		"-PasswordB64", Marshalls.utf8_to_base64(active_upload["password"]),
		"-VdfPathB64", Marshalls.utf8_to_base64(normalize_vdf_path(active_upload["vdf_path"])),
		"-LogPathB64", Marshalls.utf8_to_base64(local_dir + LAST_LOG_FILE),
		"-ExitCodePathB64", Marshalls.utf8_to_base64(local_dir + EXIT_CODE_FILE),
		"-UseCachedLogin", "1" if active_upload["use_cached_login"] else "0"
	]
	active_upload_pid = OS.execute("powershell.exe", powershell_args, false, [], false, false)
	if active_upload_pid <= 0:
		cleanup_upload_file(active_upload.get("cleanup_path", ""))
		cleanup_pending_upload_files()
		cleanup_upload_file(local_dir + RUNNER_FILE)
		set_upload_controls_disabled(false)
		show_upload_result("Could not start the background SteamCMD process.")
		return
	$"%UploadProcessTimer".start()


func get_upload_result(exit_code:int, output_text:String) -> Dictionary:
	var output_lower : String = output_text.to_lower()
	if "successfully finished appid" in output_lower:
		var build_id_regex := RegEx.new()
		build_id_regex.compile("(?i)buildid[^0-9]*(\\d+)")
		var build_id_match : RegExMatch = build_id_regex.search(output_text)
		var build_id : String = build_id_match.get_string(1) if build_id_match else "unknown"
		return {"success": true, "message": "Upload completed successfully.\nBuildID: %s" % build_id}
	if "invalid password" in output_lower:
		return {"success": false, "message": "Steam login failed: invalid password."}
	if "need two-factor code" in output_lower or "steam guard" in output_lower:
		return {"success": false, "message": "Steam Guard confirmation is required. Approve the login and retry."}
	if "timed out" in output_lower or "error (timeout)" in output_lower:
		return {"success": false, "message": "Steam login timed out. Approve the Steam Guard request and retry."}
	if exit_code != 0 or "error!" in output_lower or "error (" in output_lower:
		return {"success": false, "message": "SteamCMD stopped with an error (code %s)." % exit_code}
	return {"success": false, "message": "SteamCMD finished without a confirmed App Build success message."}


func _on_UploadProcessTimer_timeout() -> void:
	refresh_upload_log()
	if active_upload_pid > 0 and OS.is_process_running(active_upload_pid):
		return
	$"%UploadProcessTimer".stop()
	refresh_upload_log()
	var exit_code_text : String = read_text_file(local_dir + EXIT_CODE_FILE).strip_edges()
	var exit_code : int = int(exit_code_text) if exit_code_text.is_valid_integer() else -1
	active_upload_pid = -1
	cleanup_upload_file(active_upload.get("cleanup_path", ""))
	cleanup_upload_file(local_dir + EXIT_CODE_FILE)
	cleanup_upload_file(local_dir + RUNNER_FILE)
	var result : Dictionary = get_upload_result(exit_code, active_log_text)
	if not result["success"]:
		cleanup_pending_upload_files()
		set_upload_controls_disabled(false)
		show_upload_result(result["message"])
		return
	if pending_uploads.empty():
		set_upload_controls_disabled(false)
		show_upload_result(result["message"])
	else:
		start_next_steam_upload()


func _on_SteamUploadCloseButton_pressed() -> void:
	$"%SteamUploadingPopup".hide()


func _on_UploadDepotButton_pressed() -> void:
	if active_upload_pid > 0 or not pending_uploads.empty():
		show_upload_result("An upload is already running.")
		return
	$"%DepotBuildPathEdit".text = last_depot_build_path
	$"%DepotAppIdEdit".text = last_depot_app_id
	$"%DepotIdEdit".text = last_depot_id
	$"%DepotUploadConfirmButton".disabled = last_depot_build_path == "" or last_depot_app_id == "" or last_depot_id == ""
	set_depot_upload_error("")
	$"%DepotUploadPopup".popup_centered(Vector2(680, 285))
	$"%DepotBuildPathEdit".grab_focus()


func _on_DepotUploadInput_text_changed(_new_text:String) -> void:
	last_depot_build_path = $"%DepotBuildPathEdit".text.strip_edges().trim_prefix("\"").trim_suffix("\"")
	last_depot_app_id = $"%DepotAppIdEdit".text.strip_edges()
	last_depot_id = $"%DepotIdEdit".text.strip_edges()
	var has_build_path : bool = last_depot_build_path != ""
	var has_app_id : bool = last_depot_app_id != ""
	var has_depot_id : bool = last_depot_id != ""
	$"%DepotUploadConfirmButton".disabled = not (has_build_path and has_app_id and has_depot_id)
	save_settings()
	set_depot_upload_error("")


func _on_DepotUploadCancelButton_pressed() -> void:
	$"%DepotUploadPopup".hide()


func _on_DepotUploadConfirmButton_pressed() -> void:
	var build_path : String = $"%DepotBuildPathEdit".text.strip_edges().trim_prefix("\"").trim_suffix("\"")
	var app_id : String = $"%DepotAppIdEdit".text.strip_edges()
	var depot_id : String = $"%DepotIdEdit".text.strip_edges()
	$"%DepotBuildPathEdit".text = build_path
	last_depot_build_path = build_path
	last_depot_app_id = app_id
	last_depot_id = depot_id
	save_settings()

	var build_directory := Directory.new()
	if not build_directory.dir_exists(build_path):
		set_depot_upload_error("Build folder does not exist.")
		return
	if not depot_id.is_valid_integer() or int(depot_id) <= 0:
		set_depot_upload_error("Depot ID must be a positive number.")
		return
	if not app_id.is_valid_integer() or int(app_id) <= 0:
		set_depot_upload_error("App ID must be a positive number.")
		return
	if get_selected_username() == "":
		set_depot_upload_error("Add and select a Steam user first.")
		return
	if not steamcmd_has_cached_account(get_selected_username()) and $"%UserPasswordEdit".text == "":
		set_depot_upload_error("Enter the Steam password once to create a cached SteamCMD login.")
		return
	if not check_contentbuilder_path():
		set_depot_upload_error("Content Builder path or steamcmd.exe is not valid.")
		return

	scripts_path = contentbuilder_dir + "/scripts/"
	var scripts_directory := Directory.new()
	if not scripts_directory.dir_exists(scripts_path):
		set_depot_upload_error("Content Builder scripts folder was not found.")
		return

	var timestamp : int = OS.get_unix_time()
	var temp_vdf_name : String = "%s%s_%s_%s.vdf" % [TEMP_DEPOT_BUILD_PREFIX, app_id, depot_id, timestamp]
	var temp_vdf_path : String = scripts_path + temp_vdf_name
	var vdf_content : String = DEPOT_APP_BUILD_TEMPLATE % [
		app_id,
		get_depot_build_description(depot_id),
		normalize_vdf_path(build_path),
		normalize_vdf_path(contentbuilder_dir + "/output"),
		depot_id
	]
	var temp_vdf := File.new()
	if temp_vdf.open(temp_vdf_path, File.WRITE) != OK:
		set_depot_upload_error("Could not create the temporary SteamPipe VDF.")
		return
	temp_vdf.store_string(vdf_content)
	temp_vdf.close()

	$"%DepotUploadPopup".hide()
	begin_steam_uploads([{
		"vdf_path": temp_vdf_path,
		"app_id": app_id,
		"depot_id": depot_id,
		"cleanup_path": temp_vdf_path
	}])


func save_settings() -> void:
	# Save the Settings
	var save_pw_file := File.new()
	var open_error : int = save_pw_file.open_encrypted_with_pass(local_dir + SETTINGS_FILE, File.WRITE, ENCRYPT_PW)
	if open_error != OK:
		push_error("Could not save Steam Upload GUI settings (error %s)." % open_error)
		return
	var settings_dict := {
		"path" : $"%ContentBuilderPathEdit".text,
		"users" : users,
		"last_depot_build_path" : last_depot_build_path,
		"last_depot_app_id" : last_depot_app_id,
		"last_depot_id" : last_depot_id
		}
	save_pw_file.store_string(JSON.print(settings_dict))
	save_pw_file.close()


func _on_ContentBuilderPathEdit_text_entered(new_text:String) -> void:
	contentbuilder_dir = new_text.strip_edges().trim_suffix("/").trim_suffix("\\")
	check_contentbuilder_path()
	save_settings()


func _on_OpenDirButton_pressed():
	var folder_path : String = $"%ContentBuilderPathEdit".text.strip_edges()
	var directory := Directory.new()
	if not directory.dir_exists(folder_path):
		$"%ContentBuilderStatus".text = "Folder does not exist"
		$"%ContentBuilderStatus".modulate = Color(1, 0.35, 0.35, 1)
		return
	var explorer_pid : int = OS.execute("explorer.exe", [folder_path.replace("/", "\\")], false)
	if explorer_pid == -1:
		$"%ContentBuilderStatus".text = "Could not open Windows Explorer"
		$"%ContentBuilderStatus".modulate = Color(1, 0.35, 0.35, 1)


func _on_popup_about_to_show():
	$PopupLayer/PopupBG.show()


func _on_popup_hide():
	$PopupLayer/PopupBG.hide()


func _on_ManageUsersButton_pressed():
	$PopupLayer/UserDialogBG.show()
	$"%UserDialog".popup_centered()


func update_users(and_selection:=true):
	for c in $"%UserList".get_children():
		c.queue_free()
	if and_selection:
		$"%UserSelectionButton".clear()
	if users.empty():
		$"%UsersHbox".hide()
		$"%AddUsersButton".show()
		return
	$"%UsersHbox".show()
	$"%AddUsersButton".hide()
	for u in users.keys():
		var new_user = preload("res://UserPanel.tscn").instance()
		new_user.username = u
		new_user.save_pw = users[u].save_pw
		$"%UserList".add_child(new_user)
		if and_selection:
			$"%UserSelectionButton".add_item(u)
		new_user.connect("delete_user", self, "on_delete_user", [u])
		new_user.connect("save_password", self, "on_save_password", [u])
	if and_selection:
		$"%UserSelectionButton".select(0)
		_on_UserSelectionButton_item_selected(0)


func _on_AddUserButton_pressed():
	var new_user : Dictionary = create_user_dict($"%AddUserNameLineEdit".text)
	users[$"%AddUserNameLineEdit".text] = new_user
	$"%AddUserNameLineEdit".text = ""
	update_users()
	save_settings()


func create_user_dict(username:String) -> Dictionary:
	return {"username" : username, "save_pw" : true, "pw": ""}


func on_delete_user(username:String):
	if users.has(username):
		users.erase(username)
	update_users()
	save_settings()


func on_save_password(save_pw:bool, username:String):
	if users.has(username):
		users[username].save_pw = save_pw
	update_users(false)
	save_settings()


func _on_CloseUserManagementButton_pressed():
	$"%UserDialog".hide()
	$PopupLayer/UserDialogBG.hide()
	update_users()
	save_settings()


func _on_SavePW_pressed():
	var selected_user : String = $"%UserSelectionButton".get_item_text($"%UserSelectionButton".get_selected_id())
	if users.has(selected_user):
		users[selected_user].save_pw = $"%SavePW".pressed
	update_users(false)
	save_settings()


func _on_UserSelectionButton_item_selected(index):
	var selected_user : String = $"%UserSelectionButton".get_item_text(index)
	if users.has(selected_user):
		$"%SavePW".pressed = users[selected_user].save_pw
		if users[selected_user].save_pw:
			$"%UserPasswordEdit".text = users[selected_user].pw
		else:
			$"%UserPasswordEdit".text = ""


func _on_UserPasswordEdit_text_changed(new_text):
	var selected_user : String = $"%UserSelectionButton".get_item_text($"%UserSelectionButton".get_selected_id())
	if users.has(selected_user) and users[selected_user].save_pw:
		users[selected_user].pw = $"%UserPasswordEdit".text
	save_settings()
