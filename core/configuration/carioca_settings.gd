class_name CariocaSettings
extends RefCounted

## Configurações globais do CARIOCA.
##
## Sem autoload de propósito: a instância é criada sob demanda. Assim as
## ferramentas de linha de comando e os testes headless rodam sem árvore de
## cena e sem depender de ordem de inicialização.

const SETTINGS_PATH := "user://settings.cfg"
const PRESETS: Array[String] = ["mobile", "pc_medium", "pc_high"]

static var _instance: CariocaSettings = null

var quality_preset: String = "pc_medium"
var master_volume: float = 0.75
var ambience_enabled: bool = true
var mouse_sensitivity: float = 0.0022
var world_seed: int = 20170
var show_debug_hud: bool = true
var fov: float = 75.0
var start_municipality: String = "GUAPI"

## Câmera e toque (Etapa 4). Ficam junto do resto porque é o jogador que muda
## isso, e a mudança precisa sobreviver ao reinício.
var camera_distance: float = 4.4
var touch_sensitivity: float = 0.0038
var camera_invert_y: bool = false
var touch_controls_scale: float = 1.0

## Remapeamento de teclas: ação -> código de tecla. Vazio = padrão do projeto.
var input_remaps: Dictionary = {}


static func get_instance() -> CariocaSettings:
	if _instance == null:
		_instance = CariocaSettings.new()
		_instance.load_from_disk()
	return _instance


## Usado pelos testes para começar de um estado conhecido.
static func reset_for_tests() -> CariocaSettings:
	_instance = CariocaSettings.new()
	return _instance


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	quality_preset = str(cfg.get_value("video", "quality_preset", quality_preset))
	fov = float(cfg.get_value("video", "fov", fov))
	master_volume = float(cfg.get_value("audio", "master_volume", master_volume))
	ambience_enabled = bool(cfg.get_value("audio", "ambience_enabled", ambience_enabled))
	mouse_sensitivity = float(cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity))
	touch_sensitivity = float(cfg.get_value("input", "touch_sensitivity", touch_sensitivity))
	camera_distance = float(cfg.get_value("video", "camera_distance", camera_distance))
	camera_invert_y = bool(cfg.get_value("video", "camera_invert_y", camera_invert_y))
	touch_controls_scale = clampf(float(cfg.get_value("video", "touch_scale", touch_controls_scale)), 0.7, 1.6)
	var stored_remaps: Variant = cfg.get_value("input", "remaps", {})
	if typeof(stored_remaps) == TYPE_DICTIONARY:
		input_remaps = (stored_remaps as Dictionary).duplicate()
	world_seed = int(cfg.get_value("world", "seed", world_seed))
	start_municipality = str(cfg.get_value("world", "start_municipality", start_municipality))
	show_debug_hud = bool(cfg.get_value("debug", "show_debug_hud", show_debug_hud))
	if not PRESETS.has(quality_preset):
		quality_preset = "pc_medium"


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "quality_preset", quality_preset)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "ambience_enabled", ambience_enabled)
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("input", "touch_sensitivity", touch_sensitivity)
	cfg.set_value("input", "remaps", input_remaps)
	cfg.set_value("video", "camera_distance", camera_distance)
	cfg.set_value("video", "camera_invert_y", camera_invert_y)
	cfg.set_value("video", "touch_scale", touch_controls_scale)
	cfg.set_value("world", "seed", world_seed)
	cfg.set_value("world", "start_municipality", start_municipality)
	cfg.set_value("debug", "show_debug_hud", show_debug_hud)
	cfg.save(SETTINGS_PATH)


func set_quality_preset(preset_name: String) -> void:
	if PRESETS.has(preset_name):
		quality_preset = preset_name
		save_to_disk()
