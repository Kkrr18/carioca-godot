class_name HUD
extends CanvasLayer

## Painel de jogo: diagnóstico, avisos de interação, minimapa e controles de
## toque. Todo o texto é atualizado a 4 Hz — não a 60 — porque String.format e
## reflow de Label custam mais do que o jogo inteiro em um celular.

const REFRESH_INTERVAL := 0.25
const HINT_SECONDS := 10.0

var player: Player = null
var streaming: SectorStreamingManager = null
var floating: FloatingOrigin = null
var terrain: TerrainService = null
var traffic: TrafficManager = null
var pedestrians: PedestrianManager = null
var day_night: DayNightCycle = null
var weather: WeatherManager = null
var vehicle_manager: VehicleManager = null
var interior_manager: InteriorManager = null
var settings: CariocaSettings = null

var touch: TouchControls = null
var minimap: Minimap = null
var debug_label: Label = null
var prompt_label: Label = null
var hint_label: Label = null

var _refresh_timer: float = 0.0
var _hint_timer: float = HINT_SECONDS


func setup(context: Dictionary) -> void:
	player = context.get("player")
	streaming = context.get("streaming")
	floating = context.get("floating")
	terrain = context.get("terrain")
	traffic = context.get("traffic")
	pedestrians = context.get("pedestrians")
	day_night = context.get("day_night")
	weather = context.get("weather")
	vehicle_manager = context.get("vehicle_manager")
	interior_manager = context.get("interior_manager")
	settings = CariocaSettings.get_instance()
	_build()


func _build() -> void:
	debug_label = _make_label(13, Color(0.92, 0.94, 0.97))
	debug_label.anchor_left = 0.0
	debug_label.anchor_right = 0.0
	debug_label.anchor_top = 0.0
	debug_label.anchor_bottom = 0.0
	debug_label.offset_left = 12.0
	debug_label.offset_top = 10.0
	debug_label.offset_right = 620.0
	debug_label.offset_bottom = 330.0
	debug_label.text = ""
	add_child(debug_label)

	prompt_label = _make_label(17, Color(1.0, 0.93, 0.74))
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.anchor_left = 0.0
	prompt_label.anchor_right = 1.0
	prompt_label.anchor_top = 1.0
	prompt_label.anchor_bottom = 1.0
	prompt_label.offset_top = -104.0
	prompt_label.offset_bottom = -72.0
	add_child(prompt_label)

	hint_label = _make_label(14, Color(0.95, 0.96, 0.98))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.anchor_left = 0.0
	hint_label.anchor_right = 1.0
	hint_label.anchor_top = 0.0
	hint_label.anchor_bottom = 0.0
	hint_label.offset_top = 10.0
	hint_label.offset_bottom = 34.0
	hint_label.text = "WASD mover · SHIFT correr · ESPAÇO pular · E interagir · F3 diagnóstico · F5/F9 salvar/carregar · F6 clima · F7 hora · R voltar ao início"
	add_child(hint_label)

	minimap = Minimap.new()
	minimap.name = "Minimap"
	minimap.player = player
	minimap.streaming = streaming
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.anchor_top = 0.0
	minimap.anchor_bottom = 0.0
	minimap.offset_left = -180.0
	minimap.offset_right = -12.0
	minimap.offset_top = 12.0
	minimap.offset_bottom = 180.0
	add_child(minimap)

	touch = TouchControls.new()
	touch.name = "TouchControls"
	touch.visible_controls = PlatformProfile.is_mobile()
	add_child(touch)
	if player != null:
		player.touch_controls = touch


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.65))
	return label


func _process(delta: float) -> void:
	if hint_label != null and _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			hint_label.visible = false
		elif _hint_timer < 2.0:
			hint_label.modulate.a = clampf(_hint_timer / 2.0, 0.0, 1.0)

	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = REFRESH_INTERVAL
	_update_debug()
	_update_prompt()


func toggle_debug() -> void:
	if debug_label != null:
		debug_label.visible = not debug_label.visible


## Mensagem temporária no topo da tela (salvou, carregou, perfil trocado).
func flash(message: String, seconds: float = 3.0) -> void:
	if hint_label == null:
		return
	hint_label.text = message
	hint_label.visible = true
	hint_label.modulate.a = 1.0
	_hint_timer = seconds


func debug_visible() -> bool:
	return debug_label != null and debug_label.visible


func _update_prompt() -> void:
	if prompt_label == null or player == null:
		return
	# A partir da Etapa 4 o jogador publica o que está ao alcance, e o HUD só
	# repete. Sem isso, o HUD mantinha uma segunda cópia da regra de interação —
	# duas cópias que podiam discordar sobre o que o E faz.
	var prompt := ""
	if player.has_method("interaction_prompt"):
		prompt = str(player.interaction_prompt())
	if prompt.is_empty():
		if player.current_vehicle != null:
			prompt = "E   sair do veículo"
		elif interior_manager != null and interior_manager.is_inside():
			prompt = "E   sair do apartamento"
		elif vehicle_manager != null and vehicle_manager.nearest(player.global_position, Player.VEHICLE_RADIUS) != null:
			prompt = "E   dirigir"
		elif interior_manager != null and floating != null:
			var door := interior_manager.find_nearby_door(floating.viewer_metric(), Player.DOOR_RADIUS)
			if not door.is_empty():
				prompt = "E   entrar"
	prompt_label.text = prompt
	if touch != null:
		touch.set_interaction(prompt)


