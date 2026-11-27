class_name DoorInteractionProvider
extends RefCounted

## Provedor de interação para portas de interior.
##
## A porta é identificada em **espaço métrico** pelo `InteriorManager`, então a
## distância mostrada na tela é a distância geográfica real, não a diferença de
## posição local — que muda de escala quando o floating origin faz um rebase.

const PRIORITY := 6.0

var interior_manager: InteriorManager = null
var floating: FloatingOrigin = null
var radius: float = 4.5


func _init(manager: InteriorManager = null, origin: FloatingOrigin = null, interaction_radius: float = 4.5) -> void:
	interior_manager = manager
	floating = origin
	radius = interaction_radius


func candidates(player: Node3D) -> Array:
	if interior_manager == null or floating == null or player == null:
		return []

	if interior_manager.is_inside():
		return [{
			"id": "exit",
			"kind": "interior_exit",
			"label": "Sair do apartamento",
			"verb": "E",
			"distance": 0.0,
			"priority": PRIORITY + 5.0,
			"target": Callable(interior_manager, "exit"),
		}]

	var metric := floating.local_to_metric(player.position)
	var door := interior_manager.find_nearby_door(metric, radius)
	if door.is_empty():
		return []
	var door_metric: Vector2 = door.get("metric", metric)
	return [{
		"id": str(door.get("building_id", "door")),
		"kind": "door",
		"label": "Entrar",
		"verb": "E",
		"distance": door_metric.distance_to(metric),
		"priority": PRIORITY,
		"target": Callable(interior_manager, "enter").bind(door),
	}]
