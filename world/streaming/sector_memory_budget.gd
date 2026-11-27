class_name SectorMemoryBudget
extends RefCounted

## Contabilidade e despejo de setores carregados.
##
## O raio de visão já limita quantos setores existem, mas ele não limita
## **bytes**: um setor urbano denso custa várias vezes um setor rural, e o
## sprite do problema em celular é justamente o pico, não a média. Este objeto
## mantém a soma e decide quem sai quando o teto estoura.
##
## A vítima é sempre o setor mais distante do jogador, com uma exceção: nada
## dentro de `min_distance` blocos é despejado, nem sob pressão. Perder o chão
## sob os pés para ficar dentro do orçamento seria um remédio pior que a doença.

var limit_kb: float = 96000.0

var _kb: Dictionary = {}


func register(coord: Vector2i, value_kb: float) -> void:
	_kb[coord] = maxf(value_kb, 0.0)


func release(coord: Vector2i) -> void:
	_kb.erase(coord)


func clear() -> void:
	_kb.clear()


func count() -> int:
	return _kb.size()


func total_kb() -> float:
	var total := 0.0
	for value in _kb.values():
		total += float(value)
	return total


func is_over() -> bool:
	return total_kb() > limit_kb


func kb_of(coord: Vector2i) -> float:
	return float(_kb.get(coord, 0.0))


## Coordenadas a despejar, da mais distante para a mais próxima.
## `force` ignora a checagem de orçamento — usado quando o limite de quantidade
## de setores estourou sem o limite de bytes estourar.
func victims(center: Vector2i, max_count: int, min_distance: float, force: bool = false) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _kb.is_empty() or max_count <= 0:
		return out
	if not force and not is_over():
		return out
	var coords: Array = _kb.keys()
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return SectorGrid.distance_sectors(a, center) > SectorGrid.distance_sectors(b, center))
	for coord in coords:
		if out.size() >= max_count:
			break
		if SectorGrid.distance_sectors(coord, center) <= min_distance:
			continue
		out.append(coord)
	return out
