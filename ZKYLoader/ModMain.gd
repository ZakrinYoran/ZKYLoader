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
var consoleLogs := false
# Determine if debug information should be displayed
var debugMode := false
# The instance id of this script, used to pass reference to scripts that are not loaded yet
var instance_id = get_instance_id()

# First loaded by the modloader
func _init(__ : ModLoader):
	l("Initializing...")
	# Check if the debug flag is set
	for arg in OS.get_cmdline_args():
		if arg == "--console-logs":
			consoleLogs = true
			l("Printing ModLoader logs to console.")

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
	loadMods()
	# Unzip the mod files
	unzipMods()
	# Initialize the mods
	initMods()
	# Override vanilla files
	autoOverride()


	l("Initialized.")

func _ready():
	l("Readying...")
	# Cursed way of reparenting the node to the root of the tree
	# This is so the node is easily reachable by any other mod
	# Unfortunately I cannot set autoloads (as far as I am aware)
	yield(get_parent(), "ready")
	var tree = get_tree()
	get_parent().remove_child( self)
	tree.root.call_deferred("add_child", self)
	yield(self, "tree_entered")
	l("Ready.")


var modZipFiles := []
# Load any zip files in the mods folder
func loadMods():
	l("Loading mods...")
# Determine path to mods folder
	var gameInstallDirectory := OS.get_executable_path().get_base_dir()
	if OS.get_name() == "OSX":
		gameInstallDirectory = gameInstallDirectory.get_base_dir().get_base_dir().get_base_dir()
	var modPathPrefix := gameInstallDirectory.plus_file(MOD_DIRECTORY)

# Try to open the folder
	var dir := Directory.new()
	if dir.open(modPathPrefix) != OK:
		e("Can't open mod folder %s." % modPathPrefix)
		return
	if dir.list_dir_begin() != OK:
		e("Can't read mod folder %s." % modPathPrefix)
		return

# Scan and load any files in the folder
	while true:
		var fileName := dir.get_next()
		if fileName == "":
			break
		if dir.current_is_dir():
			continue
		var modFSPath := modPathPrefix.plus_file(fileName)
		var modGlobalPath := ProjectSettings.globalize_path(modFSPath)
		if not ProjectSettings.load_resource_pack(modGlobalPath, true):
			e("%s failed to load." % fileName)
			continue
		modZipFiles.append(modFSPath)
		l("%s loaded." % fileName)
	dir.list_dir_end()
	l("Done loading mods.")

var modUnzipFiles := {}
# Decompress mod files
func unzipMods():
	for modFSPath in modZipFiles:
		var gdunzip = load("res://vendor/gdunzip.gd").new()
		gdunzip.load(modFSPath)
		modUnzipFiles[modFSPath] = gdunzip

var modOverrideFiles := []
var modIgnoreFiles := []
var modAliasFiles := {}
# Run ModMain files
func initMods():
	l("Initializing mods...")
# Detect the Modmains
	var initScripts := []
	for modPath in modUnzipFiles:
		var modMainFile:Script
		for modFile in modUnzipFiles[modPath].files:
			var modEntryName = modFile.get_file().to_lower()
			if modEntryName == "modmain.gd":
				var modGlobalPath = "res://" + modFile
				d("Detected ModMain: %s" % modGlobalPath)
				modMainFile = ResourceLoader.load(modGlobalPath)
				break
		if modMainFile: initScripts.append(modMainFile)
		else: d("No ModMain Detected for: %s" % modPath.get_file())

# Handle the ModMains
	if initScripts:
	# Sort by priority
		initScripts.sort_custom(self, "compareScriptPriority")
	# Display the mod priorities
		var scriptPriorities := []
		for script in initScripts:
			scriptPriorities.append([script.resource_path.get_slice("/", 2),
			script.get_script_constant_map().get("MOD_PRIORITY", 0)])
		d("Initializing by priority: %s" % str(scriptPriorities))

		for packedScript in initScripts:
		# Very cursed, i cannot think of a better way to do this
			packedScript.source_code = packedScript.source_code.replace(
			"\nvar modLoader = false", "\nvar modLoader = instance_from_id(%s)" % get_instance_id())
			packedScript.reload()
		# Initialize the ModMains
			l("Running %s" % packedScript.resource_path)
			var scriptInstance = packedScript.new(self)
			add_child(scriptInstance)

		# If any files should be ignored during automatic override
			if "ignoreFiles" in scriptInstance:
				modIgnoreFiles += scriptInstance.ignoreFiles

		# If any files should be treated as different files
			if "aliasFiles" in scriptInstance:
				modAliasFiles.merge(scriptInstance.aliasFiles)

		l("Done initializing mods.")
	else:
		l("No mods to initialize :(")

