class_name SectorStreamingManager
extends Node3D

## Carregamento contínuo do mundo.
##
## Cinco decisões que sustentam o alvo de 30 FPS no iPhone 12:
##
## 1. Payload fora da thread principal. A leitura de arquivo e a geração
##    procedural rodam em WorkerThreadPool; a thread principal só recebe um
##    Dictionary pronto.
##
## 2. Construção com orçamento. Criar malha, colisão e MultiMesh custa caro; o
##    manager constrói no máximo N setores por frame e para no orçamento de
##    microssegundos. O mundo aparece progressivamente em vez de travar.
##
## 3. Prioridade na direção do movimento. A fila (`SectorRequestQueue`) empurra
##    para o fim o que está atrás do jogador e antecipa alguns blocos à frente
##    quando a velocidade passa de `PREFETCH_MIN_SPEED` — é o que evita dirigir
##    para dentro de mundo vazio.
##
## 4. Memória com teto próprio. Raio de visão limita quantidade; bytes variam
##    muito entre setor rural e urbano. `SectorMemoryBudget` despeja o mais
##    distante quando o teto estoura.
##
## 5. LOD por distância. O terreno de cada setor troca de resolução conforme a
##    distância, com orçamento próprio de trocas por frame.
##
## Nada aqui é estado global: os setores são filhos da raiz do mundo, e este nó
## apenas os posiciona. É o que permite o FloatingOrigin deslocar tudo sem
## deslocar o manager duas vezes.

signal sector_built(coord: Vector2i)
signal sector_dropped(coord: Vector2i)

const UNLOAD_HYSTERESIS := 1.6
const SENTINEL_CELL := Vector2i(2147483000, 2147483000)

## Abaixo disto a fila é radial; acima, inclina na direção do movimento.
const PREFETCH_MIN_SPEED := 4.0
const PREFETCH_FULL_SPEED := 28.0
const MAX_PREFETCH_CELLS := 5

## Tarefa que não terminou neste tempo é abandonada e vira falha. Sem isto, uma
## tarefa travada segura uma das duas vagas de worker para sempre.
const INFLIGHT_TIMEOUT_MSEC := 20000

## Reavaliar o conjunto desejado quando a direção muda, no máximo com esta
## frequência.
const REFRESH_INTERVAL := 0.6

var terrain: TerrainService = null
var floating: FloatingOrigin = null
var viewer: Node3D = null

## Setores entram como filhos diretos desta raiz, e não deste manager: é a raiz
## que o FloatingOrigin desloca no rebase.
var sector_parent: Node3D = null

var view_radius: int = 3
var max_concurrent_tasks: int = 2
var max_builds_per_frame: int = 1
var build_budget_usec: int = 9000
var divisions: int = 33
var seed_value: int = 20170
var enabled: bool = true

var max_loaded_sectors: int = 41
var max_unloads_per_frame: int = 2
var prefetch_gain: float = 0.6
var cache_limit: int = 24

## Injeção opcional do carregador de payload (callable puro `coord -> Dictionary`).
## Existe para o teste conseguir simular falha de carga; em jogo fica vazio e o
## manager usa `SectorRepository`.
var payload_loader: Callable = Callable()

var lod: SectorLodController = null
var cache: SectorPayloadCache = null
var memory: SectorMemoryBudget = null
var queue: SectorRequestQueue = null
var retry: LoadRetryPolicy = null

var _loaded: Dictionary = {}
var _payloads: Dictionary = {}
var _inflight: Dictionary = {}
var _inflight_since: Dictionary = {}
var _task_failed: Dictionary = {}
var _failures: Dictionary = {}
var _wanted: Dictionary = {}
var _pending_prefetch: Array[Vector2i] = []
var _lod_queue: Array[Vector2i] = []
var _orphan_tasks: Dictionary = {}
var _last_cell := SENTINEL_CELL
var _last_forward := Vector2.ZERO
var _last_viewer_metric := Vector2.ZERO
var _viewer_metric := Vector2.ZERO
var _velocity := Vector2.ZERO
var _has_motion_sample := false
var _refresh_timer := 0.0
var _lock := Mutex.new()
var _builds_total: int = 0
var _last_build_usec: int = 0
var _lod_switches: int = 0
var _evictions: int = 0
var _retries: int = 0
var _load_failures: int = 0


