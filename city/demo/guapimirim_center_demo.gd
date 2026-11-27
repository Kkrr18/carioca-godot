extends Node3D

## Demonstração urbana — Centro de Guapimirim.
##
## Cena independente do jogo: monta terreno, streaming e a camada urbana da
## Etapa 3 em volta do centro municipal, com câmera livre e painel de
## diagnóstico. É o caminho mais rápido para olhar a cidade: quadras, lotes,
## fachada por pavimento, telhado, calçada, semáforo e vegetação.
##
## Rodar:
##   godot --path . city/demo/guapimirim_center_demo.tscn
##
## Teclas:
##   WASD/setas  mover        Q/E  descer/subir     SHIFT  rápido
##   F1  perfil gráfico       F2   piloto automático (volta em círculo)
##   F3  desenhar quadras e lotes sobre a cidade
##   F4  regenerar os setores em volta (sem sair da cena)
##   F5  ligar/desligar atraso de carga (ver o streaming preencher o miolo)
##   R   voltar ao centro     ESC  soltar o mouse
##
## O desenho de quadras e lotes usa `ImmediateMesh` a partir do **próprio
## payload** de cada setor carregado — é o mesmo dado que gerou os prédios, e
## não uma reconstrução paralela que poderia divergir dele.

const WALK_SPEED := 55.0
const FAST_SPEED := 260.0
const AUTO_SPEED := 30.0
const CAMERA_HEIGHT := 42.0
const HUD_INTERVAL := 0.25
const OVERLAY_INTERVAL := 0.4

## Deslocamento do piloto automático em relação ao centro: uma volta que passeia
## por quadra residencial, eixo arterial e área de referência.
const AUTO_RADIUS := 340.0

var terrain: TerrainService = null
var floating: FloatingOrigin = null
var world_root: Node3D = null
var actor_root: Node3D = null
var flyer: Node3D = null
var camera: Camera3D = null
var streaming: SectorStreamingManager = null
var label: Label = null
var sun: DirectionalLight3D = null
var overlay: MeshInstance3D = null

var start_metric := Vector2.ZERO
var preset := "pc_medium"

var _yaw := 0.0
var _pitch := -0.34
var _auto := false
var _auto_time := 0.0
var _hud_timer := 0.0
var _overlay_timer := 0.0
var _show_overlay := false


func _ready() -> void:
	MunicipalityIndex.ensure_loaded()
	start_metric = MunicipalityIndex.center_of("GUAPI")
	terrain = TerrainService.new(CariocaSettings.get_instance().world_seed)

	_build_environment()
	_build_roots()
	_build_flyer()
	_build_streaming()
	_build_overlay()
	_build_ui()
	_apply_preset(PlatformProfile.recommended_preset())

	if not PlatformProfile.is_mobile():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "Environment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.26, 0.46, 0.82)
	sky_material.sky_horizon_color = Color(0.74, 0.71, 0.62)
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = env
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 420.0
	sun.light_energy = 1.15
	sun.rotation = Vector3(deg_to_rad(-46.0), deg_to_rad(34.0), 0.0)
	add_child(sun)


func _build_roots() -> void:
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)
	actor_root = Node3D.new()
	actor_root.name = "Actors"
	add_child(actor_root)


func _build_flyer() -> void:
	flyer = Node3D.new()
	flyer.name = "Flyer"
	actor_root.add_child(flyer)

	floating = FloatingOrigin.new()
	floating.name = "FloatingOrigin"
	add_child(floating)
	floating.setup(world_root, actor_root, flyer, start_metric)

	flyer.position = Vector3(0.0, terrain.height_at(start_metric) + CAMERA_HEIGHT, 0.0)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.far = 9000.0
	camera.fov = 75.0
	flyer.add_child(camera)
	_update_camera()


func _build_streaming() -> void:
	streaming = SectorStreamingManager.new()
	streaming.name = "SectorStreaming"
	streaming.sector_parent = world_root
	streaming.setup(terrain, floating, flyer)
	add_child(streaming)