# Sort scripts by priority, lowest to highest
func compareScriptPriority(a:Script, b:Script):
	var aPrio = a.get_script_constant_map().get("MOD_PRIORITY", 0)
	var bPrio = b.get_script_constant_map().get("MOD_PRIORITY", 0)
	if aPrio != bPrio:
		return aPrio < bPrio

	var aPath := a.resource_path
	var bPath := b.resource_path
	if aPath != bPath:
		return aPath < bPath

	return false


######################################################


# Autommatically determine dependencies and override vanilla resources
func autoOverride():
	l("Attempting automatic override of all resources...")
	var time := OS.get_ticks_msec()
	var fileReplacements := {}
	var translationFiles := []

	for modPath in modUnzipFiles:
		for modFile in modUnzipFiles[modPath].files:
			var modFolder = modFile.get_slice("/", 0)
			modFile = "res://" + modFile
		# Ignore folders
			if modFile.ends_with("/"):
				continue
		# Check if file should be ignored
			elif modFile in modIgnoreFiles:
				d("Ignoring file: %s" % modFile)
				continue

		# Check for translation files
			elif modFile.get_base_dir().get_file() == "i18n":
				d("Detected translation: %s" % modFile)
				translationFiles.append(modFile)
		
		# Check if it has a file alias
			elif modFile in modAliasFiles:
				var alias = modAliasFiles[modFile]
				d("Aliasing %s as %s"% [modFile, alias])

				if not alias in fileReplacements:
					fileReplacements[alias] = []
				fileReplacements[alias].append(modFile)

				getDependenciesFor(modFile)
		
		# Check for files that exist in vanilla
			elif equivalentFileExists(modFile, modFolder):
				d("Detected override: %s" % modFile)
				var vanillaFile = modFile.replace(modFolder+"/", "")

				if not vanillaFile in fileReplacements:
					fileReplacements[vanillaFile] = []
				fileReplacements[vanillaFile].append(modFile)

				getDependenciesFor(modFile)

	for file in translationFiles:
		addTranslationsFromCSV(file)

	var fileKeys = filePriorities.keys()
	fileKeys.sort_custom(self, "sortPriorities")
	for key in fileKeys:
		if key in fileReplacements:
			for file in fileReplacements[key]:
			# Check if the file has an alias
				var alias := ""
				if file in modAliasFiles:
					alias = modAliasFiles[file]

				match file.get_extension():
					"gd": # Extend scripts
						extendScript(file, alias)
					"tscn": # Replace scenes
						replaceScene(file, alias)
	l("Automatic override complete in %s ms." % (OS.get_ticks_msec()-time))

# Check if equivilent vanilla file exists
func equivalentFileExists(filePath:String, dirFrom := "", dirTo : = "") -> bool:
	if not dirFrom: dirFrom = filePath.get_slice("/", 2)
	return ResourceLoader.exists(filePath.replace(dirFrom, dirTo))

# Sort by priority, from lowest to highest
func sortPriorities(a, b):
	return filePriorities[a] < filePriorities[b]

var filePriorities := {}
# Get all dependencies for a file
func getDependenciesFor(path:String, idx := 0):
	if idx <= -100:
		e("Possible recursion detected, terminating search of %s" % path)
		return
	var dependencies := ResourceLoader.get_dependencies(path)
# If the file is a script
	if path.ends_with(".gd"):
	# If a vanilla script exists
		if ResourceLoader.exists(path + "c"):
		# Check for script dependencies
			dependencies.append_array(getScriptDependencies(path + "c"))

	if dependencies:
		for d in dependencies:
		# Ignore if the file already exists at a lower priority
			if d in filePriorities:
				if idx >= filePriorities[d]:
					continue
		# Add to the priority list
			filePriorities[d] = idx
			getDependenciesFor(d, idx -1)

# EVIL DEVIL MAGIC
# Hex encoding for "res://", our keyword for finding dependencies
var resHex := "res://".to_ascii().hex_encode()
func getScriptDependencies(scriptPath:String)->Array:
# Open the script file
	var file := File.new()
	file.open(scriptPath, File.READ)
# Get the bytecode of the script as a PackedByteArray
	var bytecode := file.get_buffer(file.get_len())
	file.close()
# Encode the bytecode as hex for easier searching
	var bytecodeStr := bytecode.hex_encode()
