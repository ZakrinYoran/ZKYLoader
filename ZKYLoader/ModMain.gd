extends Node

# Set mod priority if you want it to load before/after other mods
# Mods are loaded from lowest to highest priority, default is 0
const MOD_PRIORITY = -INF
# Name of the mod, used for writing to the logs
const MOD_NAME = "ZKYLoader"
# Directory we will search for mods
const MOD_DIRECTORY = "mods/mods"
# Path of the mod folder, automatically generated on runtime
var modPath:String = get_script().resource_path.get_base_dir() + "/"
# Required var for the replaceScene() func to work
var _savedObjects := []
# Used to print to the terminal instead of just the logs
var debugMode := false
# The instance id of this script, used to pass reference to scripts that are not loaded yet
var instance_id = get_instance_id()

# First loaded by the modloader
func _init(__ : ModLoader):
	l("Initializing...")
	# Check if the debug flag is set
	for arg in OS.get_cmdline_args():
		if arg == "--debug-mods":
			debugMode = true
			l("ModLoader debug mode active.")

	# Set the name so the node is easy to find
	name = MOD_NAME
	# Load the DLC before touching the mods
	loadDLC()
	# Extend the settings script so that mods can easily add settings
	#extendScript(modPath + "Settings.gd")
	# Load all of the mod files
	_loadMods()
	# Initialize the mods
	_initMods()

	l("Initialized.")

func _ready():
	l("Readying...")
	# Cursed way of reparenting the node to the root of the tree
	# This is so the node is easily reachable by any other mod
	# Since unfortunately I cannot set autoloads
	yield(get_parent(), "ready")
	var tree = get_tree()
	get_parent().remove_child( self)
	tree.root.call_deferred("add_child", self)

	yield(self, "tree_entered")
#	l(str(tree.root.get_children()))
	l("Ready.")


var _modZipFiles := []

func _loadMods():
	l("Loading mods...")
	var gameInstallDirectory := OS.get_executable_path().get_base_dir()
	if OS.get_name() == "OSX":
		gameInstallDirectory = gameInstallDirectory.get_base_dir().get_base_dir().get_base_dir()
	var modPathPrefix := gameInstallDirectory.plus_file(MOD_DIRECTORY)

	var dir := Directory.new()
	if dir.open(modPathPrefix) != OK:
		l("Can't open mod folder %s." % modPathPrefix)
		return 
	if dir.list_dir_begin() != OK:
		l("Can't read mod folder %s." % modPathPrefix)
		return 

	while true:
		var fileName := dir.get_next()
		if fileName == "":
			break
		if dir.current_is_dir():
			continue
		var modFSPath := modPathPrefix.plus_file(fileName)
		var modGlobalPath := ProjectSettings.globalize_path(modFSPath)
		if not ProjectSettings.load_resource_pack(modGlobalPath, true):
			l("%s failed to load." % fileName)
			continue
		_modZipFiles.append(modFSPath)
		l("%s loaded." % fileName)
	dir.list_dir_end()
	l("Done loading mods.")

func _initMods():
	l("Initializing mods...")

	var initScripts := []
	for modFSPath in _modZipFiles:
		var gdunzip = load("res://vendor/gdunzip.gd").new()
		gdunzip.load(modFSPath)
		for modEntryPath in gdunzip.files:
			var modEntryName = modEntryPath.get_file().to_lower()
			if modEntryName.begins_with("modmain") and modEntryName.ends_with(".gd"):
				var modGlobalPath = "res://" + modEntryPath
				l("Loading %s" % modGlobalPath)
				var packedScript = ResourceLoader.load(modGlobalPath)
				initScripts.append(packedScript)

	if initScripts:
		initScripts.sort_custom(self, "_compareScriptPriority")
		var scriptPriorities := []
		for script in initScripts:
			scriptPriorities.append([script.resource_path.get_slice("/", 2), 
			script.get_script_constant_map().get("MOD_PRIORITY", 0)])
		l("Initializing by priority: %s" % str(scriptPriorities))

		for packedScript in initScripts:
		# Very cursed, unfortunately i cannot find a better way to do this
			packedScript.source_code = packedScript.source_code.replace(
			"\nvar modLoader = false", "\nvar modLoader = instance_from_id(%s)" % get_instance_id())
			packedScript.reload()

			l("Running %s" % packedScript.resource_path)
			var scriptInstance = packedScript.new(self)
			add_child(scriptInstance)
		l("Done initializing mods.")
	else:
		l("No mods to initialize :(")

