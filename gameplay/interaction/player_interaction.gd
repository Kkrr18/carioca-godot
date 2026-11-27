class_name PlayerInteraction
extends RefCounted

## Interação com o mundo, extensível por provedores.
##
## O problema da Etapa 1 era o oposto de um sistema: `Player.try_interact()`
## conhecia `VehicleManager`, `InteriorManager` e o formato de retorno de
## `find_nearby_door`. Cada sistema novo (porta, objeto, NPC de missão) obrigava a
## editar o jogador, e o HUD reimplementava a mesma cadeia de decisão para saber
## que texto mostrar — duas cópias que podiam discordar.
##
## Aqui a decisão fica num lugar só:
##
##   provedor  ->  lista de candidatos { id, kind, label, verb, distance, priority }
##   interação ->  ordena, escolhe o melhor, publica o rótulo, executa
##
## Quem quiser acrescentar um tipo de interação registra um provedor. O jogador,
## o HUD e os testes leem o mesmo resultado.
##
## Ordem de escolha: **prioridade primeiro, distância depois**. Um veículo a 3 m
## não perde a vez para uma porta a 1 m se a porta declarou prioridade menor —
## é a prioridade que expressa "isto é o que o jogador quer fazer aqui".

signal prompt_changed(text: String)
signal interacted(kind: String, candidate: Dictionary)

var providers: Array = []
var best: Dictionary = {}
var last_prompt: String = ""

var _refresh_timer: float = 0.0
var _refresh_interval: float = 0.1


## Registra um provedor. Qualquer objeto com `candidates(player) -> Array`
## serve: não é preciso herdar de nada.
func add_provider(provider: Variant) -> bool:
	var object := provider as Object
	if object == null:
		return false
	if not object.has_method("candidates"):
		return false
	if providers.has(object):
		return false
	providers.append(object)
	return true


func remove_provider(provider: Variant) -> void:
	providers.erase(provider)


func clear_providers() -> void:
	providers.clear()
	best = {}
	_set_prompt("")


## Reavalia os candidatos. Retorna o melhor (vazio quando não há nada por perto).
##
## Esta é a única função que percorre os provedores; chamar a 10 Hz, e não a
## 60 Hz, é decisão de orçamento: o rótulo na tela não muda mais rápido que isso.
func refresh(player: Node3D, delta: float = -1.0) -> Dictionary:
	if delta >= 0.0:
		_refresh_timer -= delta
		if _refresh_timer > 0.0:
			return best
		_refresh_timer = _refresh_interval
	best = _collect_best(player)
	_set_prompt(_label_of(best))
	return best


## Reavalia agora, ignorando o intervalo. Usado depois de interagir e de
## teleportar, quando a tela não pode esperar 100 ms.
func refresh_now(player: Node3D) -> Dictionary:
	_refresh_timer = _refresh_interval
	best = _collect_best(player)
	_set_prompt(_label_of(best))
	return best


func prompt_text() -> String:
	return last_prompt


func has_target() -> bool:
	return not best.is_empty()


func interact(player: Node3D) -> bool:
	if best.is_empty():
		refresh_now(player)
	if best.is_empty():
		return false
	var candidate := best
	var kind := str(candidate.get("kind", ""))
	var target: Variant = candidate.get("target", null)
	var handled := false
	if target != null and target is Object and (target as Object).has_method("interact"):
		target.call("interact", player)
		handled = true
	elif target is Callable and (target as Callable).is_valid():
		(target as Callable).call(player)
		handled = true
	interacted.emit(kind, candidate)
	refresh_now(player)
	return handled


func _collect_best(player: Node3D) -> Dictionary:
	if player == null:
		return {}
	var best_candidate: Dictionary = {}
	var best_priority := -INF
	var best_distance := INF
	for provider in providers:
		if typeof(provider) != TYPE_OBJECT:
			continue
		if not (provider as Object).has_method("candidates"):
			continue
		var raw: Variant = (provider as Object).call("candidates", player)
		if typeof(raw) != TYPE_ARRAY:
			continue
		for entry in raw:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var candidate: Dictionary = entry
			var distance := float(candidate.get("distance", INF))
			var priority := float(candidate.get("priority", 0.0))
			if priority > best_priority + 0.001:
				best_priority = priority
				best_distance = distance
				best_candidate = candidate
			elif absf(priority - best_priority) <= 0.001 and distance < best_distance:
				best_distance = distance
				best_candidate = candidate
	return best_candidate


static func _label_of(candidate: Dictionary) -> String:
	if candidate.is_empty():
		return ""
	var label := str(candidate.get("label", ""))
	var verb := str(candidate.get("verb", ""))
	if label.is_empty():
		return verb
	if verb.is_empty():
		return label
	return "%s   %s" % [verb, label]


func _set_prompt(text: String) -> void:
	if text == last_prompt:
		return
	last_prompt = text
	prompt_changed.emit(text)


func describe() -> String:
	if best.is_empty():
		return "sem interação ao alcance"
	return "%s (%s) a %.1f m" % [str(best.get("label", "?")), str(best.get("kind", "?")), float(best.get("distance", 0.0))]
