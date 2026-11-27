extends Node3D

## Demonstração de terreno e streaming.
##
## Cena independente do jogo: monta só o terreno, o streaming e uma câmera
## livre. Serve para olhar o LOD acontecendo, ver o anel de setores carregar e
## despejar, e medir o custo real de atravessar o mundo — sem jogador, sem
## trânsito, sem veículo. O que se vê aqui é a mesma camada que o jogo usa.
##
## Rodar: F6/F5 nesta cena, ou
##   godot --path . world/demo/streaming_demo.tscn

const WALK_SPEED := 45.0
const FAST_SPEED := 240.0
const AUTO_SPEED := 26.0
const CAMERA_HEIGHT := 35.0
const HUD_INTERVAL := 0.25

var terrain: TerrainService = null
var floating: FloatingOrigin = null
var world_root: Node3D = null
var actor_root: Node3D = null
var flyer: Node3D = null
var camera: Camera3D = null
var streaming: SectorStreamingManager = null
var label: Label = null
var sun: DirectionalLight3D = null

var start_metric := Vector2.ZERO
var preset := "pc_medium"

var _yaw := 0.0
var _pitch := -0.22
var _auto := false
var _auto_time := 0.0
var _hud_timer := 0.0


func _ready() -> void:
	MunicipalityIndex.ensure_loaded()
	start_metric = MunicipalityIndex.center_of("GUAPI")
	terrain = TerrainService.new(CariocaSettings.get_instance().world_seed)

	_build_environment()
	_build_roots()
	_build_flyer()
	_build_streaming()
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
	sky_material.sky_horizon_color = Color(0.72, 0.70, 0.62)
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = env
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 320.0
	sun.light_energy = 1.1
	sun.rotation = Vector3(deg_to_rad(-42.0), deg_to_rad(38.0), 0.0)
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
	camera.far = 8000.0
	camera.fov = 75.0
	flyer.add_child(camera)
	_update_camera()


func _build_streaming() -> void:
	streaming = SectorStreamingManager.new()
	streaming.name = "SectorStreaming"
	streaming.sector_parent = world_root
	streaming.setup(terrain, floating, flyer)
	add_child(streaming)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)

	label = Label.new()
	label.name = "Stats"
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.94, 0.96, 0.99))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.75))
	label.add_theme_constant_override("outline_size", 3)
	label.position = Vector2(12.0, 10.0)
	label.text = "CARIOCA — carregando terreno…"
	layer.add_child(label)


func _process(delta: float) -> void:
	_handle_movement(delta)
	_update_camera()
	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = HUD_INTERVAL
		_update_label()


func _handle_movement(delta: float) -> void:
	if _auto:
		_auto_time += delta
		_yaw = _auto_time * 0.12
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
	if flyer.position.y < ground + 3.0:
		flyer.position.y = ground + 3.0


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


func _update_label() -> void:
	if label == null or streaming == null or floating == null:
		return
	var stats := streaming.stats()
	var metric := floating.viewer_metric()
	var lat_lon := GeoCoordinateSystem.metric_to_geographic(metric)
	var cell := SectorGrid.sector_of(metric)
	var detail := SectorGrid.detail_of(metric)
	var lod_counts: Array = stats.get("lod_counts", [])

	var lines: Array[String] = []
	lines.append("CARIOCA — terreno + streaming (demonstração da Etapa 2)")
	lines.append("FPS %.0f   velocidade %.0f m/s   perfil %s   %s" % [
		Performance.get_monitor(Performance.TIME_FPS),
		float(stats.get("speed", 0.0)),
		preset,
		"piloto automático" if _auto else "livre",
	])
	lines.append("%s   terreno %.1f m" % [
		GeoCoordinateSystem.format_lat_lon(lat_lon.x, lat_lon.y),
		terrain.height_at(metric),
	])
	lines.append("bloco %s   célula de detalhe %d_%d" % [SectorGrid.key(cell), detail.x, detail.y])
	lines.append("setores %d   fila %d   tarefas %d   antecipação %d" % [
		int(stats.get("loaded", 0)),
		int(stats.get("pending", 0)),
		int(stats.get("inflight", 0)),
		int(stats.get("prefetch", 0)),
	])
	lines.append("LOD %s   trocas %d   pendentes %d" % [
		_lod_spread(lod_counts),
		int(stats.get("lod_switches", 0)),
		int(stats.get("lod_pending", 0)),
	])
	lines.append("memória %.1f / %.0f MB   cache %d   acertos %d   despejos %d" % [
		float(stats.get("memory_kb", 0.0)) / 1024.0,
		float(stats.get("memory_budget_kb", 0.0)) / 1024.0,
		int(stats.get("cache_entries", 0)),
		int(stats.get("cache_hits", 0)),
		int(stats.get("evictions", 0)),
	])
	lines.append("WASD mover · Q/E descer/subir · SHIFT rápido · F1 perfil · F2 automático · R voltar")
	label.text = "\n".join(lines)


func _lod_spread(counts: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for value in counts:
		parts.append(str(int(value)))
	return "/".join(parts) if not parts.is_empty() else "-"
