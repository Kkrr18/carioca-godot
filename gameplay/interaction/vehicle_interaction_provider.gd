class_name VehicleInteractionProvider
extends RefCounted

## Provedor de interação para veículos.
##
## Não conhece o `Player`: recebe o nó do jogador, pergunta ao `VehicleManager`
## qual é o carro livre mais próximo e devolve um candidato. Assim a regra
## "dirigir o carro mais perto" deixa de morar dentro do controlador do jogador —
## e o HUD passa a mostrar exatamente o que o E vai fazer.

const PRIORITY := 10.0

var vehicle_manager: VehicleManager = null
var radius: float = 4.5


func _init(manager: VehicleManager = null, interaction_radius: float = 4.5) -> void:
	vehicle_manager = manager
	radius = interaction_radius


func candidates(player: Node3D) -> Array:
	if vehicle_manager == null or player == null:
		return []
	var vehicle := vehicle_manager.nearest(player.global_position, radius)
	if vehicle == null:
		return []
	var distance := vehicle.global_position.distance_to(player.global_position)
	return [{
		"id": str(vehicle.get_instance_id()),
		"kind": "vehicle",
		"label": "Dirigir",
		"verb": "E",
		"distance": distance,
		"priority": PRIORITY,
		# O provedor não executa nada: devolve a ação já ligada ao jogador, para
		# que o `PlayerInteraction` só precise chamá-la.
		"target": Callable(player, "enter_vehicle").bind(vehicle),
	}]