func _init() -> void:
	lod = SectorLodController.new()
	cache = SectorPayloadCache.new()
	memory = SectorMemoryBudget.new()
	queue = SectorRequestQueue.new()
	retry = LoadRetryPolicy.new()
	# Começa no perfil médio; quem monta o jogo aplica o perfil da plataforma em
	# seguida (`configure_quality`). Assim o manager nunca fica sem política.
	configure_defaults(QualityProfile.get_preset("pc_medium"))


## Aplica os valores de um perfil de qualidade sem reconstruir o mundo.
func configure_defaults(preset: Dictionary) -> void:
	divisions = int(preset.get("divisions", divisions))
	max_builds_per_frame = int(preset.get("max_builds_per_frame", max_builds_per_frame))
	build_budget_usec = int(preset.get("build_budget_usec", build_budget_usec))
	max_loaded_sectors = int(preset.get("max_loaded_sectors", max_loaded_sectors))
	prefetch_gain = float(preset.get("prefetch_gain", prefetch_gain))
	if memory != null:
		memory.limit_kb = float(preset.get("memory_budget_kb", memory.limit_kb))
	if cache != null:
		cache.limit_entries = cache_limit
		cache.limit_kb = float(preset.get("payload_cache_kb", cache.limit_kb))
	if lod != null:
		lod.setup(LodProfile.from_preset(preset))
	if retry != null:
		retry.max_attempts = int(preset.get("load_retry_attempts", retry.max_attempts))
	# A geração de payload roda nas threads de trabalho e lê esta configuração:
	# ela é **substituída** por um objeto completo, nunca alterada em campo.
	UrbanConfig.set_active_from_preset(preset)


## Troca o perfil em tempo de execução e recomeça o mundo no lugar. É o caminho
## do F1 no jogo e o que o `QualityProfile` chama.
func configure_quality(preset: Dictionary) -> void:
	configure_defaults(preset)
	set_view_radius(int(preset.get("view_radius", view_radius)))
	rebuild_all()


func setup(sector_terrain: TerrainService, origin: FloatingOrigin, viewer_node: Node3D) -> void:
	terrain = sector_terrain
	floating = origin
	viewer = viewer_node


func set_view_radius(radius: int) -> void:
	var clamped := clampi(radius, 1, 8)
	if clamped == view_radius:
		return
	view_radius = clamped
	_last_cell = SENTINEL_CELL


func loaded_count() -> int:
	return _loaded.size()


func pending_count() -> int:
	return queue.size() if queue != null else 0


func inflight_count() -> int:
	return _inflight.size()


func last_build_microseconds() -> int:
	return _last_build_usec


func builds_total() -> int:
	return _builds_total


func loaded_coords() -> Array:
	return _loaded.keys()


func loaded_sector(coord: Vector2i) -> SectorInstance:
	return _loaded.get(coord)


func loaded_kb() -> float:
	return memory.total_kb() if memory != null else 0.0


## Descarrega tudo e recomeça em volta do jogador. Usado quando o perfil de
## qualidade muda a resolução do terreno ou o raio de visão, e no respawn.
func rebuild_all() -> void:
	# Espera as tarefas em voo antes de limpar: sem isso, uma tarefa antiga
	# escreveria payload de um mundo que já não existe.
	for coord in _inflight.keys():
		WorkerThreadPool.wait_for_task_completion(_inflight[coord])
	for task_id in _orphan_tasks.keys():
		WorkerThreadPool.wait_for_task_completion(task_id)
	_orphan_tasks.clear()
	_inflight.clear()
	_inflight_since.clear()
	_task_failed.clear()

	for coord in _loaded.keys():
		var instance: SectorInstance = _loaded[coord]
		instance.release()
	_loaded.clear()

	_lock.lock()
	_payloads.clear()
	_lock.unlock()

	queue.clear()
	_wanted.clear()
	_pending_prefetch.clear()
	_lod_queue.clear()
	_failures.clear()
	memory.clear()
	cache.clear()
	lod.reset()
	_last_cell = SENTINEL_CELL
	_last_forward = Vector2.ZERO
	_velocity = Vector2.ZERO
	_has_motion_sample = false