func _build_overlay() -> void:
	var mesh := ImmediateMesh.new()
	overlay = MeshInstance3D.new()
	overlay.name = "BlockOverlay"
	overlay.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	overlay.material_override = material
	overlay.visible = false
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(overlay)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)

	label = Label.new()
	label.name = "Stats"
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.94, 0.96, 0.99))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("outline_size", 3)
	label.position = Vector2(12.0, 10.0)
	label.text = "CARIOCA — gerando o Centro de Guapimirim…"
	layer.add_child(label)


func _process(delta: float) -> void:
	_handle_movement(delta)
	_update_camera()

	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = HUD_INTERVAL
		_update_label()

	if _show_overlay:
		_overlay_timer -= delta
		if _overlay_timer <= 0.0:
			_overlay_timer = OVERLAY_INTERVAL
			_draw_overlay()


func _handle_movement(delta: float) -> void:
	if _auto:
		_auto_time += delta
		_yaw = _auto_time * 0.1
		var heading := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		flyer.position += heading * AUTO_SPEED * delta
		_keep_above_ground()
		return

	var direction := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		direction.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		direction.z += 1.0
	if Input.is_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		direction.x += 1.0

	var vertical := 0.0
	if Input.is_key_pressed(KEY_E):
		vertical += 1.0
	if Input.is_key_pressed(KEY_Q):
		vertical -= 1.0

	if direction == Vector3.ZERO and vertical == 0.0:
		return
	var speed := FAST_SPEED if Input.is_key_pressed(KEY_SHIFT) else WALK_SPEED
	if direction != Vector3.ZERO:
		direction = direction.rotated(Vector3.UP, _yaw).normalized()
	flyer.position += direction * speed * delta
	flyer.position += Vector3.UP * vertical * speed * 0.6 * delta
	_keep_above_ground()


func _keep_above_ground() -> void:
	var metric := floating.local_to_metric(flyer.position)
	var ground := terrain.height_at(metric)
	if flyer.position.y < ground + 4.0:
		flyer.position.y = ground + 4.0


