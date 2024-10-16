extends Node

# Set mod priority if you want it to load before/after other mods
# Mods are loaded from lowest to highest priority, default is 0
const MOD_PRIORITY = 0
# Name of the mod, used for writing to the logs
const MOD_NAME = "Example Mod"
# Path of the mod folder, automatically generated on runtime
var modPath:String = get_script().resource_path.get_base_dir() + "/"
# Reference to our modloader, assigned automatically on runtime
# Without this, your only link to the modloader is through _init(ModLoader):
# MUST BE EXACTLY 'var modLoader = false'!!!!!
var modLoader = false

# Initialize the mod
# This function is executed before the majority of the game is loaded
# Only the Tool and Debug AutoLoads are available
# Script and scene replacements should be done here, before the originals are loaded
func _init(modLoader):
	l("Initializing")
	# Do stuff here
	l("Initialized")

# Do stuff on ready
# At this point all AutoLoads are available and the game is loaded
func _ready():
	l("Readying")
	# Do more stuff here
	l("Ready")

# Call the modLoader's translation function
func addTranslationsFromCSV(path:String, delim := ","):
	modLoader.addTranslationsFromCSV(modPath + path, delim)

# Call the modLoader's scene replacement function
func replaceScene(path:String):
	modLoader.replaceScene(modPath + path)

# Call the modLoader's script extention function
func extendScript(path:String):
	modLoader.extendScript(modPath + path)

# Call the modLoader's log function
func l(text:String):
	modLoader.l(text, MOD_NAME)