func _update_debug() -> void:
	if debug_label == null or not debug_label.visible:
		return
	if floating == null or player == null:
		return
	var metric := floating.viewer_metric()
	var lat_lon := GeoCoordinateSystem.metric_to_geographic(metric)
	var cell := SectorGrid.sector_of(metric)
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var memory_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)

	var lines: Array[String] = []
	lines.append("FPS %.0f   memória %.0f MB   draw calls %.0f   nós %.0f" % [fps, memory_mb, draws, objects])
	lines.append("LAT %s   LON %s   ALT %.1f m" % [
		_deg(lat_lon.x, "S", "N"),
		_deg(lat_lon.y, "W", "E"),
		terrain.height_at(metric) if terrain != null else 0.0,
	])
	lines.append("SETOR %s" % MunicipalityIndex.id_for(cell))
	lines.append("GRADE %s   tile %s" % [SectorGrid.key(cell), SectorGrid.tile_key(SectorGrid.tile_of_sector(cell))])
	lines.append("setores %d   fila %d   tarefas %d   rebase %d" % [
		streaming.loaded_count() if streaming != null else 0,
		streaming.pending_count() if streaming != null else 0,
		streaming.inflight_count() if streaming != null else 0,
		floating.rebase_count,
	])
	lines.append("última construção %.1f ms   total %d" % [
		float(streaming.last_build_microseconds()) / 1000.0 if streaming != null else 0.0,
		streaming.builds_total() if streaming != null else 0,
	])
	if streaming != null:
		var stats: Dictionary = streaming.stats()
		lines.append("LOD %s   trocas %d   velocidade %.0f m/s" % [
			_lod_spread(stats.get("lod_counts", [])),
			int(stats.get("lod_switches", 0)),
			float(stats.get("speed", 0.0)),
		])
		lines.append("memória %.1f/%.0f MB   cache %d (acertos %d, erros %d)" % [
			float(stats.get("memory_kb", 0.0)) / 1024.0,
			float(stats.get("memory_budget_kb", 0.0)) / 1024.0,
			int(stats.get("cache_entries", 0)),
			int(stats.get("cache_hits", 0)),
			int(stats.get("cache_misses", 0)),
		])
		lines.append("antecipação %d   despejos %d   retentativas %d" % [
			int(stats.get("prefetch", 0)),
			int(stats.get("evictions", 0)),
			int(stats.get("retries", 0)),
		])
	var urban := _urban_line()
	if not urban.is_empty():
		lines.append(urban)
	if day_night != null and weather != null:
		lines.append("tempo %s   clima %s   aderência %.0f%%" % [
			day_night.time_string(),
			weather.label(),
			weather.wetness * 100.0,
		])
	lines.append("trânsito %d   pedestres %d   veículos %d" % [
		traffic.agent_count() if traffic != null else 0,
		pedestrians.agent_count() if pedestrians != null else 0,
		vehicle_manager.count() if vehicle_manager != null else 0,
	])
	if settings != null:
		lines.append("perfil %s" % settings.quality_preset)
	if player != null and player.has_method("describe"):
		var camera_text := "—"
		if player.camera_rig != null:
			camera_text = player.camera_rig.describe()
		lines.append("personagem %s   câmera %s" % [str(player.describe()), camera_text])
	debug_label.text = "\n".join(lines)


## Quadras, lotes e edificações dos setores carregados. Soma feita a 4 Hz sobre
## os setores vivos — é o número que mostra a camada urbana funcionando junto
## com o streaming: se o total cai ao andar, o descarregamento está certo.
func _urban_line() -> String:
	if streaming == null:
		return ""
	var buildings := 0
	var blocks := 0
	var parcels := 0
	var urban_sectors := 0
	for coord in streaming.loaded_coords():
		var instance: SectorInstance = streaming.loaded_sector(coord)
		if instance == null:
			continue
		buildings += instance.urban_buildings()
		blocks += instance.urban_blocks()
		parcels += instance.urban_parcels()
		if instance.is_urban_layer():
			urban_sectors += 1
	if urban_sectors == 0:
		return ""
	return "urbano %d setores   quadras %d   lotes %d   prédios %d" % [
		urban_sectors,
		blocks,
		parcels,
		buildings,
	]


func _deg(value: float, negative_suffix: String, positive_suffix: String) -> String:
	var suffix := negative_suffix if value < 0.0 else positive_suffix
	return "%.6f%s" % [absf(value), suffix]


## Distribuição de setores por nível de detalhe: "4/8/5/0" = quatro no nível 0,
## oito no 1, e assim por diante. É o número que mostra o LOD funcionando.
func _lod_spread(counts: Variant) -> String:
	if typeof(counts) != TYPE_ARRAY:
		return "-"
	var parts: PackedStringArray = PackedStringArray()
	for value in counts:
		parts.append(str(int(value)))
	return "/".join(parts) if not parts.is_empty() else "-"
