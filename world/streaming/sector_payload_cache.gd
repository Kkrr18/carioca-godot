class_name SectorPayloadCache
extends RefCounted

## Cache LRU de payloads de setor.
##
## Serve a um padrão de movimento específico: ir e voltar. Sem cache, cada
## retorno ao setor anterior refaz a leitura de disco ou a geração procedural
## inteira. Com cache de duas dúzias de entradas, atravessar uma rua e voltar
## custa zero.
##
## Só a thread principal toca neste objeto. Payload gerado em worker thread entra
## aqui pela mão do manager, depois que a tarefa é recolhida — assim não existe
## estrutura compartilhada para protegê-la além do que já existe.
##
## O custo em memória é estimado pelo número de registros do payload, não pelo
## JSON serializado: serializar para medir custaria mais que o próprio cache.

## Estimativa por registro (via, prédio, árvore, poste). É ordem de grandeza, não
## medida fina: existe para o orçamento ter uma unidade, não para prever bytes.
const KB_PER_RECORD := 0.11

var limit_entries: int = 24
var limit_kb: float = 8192.0

var hits: int = 0
var misses: int = 0

var _entries: Dictionary = {}
var _kb: Dictionary = {}
var _recency: Array[Vector2i] = []


## Nome com cuidado: chamar isto de `get` sobrescreve o `Object.get()` nativo
## (getter de propriedade), e o parser do Godot 4.4 não resolve o membro —
## o erro "Could not resolve external class member" cascata pelo grafo de
## classes inteiro e derruba até a suíte de testes. Ficou `get_payload`.
func get_payload(coord: Vector2i) -> Dictionary:
	if not _entries.has(coord):
		misses += 1
		return {}
	hits += 1
	_touch(coord)
	return _entries[coord]


## Consulta sem alterar contadores — diagnóstico e testes de presença.
func peek(coord: Vector2i) -> Dictionary:
	return _entries.get(coord, {})


func put(coord: Vector2i, payload: Dictionary) -> void:
	if payload.is_empty():
		return
	if _entries.has(coord):
		_touch(coord)
		return
	_entries[coord] = payload
	_kb[coord] = estimate_kb(payload)
	_recency.append(coord)
	_trim()


func has(coord: Vector2i) -> bool:
	return _entries.has(coord)


func erase(coord: Vector2i) -> void:
	_entries.erase(coord)
	_kb.erase(coord)
	_recency.erase(coord)


func clear() -> void:
	_entries.clear()
	_kb.clear()
	_recency.clear()


func size() -> int:
	return _entries.size()


func size_kb() -> float:
	var total := 0.0
	for value in _kb.values():
		total += float(value)
	return total


func stats() -> Dictionary:
	return {
		"entries": size(),
		"kb": size_kb(),
		"hits": hits,
		"misses": misses,
		"limit_entries": limit_entries,
	}


func _touch(coord: Vector2i) -> void:
	var index := _recency.find(coord)
	if index >= 0:
		_recency.remove_at(index)
	_recency.append(coord)


func _trim() -> void:
	var max_entries := maxi(limit_entries, 1)
	while _recency.size() > max_entries:
		_drop_oldest()
	while size_kb() > limit_kb and _recency.size() > 1:
		_drop_oldest()


func _drop_oldest() -> void:
	if _recency.is_empty():
		return
	var victim: Vector2i = _recency[0]
	_recency.remove_at(0)
	_entries.erase(victim)
	_kb.erase(victim)


static func estimate_kb(payload: Dictionary) -> float:
	var records := 0
	for key in ["roads", "buildings", "trees", "props", "water"]:
		var value: Variant = payload.get(key, [])
		if typeof(value) == TYPE_ARRAY:
			records += (value as Array).size()
	return 4.0 + float(records) * KB_PER_RECORD