func _compareScriptPriority(a:Script, b:Script):
	var aPrio = a.get_script_constant_map().get("MOD_PRIORITY", 0)
	var bPrio = b.get_script_constant_map().get("MOD_PRIORITY", 0)
	if aPrio != bPrio:
		return aPrio < bPrio

	var aPath := a.resource_path
	var bPath := b.resource_path
	if aPath != bPath:
		return aPath < bPath

	return false






# Helper script to load translations using csv format
# `path` is the path to the transalation file
# `delim` is the symbol used to seperate the values
# example usage: addTranslationsFromCSV("res://ModFolder/i18n/translation.txt", "|")
func addTranslationsFromCSV(path:String, delim:String = ","):
	var modFolder := path.get_slice("/", 2)
	l("Adding translations from: %s" % path, modFolder)
	var tlFile:File = File.new()
	tlFile.open(path, File.READ)

	var translations := []

	var csvLine := tlFile.get_line().split(delim)
	l("Adding translations as: %s" % csvLine, modFolder)
	for i in range(1, csvLine.size()):
		var translationObject := Translation.new()
		translationObject.locale = csvLine[i]
		translations.append(translationObject)

	while not tlFile.eof_reached():
		csvLine = tlFile.get_csv_line(delim)

		if csvLine.size() > 1:
			var translationID := csvLine[0]
			for i in range(1, csvLine.size()):
				translations[i - 1].add_message(translationID, csvLine[i].c_unescape())
			l(str(csvLine), modFolder)

	tlFile.close()

	for translationObject in translations:
		TranslationServer.add_translation(translationObject)

	l("Translations Updated", modFolder)

# Name for legacy modloader fucntion
func installScriptExtension(childScriptPath:String):
	extendScript(childScriptPath)

# Helper function to extend scripts
# Loads the script you pass, checks what script is extended, and overrides it
func extendScript(childPath:String):
	var modFolder := childPath.get_slice("/", 2)
	var childScript:Script = ResourceLoader.load(childPath)
	var parentPath:String = childScript.get_base_script().resource_path

	l("Installing script extension: %s <- %s" % [parentPath, childPath], modFolder)

	childScript.new()
	childScript.take_over_path(parentPath)

# Helper function to replace scenes
# Can either be passed a single path, or two paths
# With a single path, it will replace the vanilla scene in the same relative position
func replaceScene(newPath:String, oldPath:String = ""):
	var modFolder := newPath.get_slice("/", 2)
	l("Updating scene: %s" % newPath, modFolder)

	if oldPath.empty():
		oldPath = newPath.replace(modFolder + "/", "")

	var scene := load(newPath)
	scene.take_over_path(oldPath)
	_savedObjects.append(scene)
	l("Finished updating: %s" % oldPath, modFolder)

func overrideAllInFolder(folderPath:String):
	l("Attempting automatic override of all resources in: %s" % folderPath)
	var files := allFilesIn(folderPath)
	for filePath in files:
		if equivalentFileExists(filePath, folderPath):
			if filePath.ends_with(".gd"):
				extendScript(filePath)
			elif filePath.ends_with(".tscn"):
				replaceScene(filePath)

func allFilesIn(scan_dir : String, filter_exts : Array = []) -> Array:
	var files := []
	var dir := Directory.new()
	if dir.open(scan_dir) != OK:
		l("Warning: could not open directory: ", scan_dir)
		return []

	if dir.list_dir_begin(true, true) != OK:
		l("Warning: could not list contents of: ", scan_dir)
		return []

	var file := dir.get_next()
	while file != "":
		if dir.current_is_dir():
			l("Found directory: " + file)
			files += allFilesIn(dir.get_current_dir() + "/" + file, filter_exts)
		else:
			if filter_exts.size() == 0:
				l("Found file: " + file)
				files.append(dir.get_current_dir() + "/" + file)
			else:
				for ext in filter_exts:
					if file.get_extension() == ext:
						l("Found file: " + file)
						files.append(dir.get_current_dir() + "/" + file)
		file = dir.get_next()
	return files

func equivalentFileExists(filePath:String, dirFrom : String, dirTo : = "res://") -> bool:
	return ResourceLoader.exists(filePath.replace(dirFrom, dirTo))

# Instances Settings.gd, loads DLC, then frees the script.
# Sometimes needed for mods to be compatible with DLC
func loadDLC():
	l("Preloading DLC for mod compatability")
	var DLCLoader:Settings = preload("res://Settings.gd").new()
	DLCLoader.loadDLC()
	DLCLoader.queue_free()
	l("Finished loading DLC")

# Func to print messages to the logs
# Also prints to the console if argument is used
func l(msg:String, title:String = MOD_NAME):
	var text := "[%s]: %s" % [title, msg]
	if debugMode: print(text)
	Debug.l(text)
