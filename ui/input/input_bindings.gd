class_name InputBindings
extends RefCounted

## Ações nomeadas e remapeamento.
##
## O projeto da Etapa 1 lia teclas direto (`Input.is_key_pressed(KEY_W)`) e o
## `project.godot` não tem seção `[input]`. Isso funciona, mas fecha duas portas:
## remapear controle e deixar o toque e o teclado falarem a mesma língua.
##
## Aqui as ações passam a ter nome (`carioca_forward`, `carioca_jump`, …) e cada
## uma tem uma **tecla padrão**. A leitura é resiliente por desenho:
##
##   - se a ação estiver registrada no `InputMap` **e** tiver evento, lê-se a ação
##     (o que faz o remapeamento valer);
##   - caso contrário, lê-se a tecla padrão direto.
##
## O segundo caminho não é preguiça: é o que mantém o jogo jogável quando alguém
## esquece de chamar `ensure_registered()` (uma cena de teste, uma ferramenta
## headless) e o que mantém a Etapa 1 funcionando sem depender de ordem de boot.

const ACTION_FORWARD := "carioca_forward"
const ACTION_BACK := "carioca_back"
const ACTION_LEFT := "carioca_left"
const ACTION_RIGHT := "carioca_right"
const ACTION_SPRINT := "carioca_sprint"
const ACTION_WALK := "carioca_walk"
const ACTION_JUMP := "carioca_jump"
const ACTION_INTERACT := "carioca_interact"
const ACTION_CAMERA_RESET := "carioca_camera_reset"
const ACTION_ZOOM_IN := "carioca_zoom_in"
const ACTION_ZOOM_OUT := "carioca_zoom_out"
## Etapa 5 — veículo. O espaço é freio de mão no carro e pulo a pé: ações
## distintas com a mesma tecla padrão é o que mantém os contextos separados.
const ACTION_HANDBRAKE := "carioca_handbrake"
const ACTION_HORN := "carioca_horn"
const ACTION_CAMERA_MODE := "carioca_camera_mode"

const ACTIONS: Array[String] = [
	ACTION_FORWARD,
	ACTION_BACK,
	ACTION_LEFT,
	ACTION_RIGHT,
	ACTION_SPRINT,
	ACTION_WALK,
	ACTION_JUMP,
	ACTION_INTERACT,
	ACTION_CAMERA_RESET,
	ACTION_ZOOM_IN,
	ACTION_ZOOM_OUT,
	ACTION_HANDBRAKE,
	ACTION_HORN,
	ACTION_CAMERA_MODE,
]

## Teclas padrão por ação. Valores múltiplos significam "qualquer uma vale".
const DEFAULTS := {
	ACTION_FORWARD: [KEY_W, KEY_UP],
	ACTION_BACK: [KEY_S, KEY_DOWN],
	ACTION_LEFT: [KEY_A, KEY_LEFT],
	ACTION_RIGHT: [KEY_D, KEY_RIGHT],
	ACTION_SPRINT: [KEY_SHIFT],
	ACTION_WALK: [KEY_CTRL],
	ACTION_JUMP: [KEY_SPACE],
	ACTION_INTERACT: [KEY_E],
	ACTION_CAMERA_RESET: [KEY_C],
	ACTION_ZOOM_IN: [KEY_EQUAL, KEY_KP_ADD],
	ACTION_ZOOM_OUT: [KEY_MINUS, KEY_KP_SUBTRACT],
	ACTION_HANDBRAKE: [KEY_SPACE],
	ACTION_HORN: [KEY_H],
	ACTION_CAMERA_MODE: [KEY_V],
}

const LABELS := {
	ACTION_FORWARD: "frente",
	ACTION_BACK: "trás",
	ACTION_LEFT: "esquerda",
	ACTION_RIGHT: "direita",
	ACTION_SPRINT: "sprint",
	ACTION_WALK: "caminhada",
	ACTION_JUMP: "pulo",
	ACTION_INTERACT: "interagir",
	ACTION_CAMERA_RESET: "recentralizar câmera",
	ACTION_ZOOM_IN: "aproximar",
	ACTION_ZOOM_OUT: "afastar",
	ACTION_HANDBRAKE: "freio de mão",
	ACTION_HORN: "buzina",
	ACTION_CAMERA_MODE: "câmera do carro",
}

static var _registered: bool = false
static var _remaps: Dictionary = {}


## Cria as ações no `InputMap` com as teclas padrão. Idempotente: chamar duas
## vezes não duplica evento nenhum.
static func ensure_registered() -> void:
	if _registered:
		return
	_registered = true
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		_rebuild_events(action)


## Remapeia uma ação para uma tecla única. Devolve falso para ação desconhecida
## ou tecla inválida.
static func set_remap(action: String, keycode: int) -> bool:
	if not ACTIONS.has(action):
		return false
	if keycode == 0:
		return false
	_remaps[action] = keycode
	if _registered:
		_rebuild_events(action)
	return true


static func clear_remap(action: String) -> void:
	_remaps.erase(action)
	if _registered:
		_rebuild_events(action)


static func reset_remaps() -> void:
	_remaps.clear()
	if _registered:
		for action in ACTIONS:
			_rebuild_events(action)


static func remaps() -> Dictionary:
	return _remaps.duplicate()


static func apply_remaps(values: Dictionary) -> void:
	for key in values.keys():
		var action := str(key)
		if not ACTIONS.has(action):
			continue
		var keycode := int(values[key])
		if keycode <= 0:
			_remaps.erase(action)
			continue
		_remaps[action] = keycode
	if _registered:
		for action in ACTIONS:
			_rebuild_events(action)


## Teclas válidas para a ação, considerando remapeamento.
static func keys_for(action: String) -> Array:
	if _remaps.has(action):
		return [int(_remaps[action])]
	return (DEFAULTS.get(action, []) as Array).duplicate()


static func primary_key(action: String) -> int:
	var keys := keys_for(action)
	return int(keys[0]) if not keys.is_empty() else 0


static func is_pressed(action: String) -> bool:
	if _registered and InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty():
		if Input.is_action_pressed(action):
			return true
		# Um remapeamento pode ter deixado a ação sem evento útil para o layout
		# de teclado atual; a tecla padrão continua valendo como rede.
	for key in keys_for(action):
		if Input.is_key_pressed(int(key)):
			return true
	return false


## Vetor de movimento no plano, com y = frente. Mesma convenção da Etapa 1:
## `input.y` positivo é para frente, `input.x` positivo é para a direita.
static func move_axis() -> Vector2:
	var axis := Vector2.ZERO
	if is_pressed(ACTION_FORWARD):
		axis.y += 1.0
	if is_pressed(ACTION_BACK):
		axis.y -= 1.0
	if is_pressed(ACTION_RIGHT):
		axis.x += 1.0
	if is_pressed(ACTION_LEFT):
		axis.x -= 1.0
	if axis.length() > 1.0:
		axis = axis.normalized()
	return axis


static func is_registered() -> bool:
	return _registered


static func reset_for_tests() -> void:
	_registered = false
	_remaps.clear()
	for action in ACTIONS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)


static func describe() -> String:
	var parts := PackedStringArray()
	for action in ACTIONS:
		var key := primary_key(action)
		var key_name := OS.get_keycode_string(key) if key != 0 else "—"
		parts.append("%s=%s" % [str(LABELS.get(action, action)), key_name])
	return " · ".join(parts)


static func _rebuild_events(action: String) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	for key in keys_for(action):
		var event := InputEventKey.new()
		event.keycode = int(key)
		event.physical_keycode = int(key)
		InputMap.action_add_event(action, event)
