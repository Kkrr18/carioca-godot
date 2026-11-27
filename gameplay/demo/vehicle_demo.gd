extends Node3D

## Demonstração jogável da Etapa 5 — dirigir no Centro de Guapimirim.
##
## Não é um circuito separado: é o mesmo mundo do jogo (terreno, streaming e a
## camada urbana da Etapa 3, com as ruas largas do eixo e as quadras em volta),
## o mesmo `Player` da Etapa 4, o mesmo `HUD`, e a câmera é a veicular da
## Etapa 5. A diferença em relação a `main.tscn` é o que **não** sobe: trânsito
## com IA, pedestres, clima, ciclo do dia e interiores ficam de fora para a
## cena abrir rápido durante o ajuste de dirigibilidade.
##
## Rodar:
##   godot --path . gameplay/demo/vehicle_demo.tscn
##
## Teclas:
##   W acelerar · S freio/ré · A/D direção · ESPAÇO freio de mão
##   H buzina · V câmera próxima/distante · E entrar/sair
##   mouse olhar · roda zoom · F1 perfil · F2 recentralizar · F3 diagnóstico
##   F5 controles de toque (testar mobile no PC) · R voltar ao início

const START_HOURS := 9.5

var settings: CariocaSettings = null
var terrain: TerrainService = null
var floating: FloatingOrigin = null
var world_root: Node3D = null
var actor_root: Node3D = null
var player: Player = null
var camera_rig: VehicleCamera = null
var streaming: SectorStreamingManager = null
var vehicle_manager: VehicleManager = null
var hud: HUD = null
var environment: WorldEnvironment = null
var sun: DirectionalLight3D = null
var overlay: Label = null
var start_metric: Vector2 = Vector2.ZERO

var _overlay_timer: float = 0.0


func _ready() -> void:
	settings = CariocaSettings.get_instance()
	InputBindings.ensure_registered()
	InputBindings.apply_remaps(settings.input_remaps)

	MunicipalityIndex.ensure_loaded()
	terrain = TerrainService.new(settings.world_seed)
	start_metric = MunicipalityIndex.center_of("GUAPI")

	_build_environment()
	_build_roots()
	_build_player()
	_build_camera()
	_build_streaming()
	_build_vehicles()
	_build_hud()
	_build_overlay()
	_apply_quality(settings.quality_preset)

	CariocaBus.get_instance().world_started.emit()
	if not PlatformProfile.is_mobile():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_environment() -> void:
	environment = WorldEnvironment.new()
	environment.name = "Environment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.28, 0.48, 0.82)
	sky_material.sky_horizon_color = Color(0.74, 0.70, 0.62)
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 260.0
	sun.light_energy = 1.12
	sun.rotation = Vector3(deg_to_rad(-46.0), deg_to_rad(34.0), 0.0)
	add_child(sun)


func _build_roots() -> void:
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)
	actor_root = Node3D.new()
	actor_root.name = "Actors"
	add_child(actor_root)


func _build_player() -> void:
	player = Player.new()
	player.name = "Player"
	actor_root.add_child(player)

	floating = FloatingOrigin.new()
	floating.name = "FloatingOrigin"
	add_child(floating)
	floating.setup(world_root, actor_root, player, start_metric)

	# Nasce na calçada, um passo do carro na pista: a demonstração começa com a
	# pergunta "como entro no carro?" a uma tecla de distância.
	var spawn_height := terrain.height_at(start_metric) + 2.0
	player.position = Vector3(0.0, spawn_height, 0.0)
	player.floating = floating
	player.terrain = terrain


func _build_camera() -> void:
	camera_rig = VehicleCamera.new()
	camera_rig.name = "VehicleCamera"
	camera_rig.sensitivity = settings.mouse_sensitivity
	camera_rig.set_invert_y(settings.camera_invert_y)
	add_child(camera_rig)
	camera_rig.set_target(player)
	player.camera_rig = camera_rig


func _build_streaming() -> void:
	streaming = SectorStreamingManager.new()
	streaming.name = "SectorStreaming"
	streaming.seed_value = settings.world_seed
	streaming.sector_parent = world_root
	streaming.setup(terrain, floating, player)
	add_child(streaming)


func _build_vehicles() -> void:
	vehicle_manager = VehicleManager.new()
	vehicle_manager.name = "VehicleManager"
	add_child(vehicle_manager)
	vehicle_manager.setup(terrain, floating, actor_root)
	player.vehicle_manager = vehicle_manager

	# Um carro na pista em frente, um carro na contramão: entra no primeiro,
	# manobra, sai, entra no outro. Dois cores diferentes também mostram que o
	# casco pintado responde à cor do manager.
	var first := vehicle_manager.spawn_near(player.position, Vector3(4.0, 0.0, 0.0))
	if first != null:
		first.rotation.y = 0.0
	var second := vehicle_manager.spawn_near(player.position, Vector3(-9.0, 0.0, -6.0))
	if second != null:
		second.rotation.y = 1.2