func _process(delta: float) -> void:
	tick_for_test(delta)


## Um passo de simulação. Público porque o teste headless não tem laço de frame
## chamando `_process`: ele chama isto em laço e o comportamento fica
## determinístico.
func tick_for_test(delta: float) -> void:
	if not enabled or terrain == null or floating == null or viewer == null:
		return
	_update_motion(delta)
	var metric := _viewer_metric
	var cell := SectorGrid.sector_of(metric)
	var forward := _forward_direction()

	_refresh_timer -= delta
	var turned := forward.dot(_last_forward) < 0.35
	if cell != _last_cell or (turned and _refresh_timer <= 0.0):
		_last_cell = cell
		_last_forward = forward
		_refresh_timer = REFRESH_INTERVAL
		_refresh_wanted(cell, forward)

	_poll_tasks()
	_start_tasks()
	_build_with_budget()
	_update_lod(metric, delta)
	_unload_distant(cell)
	_evict_over_budget(cell)


# --- movimento e direção ----------------------------------------------------


func _update_motion(delta: float) -> void:
	var metric := floating.viewer_metric()
	_viewer_metric = metric
	if _has_motion_sample and delta > 0.0001:
		var instant := (metric - _last_viewer_metric) / delta
		if instant.length() < 400.0:
			# Média exponencial: ruído de um passo não vira direção.
			_velocity = _velocity.lerp(instant, 0.35)
		else:
			# Teleporte (interior, carregar save): não é deslocamento.
			_velocity = Vector2.ZERO
	_last_viewer_metric = metric
	_has_motion_sample = true


func _forward_direction() -> Vector2:
	var speed := _velocity.length()
	if speed < PREFETCH_MIN_SPEED:
		return Vector2.ZERO
	return _velocity / speed


func _prefetch_gain_for_speed() -> float:
	var speed := _velocity.length()
	var span := PREFETCH_FULL_SPEED - PREFETCH_MIN_SPEED
	if span <= 0.0:
		return prefetch_gain
	return prefetch_gain * clampf((speed - PREFETCH_MIN_SPEED) / span, 0.0, 1.0)


func viewer_speed() -> float:
	return _velocity.length()


# --- conjunto desejado -------------------------------------------------------


func _refresh_wanted(cell: Vector2i, forward: Vector2) -> void:
	_wanted.clear()
	_pending_prefetch.clear()
	for coord in SectorGrid.sectors_in_radius(cell, view_radius):
		_wanted[coord] = true

	if forward != Vector2.ZERO:
		for coord in _prefetch_cells(cell, forward):
			if _wanted.has(coord):
				continue
			_wanted[coord] = true
			_pending_prefetch.append(coord)

	# Payload pronto de setor que saiu do raio não pode ocupar memória.
	_lock.lock()
	for coord in _payloads.keys():
		if not _wanted.has(coord):
			_payloads.erase(coord)
	var ready: Array = _payloads.keys()
	_lock.unlock()

	for coord in _failures.keys():
		if not _wanted.has(coord):
			_failures.erase(coord)

	var requests: Array[Vector2i] = []
	for coord in _wanted.keys():
		if _loaded.has(coord) or _inflight.has(coord) or ready.has(coord):
			continue
		var cached := cache.get(coord)
		if not cached.is_empty():
			# Acerto de cache: entra como payload pronto, sem thread nenhuma.
			_lock.lock()
			_payloads[coord] = cached
			_lock.unlock()
			continue
		requests.append(coord)
	queue.refill(requests, cell, forward, _prefetch_gain_for_speed())