# If our keyword is in the hexcode
	if resHex in bytecodeStr:
		var dependencies := []
	# Split the hexcode into segments at every instance of our keyword
		var hexArray := bytecodeStr.split(resHex)
	# Track our offset in the script file
		var buffer := 0
	# For every instance of our keyword
		for idx in hexArray.size():
		# Get the hex text of that segment
			var hexText := hexArray[idx]
		# The first segment does not have the keyword, so continue
			if idx > 0:
			# Add our keyword back to the string, as it gets removed by .split()
				hexText = resHex + hexText
			# Get the section of the bytecode that corrosponds to our hexcode
				var resByte := bytecode.subarray(buffer, buffer + hexText.length()/2.0 - 1)
			# Parse the dependency path and add it to the array
				dependencies.append(resByte.get_string_from_ascii())
		# Update our offset in the bytecode
			buffer += hexText.length()/2.0
	# Display any dependencies found
		d("Additional dependencies found for %s: %s" % [scriptPath, dependencies])
	# Return what we found
		return dependencies
# Return nothing if no dependencies
	return []


#########################################################


# Helper script to load translations using csv format
# `path` is the path to the transalation file
# `delim` is the symbol used to seperate the values

# Our list of locales, used for automatic delimiter detection
var localeScript = load("res://ZKYLoader/Locales.gd").new()
func addTranslationsFromCSV(path:String, delim:String = ""):
	var modFolder := path.get_slice("/", 2)
	d("Adding translations from: %s" % path, modFolder)
	var tlFile:File = File.new()
# Trey to open the file
	if tlFile.open(path, File.READ) != OK:
		e("Could not open file: %s" % path)
		return

# Automatic delimiter detection
	if not delim:
		d("No delimiter given, attempting automatic detection")
		var line := tlFile.get_line()
		for i in range(2, 8):
			var locale = line.right(line.length()-i)
			if locale in localeScript.LOCALES:
				delim = line[line.length()-i-1]
				break
		if delim:
			d("Delimiter detected as: %s" % delim)
		else:
			w("Unable to determine delimiter for file: %s" % path)
			return
		tlFile.seek(0)

	var translations := []
# Scan the first line for locales
	var csvLine := tlFile.get_line().split(delim)
	d("Adding translations as: %s" % csvLine, modFolder)
	for i in range(1, csvLine.size()):
		var translationObject := Translation.new()
		translationObject.locale = csvLine[i]
		translations.append(translationObject)

# Get line as csv translations
	while not tlFile.eof_reached():
		csvLine = tlFile.get_csv_line(delim)
		if csvLine.size() > 1:
			var translationID := csvLine[0]
			for i in range(1, csvLine.size()):
				translations[i - 1].add_message(translationID, csvLine[i].c_unescape())
			d(str(csvLine), modFolder)

	tlFile.close()
# Add the translations to the game
	for translationObject in translations:
		TranslationServer.add_translation(translationObject)

# Name for legacy modloader fucntion
func installScriptExtension(childScriptPath:String):
	extendScript(childScriptPath)

# Helper function to extend scripts
# Loads the script you pass, checks what script is extended, and overrides it
func extendScript(newPath:String, oldPath:String = ""):
	var modFolder := newPath.get_slice("/", 2)
	var childScript:Script = ResourceLoader.load(newPath)

	if not oldPath:
		oldPath = childScript.get_base_script().resource_path

	if oldPath:
		d("Installing script extension: %s <- %s" % [oldPath, newPath], modFolder)
		childScript.new()
		childScript.take_over_path(oldPath)
	else:
		w("No parent script found for: %s" % newPath)

# Helper function to replace scenes
# Can either be passed a single path, or two paths
# With a single path, it will replace the vanilla scene in the same relative position
func replaceScene(newPath:String, oldPath:String = ""):
	var modFolder := newPath.get_slice("/", 2)
	d("Updating scene: %s" % newPath, modFolder)

	if not oldPath:
		oldPath = newPath.replace(modFolder + "/", "")

	if ResourceLoader.exists(oldPath):
		var scene := load(newPath)
		scene.take_over_path(oldPath)
		_savedObjects.append(scene)
		d("Finished updating: %s" % oldPath, modFolder)
	else:
		w("No scene found at: %s" % oldPath)

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
	if consoleLogs or debugMode: print(text)
	Debug.l(text)

# Func to print debug information
func d(msg:String, title:String = MOD_NAME):
	if debugMode:
		var text := "[%s]: %s" % [title, msg]
		print(text)
		Debug.l(text)

# Func to print warnings
func w(msg:String, title:String = MOD_NAME):
	var text := "[%s]: %s" % [title, msg]
	push_warning(text)
	Debug.l("WARNING: " + text)

# Func to print errors
func e(msg:String, title:String = MOD_NAME):
	var text := "[%s]: %s" % [title, msg]
	push_error(text)
	Debug.l("ERROR: " + text)









# Unused
func allFilesIn(scan_dir : String, filter_exts : Array = []) -> Array:
	var files := []
	var dir := Directory.new()
	if dir.open(scan_dir) != OK:
		e("Could not open directory: %s" % scan_dir)
		return []

	if dir.list_dir_begin(true, true) != OK:
		e("Could not list contents of: %s" % scan_dir)
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
