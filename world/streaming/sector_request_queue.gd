class_name SectorRequestQueue
extends RefCounted

## Fila de carga de setores com prioridade espacial e direcional.
##
## A prioridade não é "mais perto primeiro" puro. Quando o jogador se move — e
## principalmente a 60 km/h — o setor que importa é o que ele vai **atravessar**,
## não o que está ao lado. A pontuação é:
##
##     score = distância - ganho × alinhamento × distância
##
## com `alinhamento` em [-1, 1] contra a direção de movimento. À frente, o setor
## é servido como se estivesse mais perto; atrás, como se estivesse mais longe.
## `ganho` vem do perfil de qualidade e cresce com a velocidade, então a pé a
## fila é puramente radial e de carro ela se inclina para frente.
##
## A fila guarda apenas coordenadas: nenhum payload, nenhuma malha, nenhuma
## referência a nó. Por isso ela é barata de reconstruir quando o jogador muda de
## célula e trivial de testar.

const SENTINEL := Vector2i(2147483000, 2147483000)

var _items: Array[Vector2i] = []
var _queued: Dictionary = {}
var _center := Vector2i.ZERO
var _forward := Vector2.ZERO
var _gain: float = 0.0


## Troca o conteúdo inteiro da fila. Deduplica: a mesma coordenada nunca entra
## duas vezes, que é a primeira defesa contra carregar um setor em dobro.
func refill(coords: Array, center: Vector2i, forward: Vector2, gain: float) -> void:
	_items.clear()
	_queued.clear()
	_center = center
	_forward = forward
	_gain = clampf(gain, 0.0, 0.95)
	for coord in coords:
		if coord == SENTINEL:
			continue
		if _queued.has(coord):
			continue
		_queued[coord] = true
		_items.append(coord)


func size() -> int:
	return _items.size()


func is_empty() -> bool:
	return _items.is_empty()


func has(coord: Vector2i) -> bool:
	return _queued.has(coord)


func remove(coord: Vector2i) -> void:
	if not _queued.has(coord):
		return
	_queued.erase(coord)
	_items.erase(coord)


func clear() -> void:
	_items.clear()
	_queued.clear()


func push_back(coord: Vector2i) -> void:
	if _queued.has(coord):
		return
	_queued[coord] = true
	_items.append(coord)


## Retira a coordenada de maior prioridade (menor pontuação).
func pop() -> Vector2i:
	if _items.is_empty():
		return SENTINEL
	var best_index := 0
	var best_score := INF
	for i in range(_items.size()):
		var score := priority(_items[i])
		if score < best_score:
			best_score = score
			best_index = i
	var coord := _items[best_index]
	_items.remove_at(best_index)
	_queued.erase(coord)
	return coord


## Pontuação pública para o teste poder afirmar o comportamento em vez de
## depender da ordem interna.
func priority(coord: Vector2i) -> float:
	var dx := float(coord.x - _center.x)
	var dy := float(coord.y - _center.y)
	var distance := sqrt(dx * dx + dy * dy)
	if distance < 0.0001:
		return 0.0
	if _gain <= 0.0 or _forward == Vector2.ZERO:
		return distance
	var alignment := (dx * _forward.x + dy * _forward.y) / distance
	return distance * (1.0 - clampf(alignment, -1.0, 1.0) * _gain)


func snapshot() -> Array[Vector2i]:
	return _items.duplicate()


func center() -> Vector2i:
	return _center


func forward() -> Vector2:
	return _forward