## Blocos à frente do movimento, ainda fora do raio. Limitados a
## MAX_PREFETCH_CELLS para a antecipação nunca virar um segundo raio de carga.
func _prefetch_cells(cell: Vector2i, forward: Vector2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var ahead := cell + Vector2i(
		roundi(forward.x * float(view_radius + 1)),
		roundi(forward.y * float(view_radius + 1))
	)
	if ahead == cell:
		return out
	for coord in SectorGrid.sectors_in_radius(ahead, 1):
		if coord == cell:
			continue
		var dx := float(coord.x - cell.x)
		var dy := float(coord.y - cell.y)
		if dx * forward.x + dy * forward.y <= 0.0:
			continue
		out.append(coord)
		if out.size() >= MAX_PREFETCH_CELLS:
			break
	return out


# --- tarefas -----------------------------------------------------------------


func _start_tasks() -> void:
	var now := Time.get_ticks_msec()
	var deferred: Array[Vector2i] = []
	while _inflight.size() < max_concurrent_tasks and not queue.is_empty():
		var coord := queue.pop()
		if coord == SectorRequestQueue.SENTINEL:
			break
		if _loaded.has(coord) or _inflight.has(coord):
			continue
		if not _wanted.has(coord):
			continue
		var failure: Dictionary = _failures.get(coord, {})
		if not failure.is_empty() and int(failure.get("next_at", 0)) > now:
			deferred.append(coord)
			continue
		_inflight[coord] = WorkerThreadPool.add_task(
			_load_task.bind(coord), false, "carioca_sector_%d_%d" % [coord.x, coord.y]
		)
		_inflight_since[coord] = now
	for coord in deferred:
		queue.push_back(coord)


## Executa na thread do worker: só leitura de arquivo, geração pura e escrita
## protegida por mutex. Nunca toca na árvore de cena.
func _load_task(coord: Vector2i) -> void:
	var payload: Dictionary = {}
	if payload_loader.is_valid():
		var raw: Variant = payload_loader.call(coord)
		if typeof(raw) == TYPE_DICTIONARY:
			payload = raw
	else:
		payload = SectorRepository.load_payload(coord, seed_value)

	var valid := not payload.is_empty() and payload.has("grid")
	_lock.lock()
	if valid:
		_payloads[coord] = payload
	else:
		_task_failed[coord] = true
	_lock.unlock()


func _poll_tasks() -> void:
	_reap_orphans()
	if _inflight.is_empty():
		return
	var now := Time.get_ticks_msec()
	for coord in _inflight.keys():
		var task_id: int = _inflight[coord]
		var finished := WorkerThreadPool.is_task_completed(task_id)
		var timed_out := now - int(_inflight_since.get(coord, now)) > INFLIGHT_TIMEOUT_MSEC
		if not finished and not timed_out:
			continue
		if finished:
			WorkerThreadPool.wait_for_task_completion(task_id)
		else:
			# Abandonada agora, recolhida depois: a vaga de worker é liberada já,
			# mas o identificador continua registrado para ser fechado quando a
			# tarefa terminar de verdade. Sem isso o pool acumula descritores.
			_orphan_tasks[task_id] = true
		_inflight.erase(coord)
		_inflight_since.erase(coord)

		# `payload_loader` e `cache` são da thread principal: ler `_payloads`
		# sob o cadeado e agir fora dele.
		_lock.lock()
		var payload: Dictionary = _payloads.get(coord, {})
		var failed := _task_failed.has(coord)
		if failed:
			_task_failed.erase(coord)
		_lock.unlock()

		if payload.is_empty() or failed:
			_register_failure(coord)
			continue
		cache.put(coord, payload)
		_failures.erase(coord)


func _register_failure(coord: Vector2i) -> void:
	_load_failures += 1
	var previous: Dictionary = _failures.get(coord, {})
	var attempts := int(previous.get("attempts", 0)) + 1
	_failures[coord] = {
		"attempts": attempts,
		"next_at": Time.get_ticks_msec() + retry.delay_msec_for(attempts),
	}
	if retry.can_retry(attempts):
		_retries += 1
		queue.push_back(coord)


## Fecha tarefas que foram abandonadas por tempo. `wait_for_task_completion`
## libera o descritor da tarefa no pool, e precisa ser chamado uma vez por
## tarefa adicionada — inclusive pelas que o watchdog desistiu de esperar.
func _reap_orphans() -> void:
	if _orphan_tasks.is_empty():
		return
	for task_id in _orphan_tasks.keys():
		if WorkerThreadPool.is_task_completed(task_id):
			WorkerThreadPool.wait_for_task_completion(task_id)
			_orphan_tasks.erase(task_id)


# --- construção --------------------------------------------------------------


func _build_with_budget() -> void:
	if _payloads.is_empty():
		return
	var started := Time.get_ticks_usec()
	var built := 0
	while built < max_builds_per_frame and (Time.get_ticks_usec() - started) < build_budget_usec:
		var coord := _next_ready_coord()
		if coord == SENTINEL_CELL:
			break
		var payload := _pop_payload(coord)
		if payload.is_empty():
			continue
		if not _wanted.has(coord) or _loaded.has(coord):
			continue
		if not _admit():
			# Sem vaga: o payload fica no cache em vez de ser jogado fora.
			cache.put(coord, payload)
			continue
		var level := _target_lod_for(coord, _viewer_metric)
		var instance := SectorInstance.new()
		instance.position = floating.metric_to_local(SectorGrid.sector_origin(coord))
		_sectors_parent().add_child(instance)
		instance.build(coord, payload, terrain, _divisions_for_level(level), _skirt(), _has_collision(level))
		instance.apply_detail(level)
		lod.register_level(coord, level)
		_loaded[coord] = instance
		memory.register(coord, instance.memory_estimate_kb())
		_builds_total += 1
		_last_build_usec = instance.build_microseconds
		built += 1
		lod.mark_dirty()
		sector_built.emit(coord)
		CariocaBus.get_instance().sector_loaded.emit(coord)
		# Um segundo setor só se ainda houver orçamento depois deste.
		if Time.get_ticks_usec() - started > build_budget_usec:
			break


## Quantidade de setores e bytes. Um setor não entra se estouraria o teto; o
## despejo roda no fim do mesmo frame, então a vaga abre no seguinte.
func _admit() -> bool:
	if _loaded.size() >= max_loaded_sectors:
		return false
	if memory.is_over():
		return false
	return true


func _next_ready_coord() -> Vector2i:
	var best := SENTINEL_CELL
	var best_distance := INF
	var center := _last_cell
	_lock.lock()
	var keys := _payloads.keys()
	_lock.unlock()
	for coord in keys:
		if _loaded.has(coord) or not _wanted.has(coord):
			continue
		var distance := SectorGrid.distance_sectors(coord, center)
		if distance < best_distance:
			best_distance = distance
			best = coord
	return best


func _pop_payload(coord: Vector2i) -> Dictionary:
	_lock.lock()
	var payload: Dictionary = _payloads.get(coord, {})
	_payloads.erase(coord)
	_lock.unlock()
	return payload


# --- LOD ---------------------------------------------------------------------


func _target_lod_for(coord: Vector2i, center_metric: Vector2) -> int:
	if lod == null or lod.profile == null:
		return 0
	return lod.provisional_level(coord, center_metric)


func _divisions_for_level(level: int) -> int:
	if lod == null or lod.profile == null:
		return divisions
	return lod.divisions_for(level)


func _skirt() -> float:
	if lod == null or lod.profile == null:
		return 0.0
	return lod.profile.skirt


func _has_collision(level: int) -> bool:
	if lod == null or lod.profile == null:
		return true
	return lod.profile.has_collision(level)


func _update_lod(metric: Vector2, delta: float) -> void:
	if lod == null or lod.profile == null:
		return
	if not _loaded.is_empty():
		for coord in lod.update(metric, _loaded.keys(), delta):
			if not _lod_queue.has(coord):
				_lod_queue.append(coord)
	if _lod_queue.is_empty():
		return
	var started := Time.get_ticks_usec()
	var applied := 0
	while not _lod_queue.is_empty():
		if applied >= lod.profile.max_switches_per_frame:
			break
		if applied > 0 and Time.get_ticks_usec() - started > lod.profile.switch_budget_usec:
			break
		var coord: Vector2i = _lod_queue[0]
		_lod_queue.remove_at(0)
		var instance: SectorInstance = _loaded.get(coord)
		if instance == null:
			continue
		var level := lod.level_of(coord)
		if instance.set_terrain_lod(_divisions_for_level(level), _has_collision(level), _skirt()):
			_lod_switches += 1
			memory.register(coord, instance.memory_estimate_kb())
		instance.apply_detail(level)
		applied += 1


# --- descarga ----------------------------------------------------------------


func _unload_distant(cell: Vector2i) -> void:
	if _loaded.is_empty():
		return
	var limit := float(view_radius) + UNLOAD_HYSTERESIS
	var dropped := 0
	for coord in _loaded.keys():
		if dropped >= max_unloads_per_frame:
			break
		if SectorGrid.distance_sectors(coord, cell) <= limit:
			continue
		_drop(coord)
		dropped += 1


## Despejo por orçamento: só quando o teto de setores ou de bytes estourou.
func _evict_over_budget(cell: Vector2i) -> void:
	var over_count := _loaded.size() > max_loaded_sectors
	if not over_count and not memory.is_over():
		return
	for coord in memory.victims(cell, max_unloads_per_frame, 1.5, over_count):
		_evictions += 1
		_drop(coord)


func _drop(coord: Vector2i) -> void:
	var instance: SectorInstance = _loaded.get(coord)
	if instance == null:
		memory.release(coord)
		return
	# Guardar o payload é o que torna voltar para trás instantâneo.
	cache.put(coord, instance.payload)
	memory.release(coord)
	lod.forget(coord)
	instance.release()
	_loaded.erase(coord)
	lod.mark_dirty()
	sector_dropped.emit(coord)
	CariocaBus.get_instance().sector_unloaded.emit(coord)


# --- diagnóstico e ferramentas -----------------------------------------------


func stats() -> Dictionary:
	var lod_counts: Array[int] = []
	if lod != null:
		lod_counts = lod.level_counts(_loaded.keys())
	return {
		"loaded": _loaded.size(),
		"pending": pending_count(),
		"inflight": _inflight.size(),
		"prefetch": _pending_prefetch.size(),
		"speed": _velocity.length(),
		"cache_entries": cache.size() if cache != null else 0,
		"cache_hits": cache.hits if cache != null else 0,
		"cache_misses": cache.misses if cache != null else 0,
		"memory_kb": loaded_kb(),
		"memory_budget_kb": memory.limit_kb if memory != null else 0.0,
		"lod_counts": lod_counts,
		"lod_switches": _lod_switches,
		"lod_pending": _lod_queue.size(),
		"evictions": _evictions,
		"retries": _retries,
		"failures": _load_failures,
		"builds": _builds_total,
	}


## Pré-carrega um conjunto de setores sem depender de um jogador (usado pelos
## testes de integração e pela ferramenta de bake para aquecer cache).
func warm_up(cell: Vector2i, count: int) -> int:
	var loaded := 0
	var center := SectorGrid.sector_center(cell)
	for coord in SectorGrid.sectors_in_radius(cell, view_radius):
		if loaded >= count:
			break
		if _loaded.has(coord):
			continue
		var payload := SectorRepository.load_payload(coord, seed_value)
		if payload.is_empty():
			continue
		var level := _target_lod_for(coord, center)
		var instance := SectorInstance.new()
		instance.position = floating.metric_to_local(SectorGrid.sector_origin(coord))
		_sectors_parent().add_child(instance)
		instance.build(coord, payload, terrain, _divisions_for_level(level), _skirt(), _has_collision(level))
		instance.apply_detail(level)
		lod.register_level(coord, level)
		_loaded[coord] = instance
		memory.register(coord, instance.memory_estimate_kb())
		loaded += 1
	return loaded


func _sectors_parent() -> Node3D:
	return sector_parent if sector_parent != null else self