func _build_hud() -> void:
	hud = HUD.new()
	hud.name = "HUD"
	hud.setup({
		"player": player,
		"streaming": streaming,
		"floating": floating,
		"terrain": terrain,
		"vehicle_manager": vehicle_manager,
	})
	add_child(hud)
	if hud.debug_label != null:
		hud.debug_label.visible = settings.show_debug_hud
	if hud.touch != null:
		hud.touch.visible_controls = PlatformProfile.is_mobile()
		hud.touch.look_sensitivity = settings.touch_sensitivity


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Etapa5"
	add_child(layer)
	overlay = Label.new()
	overlay.name = "Driving"
	overlay.add_theme_font_size_override("font_size", 13)
	overlay.add_theme_color_override("font_color", Color(1.0, 0.94, 0.76))
	overlay.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	overlay.add_theme_constant_override("outline_size", 3)
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.offset_left = 12.0
	overlay.offset_top = 344.0
	overlay.offset_right = -12.0
	overlay.offset_bottom = 500.0
	layer.add_child(overlay)


func _apply_quality(preset_name: String) -> void:
	var preset := QualityProfile.get_preset(preset_name)
	QualityProfile.apply(preset_name, {
		"streaming": streaming,
		"vehicle_manager": vehicle_manager,
		"viewport": get_viewport(),
		"camera": camera_rig.camera if camera_rig != null else null,
	})
	player.apply_movement_profile(MovementProfile.from_preset(preset))
	camera_rig.apply_preset(preset)
	camera_rig.set_sensitivity(settings.mouse_sensitivity)
	camera_rig.set_invert_y(settings.camera_invert_y)
	camera_rig.touch_controls = hud.touch if hud != null else null


func _process(delta: float) -> void:
	_overlay_timer -= delta
	if _overlay_timer > 0.0:
		return
	_overlay_timer = 0.2
	_update_overlay()


func _update_overlay() -> void:
	if overlay == null or player == null:
		return
	var lines: Array[String] = []
	lines.append("ETAPA 5 — veículos (Centro de Guapimirim)")
	var driving: bool = player.current_vehicle != null
	if driving:
		var vehicle := player.current_vehicle
		lines.append("dirigindo: %.0f km/h · marcha %s · esterço %.0f°" % [
			vehicle.speed_kmh(),
			vehicle.model.gear_name(),
			rad_to_deg(vehicle.model.steering),
		])
		lines.append("câmera %s   (V alterna próxima/distante)" % camera_rig.describe())
	else:
		var nearest: Vehicle = null
		if vehicle_manager != null:
			nearest = vehicle_manager.nearest(player.global_position, Player.VEHICLE_RADIUS)
		if nearest != null:
			lines.append("carro ao alcance: aperte E para dirigir (%s)" % nearest.describe())
		else:
			lines.append("sem carro ao alcance — aproxime-se de um e aperte E")
	lines.append("FPS %.0f   %s" % [
		Performance.get_monitor(Performance.TIME_FPS),
		player.describe(),
	])
	lines.append("setores %d   memória %.1f MB   perfil %s" % [
		streaming.loaded_count() if streaming != null else 0,
		streaming.loaded_kb() / 1024.0 if streaming != null else 0.0,
		settings.quality_preset,
	])
	lines.append("W acelerar · S freio/ré · A/D direção · ESPAÇO mão · H buzina · V câmera · E entrar/sair · F5 toque")
	overlay.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key((event as InputEventKey).keycode)
	elif event is InputEventMouseButton and event.pressed:
		if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not PlatformProfile.is_mobile():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _handle_key(key: int) -> void:
	match key:
		KEY_E:
			player.try_interact()
		KEY_F1:
			_cycle_quality()
		KEY_F2:
			if camera_rig != null:
				camera_rig.reset_yaw()
		KEY_F3:
			if hud != null:
				hud.toggle_debug()
		KEY_F5:
			if hud != null and hud.touch != null:
				hud.touch.visible_controls = not hud.touch.visible_controls
		KEY_R:
			_respawn()
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _cycle_quality() -> void:
	var presets := QualityProfile.names()
	var index := presets.find(settings.quality_preset)
	var next := presets[(index + 1) % presets.size()]
	settings.set_quality_preset(next)
	_apply_quality(next)
	if hud != null:
		hud.flash("Perfil: %s" % QualityProfile.describe(next), 3.0)


func _respawn() -> void:
	if player.current_vehicle != null:
		player.exit_vehicle()
	var height := terrain.height_at(start_metric) + 2.0
	player.teleport_to_local(floating.metric_to_local(start_metric, height))
	streaming.rebuild_all()
	if hud != null:
		hud.flash("De volta ao centro de Guapimirim", 3.0)
