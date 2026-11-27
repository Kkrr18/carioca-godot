class_name SectorLodController
extends RefCounted

## Decide em que nível de detalhe cada setor carregado deve estar.
##
## Não desenha nada e não toca na árvore de cena: devolve uma lista de coordena-
## das cuja malha precisa ser reconstruída, e o streaming executa com orçamento.
## Essa separação é o que permite testar a política de LOD sem GPU nem frame.
##
## Três regras, nesta ordem:
##
## 1. **Distância até a borda**, não até o centro. Um bloco de 512 m cujo centro
##    está a 700 m pode começar a 450 m do jogador; usar o centro o jogaria para
##    um nível grosseiro e ele "cresceria" na frente da câmera.
##
## 2. **Restrição de vizinhança**: dois setores adjacentes não podem diferir por
##    mais de um nível. Sem isso, a diferença de resolução nas bordas cresce e a
##    saia da malha passa a ser a única coisa segurando a imagem.
##
## 3. **Histerese temporal**: a mudança precisa se sustentar por
##    `switch_delay` segundos. Parado na fronteira de faixa, o setor não fica
##    trocando de nível a cada frame.

const NEIGHBOURS := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

var profile: LodProfile = null

var _levels: Dictionary = {}
var _pending: Dictionary = {}
var _last_center := Vector2(INF, INF)
var _dirty: bool = true
var _evaluations: int = 0
var _committed: int = 0


func setup(new_profile: LodProfile) -> void:
	profile = new_profile
	reset()


func reset() -> void:
	_levels.clear()
	_pending.clear()
	_last_center = Vector2(INF, INF)
	_dirty = true
	_evaluations = 0
	_committed = 0


## O conjunto de setores carregados mudou: reavaliar sem esperar o jogador andar.
func mark_dirty() -> void:
	_dirty = true


func forget(coord: Vector2i) -> void:
	_levels.erase(coord)
	_pending.erase(coord)


func level_of(coord: Vector2i) -> int:
	return int(_levels.get(coord, 0))


func register_level(coord: Vector2i, level: int) -> void:
	if not _levels.has(coord):
		_levels[coord] = clampi(level, 0, profile.level_count() - 1) if profile != null else 0


## Nível que o setor teria hoje só pela distância, sem histerese nem vizinhança.
## Usado no momento da construção, para o setor já nascer no nível certo em vez
## de nascer detalhado e encolher no frame seguinte.
func provisional_level(coord: Vector2i, center_metric: Vector2) -> int:
	if profile == null:
		return 0
	return profile.level_for_distance(SectorGrid.distance_to_sector_m(coord, center_metric))


## Avalia o conjunto carregado e devolve as coordenadas que mudaram de nível
## agora. O chamador aplica o que couber no orçamento do frame.
func update(center_metric: Vector2, coords: Array, delta: float) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	if profile == null or coords.is_empty():
		return changed
	var moved_enough := not _last_center.is_finite() or _last_center.distance_to(center_metric) >= profile.update_distance
	if not (_dirty or moved_enough or not _pending.is_empty()):
		return changed
	_dirty = false
	_last_center = center_metric
	_evaluations += 1

	var targets := {}
	for coord in coords:
		var target := provisional_level(coord, center_metric)
		if not _levels.has(coord):
			_levels[coord] = target
		targets[coord] = target

	_enforce_neighbour_rule(targets)

	for coord in coords:
		if not targets.has(coord):
			continue
		var current := int(_levels.get(coord, 0))
		var target: int = targets[coord]
		if target == current:
			_pending.erase(coord)
			continue
		var entry: Dictionary = _pending.get(coord, {})
		if int(entry.get("level", -1)) != target:
			entry = {"level": target, "time": 0.0}
		entry["time"] = float(entry.get("time", 0.0)) + delta
		if float(entry["time"]) >= profile.switch_delay:
			_levels[coord] = target
			_pending.erase(coord)
			changed.append(coord)
			_committed += 1
		else:
			_pending[coord] = entry
	return changed


## Nenhum par de vizinhos pode diferir por mais de um nível. Os valores só
## diminuem a cada passada, então duas passadas convergem.
func _enforce_neighbour_rule(targets: Dictionary) -> void:
	var ceiling := profile.level_count() - 1
	for _pass in range(2):
		for coord in targets.keys():
			var limit := ceiling
			for dir in NEIGHBOURS:
				var other: Vector2i = coord + dir
				if not targets.has(other):
					continue
				limit = mini(limit, int(targets[other]) + 1)
			targets[coord] = mini(int(targets[coord]), limit)


func level_counts(coords: Array) -> Array[int]:
	var total := profile.level_count() if profile != null else LodProfile.MAX_LEVELS
	var counts: Array[int] = []
	for _i in range(total):
		counts.append(0)
	for coord in coords:
		var level := level_of(coord)
		if level >= 0 and level < counts.size():
			counts[level] += 1
	return counts


func stats() -> Dictionary:
	return {
		"evaluations": _evaluations,
		"committed": _committed,
		"pending": _pending.size(),
		"levels": _levels.size(),
	}
