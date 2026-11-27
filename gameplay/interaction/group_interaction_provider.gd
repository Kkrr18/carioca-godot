class_name GroupInteractionProvider
extends RefCounted

## Provedor genérico: qualquer nó no grupo `interactable` vira candidato.
##
## É o ponto de extensão para o que ainda não existe — porta de casa, objeto de
## missão, NPC de diálogo, caixa eletrônico. Em vez de o jogador ganhar mais um
## `if` por tipo novo, o objeto entra no grupo e implementa o que quiser:
##
##   func interaction_label() -> String        rótulo (padrão: "Interagir")
##   func interaction_priority() -> float      prioridade (padrão: 4)
##   func interaction_radius() -> float        alcance (padrão: 3,5 m)
##   func interact(player: Node3D) -> void     ação
##
## Sem `interact`, o objeto aparece na tela e não faz nada — o que é melhor do
## que sumir silenciosamente do alcance.
##
## A varredura usa o grupo da árvore, não consulta de física: são poucos nós, e
## uma consulta de forma por frame custaria mais do que o problema que resolve.

const GROUP := "interactable"
const DEFAULT_RADIUS := 3.5
const DEFAULT_PRIORITY := 4.0
const DEFAULT_LABEL := "Interagir"

var radius: float = DEFAULT_RADIUS


func candidates(player: Node3D) -> Array:
	if player == null or not player.is_inside_tree():
		return []
	var out: Array = []
	for node in player.get_tree().get_nodes_in_group(GROUP):
		var target := node as Node3D
		if target == null or not is_instance_valid(target):
			continue
		if target == player:
			continue
		var reach := radius
		if target.has_method("interaction_radius"):
			reach = float(target.call("interaction_radius"))
		var distance := target.global_position.distance_to(player.global_position)
		if distance > reach:
			continue
		var label := DEFAULT_LABEL
		if target.has_method("interaction_label"):
			label = str(target.call("interaction_label"))
		var priority := DEFAULT_PRIORITY
		if target.has_method("interaction_priority"):
			priority = float(target.call("interaction_priority"))
		var action: Variant = null
		if target.has_method("interact"):
			action = Callable(target, "interact").bind(player)
		out.append({
			"id": str(target.name),
			"kind": "object",
			"label": label,
			"verb": "E",
			"distance": distance,
			"priority": priority,
			"target": action,
		})
	return out