func _update_camera() -> void:
	if camera != null:
		camera.rotation = Vector3(_pitch, _yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * 0.0025
		_pitch = clampf(_pitch - motion.relative.y * 0.0025, -1.45, 1.45)
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_F1:
			_cycle_preset()
		KEY_F2:
			_auto = not _auto
			_auto_time = 0.0
		KEY_F3:
			_show_overlay = not _show_overlay
			overlay.visible = _show_overlay
			if _show_overlay:
				_overlay_timer = 0.0
		KEY_F4:
			_regenerate()
		KEY_F5:
			streaming.enabled = not streaming.enabled
		KEY_R:
			_respawn()
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _cycle_preset() -> void:
	var presets := QualityProfile.names()
	var index := presets.find(preset)
	_apply_preset(presets[(index + 1) % presets.size()])


func _apply_preset(name: String) -> void:
	preset = name
	if streaming != null:
		streaming.configure_quality(QualityProfile.get_preset(name))
	if camera != null:
		camera.fov = float(QualityProfile.get_preset(name)["far_fov"])


func _respawn() -> void:
	floating.origin_metric = start_metric
	flyer.position = Vector3(0.0, terrain.height_at(start_metric) + CAMERA_HEIGHT, 0.0)
	_auto_time = 0.0
	streaming.rebuild_all()


## Regenera sem sair da cena: limpa o cache de payload e reconstrói o anel em
## volta do observador. É o atalho de iteração — mexeu no gerador, F4.
func _regenerate() -> void:
	streaming.cache.clear()
	streaming.rebuild_all()
	_overlay_timer = 0.0


# --- desenho de quadras e lotes ----------------------------------------------


func _draw_overlay() -> void:
	var mesh := ImmediateMesh.new()
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for coord in streaming.loaded_coords():
		var instance: SectorInstance = streaming.loaded_sector(coord)
		if instance == null:
			continue
		var offset := instance.position
		_draw_polygons(mesh, instance.payload.get("blocks", []), offset, Color(1.0, 0.72, 0.25))
		_draw_polygons(mesh, instance.payload.get("parcels", []), offset, Color(0.45, 0.92, 1.0))
	mesh.surface_end()
	overlay.mesh = mesh


func _draw_polygons(mesh: ImmediateMesh, entries: Array, offset: Vector3, color: Color) -> void:
	for raw in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var poly := PolygonUtils.from_array((raw as Dictionary).get("poly", []))
		var count := poly.size()
		if count < 3:
			continue
		for i in range(count):
			var a := poly[i]
			var b := poly[(i + 1) % count]
			var ya := terrain.height_at(floating.local_to_metric(offset + Vector3(a.x, 0.0, a.y))) + 1.8
			var yb := terrain.height_at(floating.local_to_metric(offset + Vector3(b.x, 0.0, b.y))) + 1.8
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(Vector3(offset.x + a.x, ya, offset.z + a.y))
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(Vector3(offset.x + b.x, yb, offset.z + b.y))


# --- painel ------------------------------------------------------------------


func _update_label() -> void:
	if label == null or streaming == null or floating == null:
		return
	var stats := streaming.stats()
	var metric := floating.viewer_metric()
	var lat_lon := GeoCoordinateSystem.metric_to_geographic(metric)
	var cell := SectorGrid.sector_of(metric)

	var buildings := 0
	var blocks := 0
	var parcels := 0
	var trees := 0
	var props := 0
	var urban_sectors := 0
	var sources: Array[String] = []
	for coord in streaming.loaded_coords():
		var instance: SectorInstance = streaming.loaded_sector(coord)
		if instance == null:
			continue
		buildings += instance.urban_buildings()
		blocks += instance.urban_blocks()
		parcels += instance.urban_parcels()
		if instance.is_urban_layer():
			urban_sectors += 1
			trees += (instance.payload.get("vegetation", {}).get("trees", []) as Array).size()
			for key in (instance.payload.get("street_objects", {}) as Dictionary).keys():
				props += ((instance.payload.get("street_objects", {}) as Dictionary)[key] as Array).size()
			var source := str(instance.payload.get("urban_source", ""))
			if not sources.has(source):
				sources.append(source)

	var lines: Array[String] = []
	lines.append("CARIOCA — Etapa 3: geração urbana (Centro de Guapimirim)")
	lines.append("FPS %.0f   perfil %s   velocidade %.0f m/s   %s" % [
		Performance.get_monitor(Performance.TIME_FPS),
		preset,
		float(stats.get("speed", 0.0)),
		"piloto automático" if _auto else "livre",
	])
	lines.append("%s   %s" % [
		GeoCoordinateSystem.format_lat_lon(lat_lon.x, lat_lon.y),
		MunicipalityIndex.id_for(cell),
	])
	lines.append("setores %d (%d urbanos)   fila %d   tarefas %d   LOD %s   fonte: %s" % [
		int(stats.get("loaded", 0)),
		urban_sectors,
		int(stats.get("pending", 0)),
		int(stats.get("inflight", 0)),
		_lod_spread(stats.get("lod_counts", [])),
		", ".join(sources) if not sources.is_empty() else "—",
	])
	lines.append("quadras %d   lotes %d   prédios %d   árvores %d   mobiliário %d" % [
		blocks, parcels, buildings, trees, props,
	])
	lines.append("memória %.1f/%.0f MB   cache %d   última construção %.1f ms" % [
		float(stats.get("memory_kb", 0.0)) / 1024.0,
		float(stats.get("memory_budget_kb", 0.0)) / 1024.0,
		int(stats.get("cache_entries", 0)),
		float(streaming.last_build_microseconds()) / 1000.0,
	])
	lines.append("WASD mover · Q/E altura · SHIFT rápido · F1 perfil · F2 automático · F3 quadras/lotes · F4 regenerar · R voltar")
	label.text = "\n".join(lines)


func _lod_spread(counts: Variant) -> String:
	if typeof(counts) != TYPE_ARRAY:
		return "-"
	var parts := PackedStringArray()
	for value in counts:
		parts.append(str(int(value)))
	return "/".join(parts) if not parts.is_empty() else "-"
