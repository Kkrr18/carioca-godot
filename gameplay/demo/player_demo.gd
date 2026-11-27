extends Node3D

## Demonstração jogável da Etapa 4 — personagem no Centro de Guapimirim.
##
## Não é um protótipo paralelo: usa o mesmo `Player`, o mesmo `PlayerCamera`, o
## mesmo `SectorStreamingManager` e o mesmo `HUD` do jogo, sobre a mesma camada
## urbana da Etapa 3. A diferença em relação a `main.tscn` é o que **não** sobe:
## trânsito, pedestres, clima, ciclo do dia, áudio e interiores pesados ficam de
## fora para a cena abrir rápido durante o desenvolvimento do personagem.
##
## Rodar:
##   godot --path . gameplay/demo/player_demo.tscn
##
## Teclas:
##   WASD mover · CTRL caminhar · SHIFT sprint · ESPAÇO pular · E interagir
##   mouse olhar · roda distância
##   F1 perfil gráfico   F2 recentralizar câmera   F3 diagnóstico
##   F5 mostrar/esconder controles de toque (testar layout mobile no PC)
##   R voltar ao início   ESC soltar o mouse

const START_HOURS := 9.5

var settings: CariocaSettings = null
var terrain: TerrainService = null
var floating: FloatingOrigin = null
var world_root: Node3D = null
var actor_root: Node3D = null
var player: Player = null
var camera_rig: PlayerCamera = null
var streaming: SectorStreamingManager = null
var vehicle_manager: VehicleManager = null
var interior: InteriorManager = null
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
	_build_actors()
	_build_interior()
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

	var spawn_height := terrain.height_at(start_metric) + 2.0
	player.position = Vector3(0.0, spawn_height, 0.0)
	player.floating = floating
	player.terrain = terrain
	player.state_changed.connect(_on_player_state_changed)


func _build_camera() -> void:
	camera_rig = PlayerCamera.new()
	camera_rig.name = "PlayerCamera"
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


func _build_actors() -> void:
	vehicle_manager = VehicleManager.new()
	vehicle_manager.name = "VehicleManager"
	add_child(vehicle_manager)
	vehicle_manager.setup(terrain, floating, actor_root)
	player.vehicle_manager = vehicle_manager

	# Dois carros ao lado do ponto de nascimento: um deles serve para o teste de
	# interação "E dirigir" sem precisar procurar o mundo.
	var first := vehicle_manager.spawn_near(player.position, Vector3(6.0, 0.0, 2.5))
	if first != null:
		first.rotation.y = 0.6
	var second := vehicle_manager.spawn_near(player.position, Vector3(-7.0, 0.0, -4.0))
	if second != null:
		second.rotation.y = -1.1


func _build_interior() -> void:
	interior = InteriorManager.new()
	interior.name = "InteriorManager"
	add_child(interior)
	interior.setup(player, floating, streaming)
	player.interior_manager = interior


func _build_hud() -> void:
	hud = HUD.new()
	hud.name = "HUD"
	hud.setup({
		"player": player,
		"streaming": streaming,
		"floating": floating,
		"terrain": terrain,
		"vehicle_manager": vehicle_manager,
		"interior_manager": interior,
	})
	add_child(hud)
	if hud.debug_label != null:
		hud.debug_label.visible = settings.show_debug_hud
	if hud.touch != null:
		# No PC os controles ficam escondidos, mas F5 mostra: é assim que se
		# confere o layout de toque sem um aparelho na mão.
		hud.touch.visible_controls = PlatformProfile.is_mobile()
		hud.touch.look_sensitivity = settings.touch_sensitivity


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Etapa4"
	add_child(layer)
	overlay = Label.new()
	overlay.name = "PlayerState"
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
	overlay.offset_bottom = 480.0
	layer.add_child(overlay)


func _apply_quality(preset_name: String) -> void:
	var preset := QualityProfile.get_preset(preset_name)
	QualityProfile.apply(preset_name, {
		"streaming": streaming,
		"viewport": get_viewport(),
		"camera": camera_rig.camera if camera_rig != null else null,
	})
	player.apply_movement_profile(MovementProfile.from_preset(preset))
	camera_rig.apply_preset(preset)
	camera_rig.set_sensitivity(settings.mouse_sensitivity)
	camera_rig.set_invert_y(settings.camera_invert_y)
	camera_rig.distance = clampf(settings.camera_distance, camera_rig.min_distance, camera_rig.max_distance)
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
	lines.append("ETAPA 4 — personagem e câmera (Centro de Guapimirim)")
	lines.append("FPS %.0f   %s   %.1f m/s   chão %s   subpassos %d" % [
		Performance.get_monitor(Performance.TIME_FPS),
		player.state_name(),
		player.speed(),
		"sim" if player.is_on_floor() else "não",
		player.substeps(1.0 / 60.0),
	])
	lines.append("câmera %s" % (camera_rig.describe() if camera_rig != null else "—"))
	lines.append("interação: %s" % (player.interaction_prompt() if not player.interaction_prompt().is_empty() else "nada ao alcance"))
	lines.append("animação: %s   importada: %s" % [
		player.animator.describe(),
		"sim" if player.animator.is_bound() else "não (boneco provisório)",
	])
	lines.append("setores %d   memória %.1f MB   perfil %s" % [
		streaming.loaded_count() if streaming != null else 0,
		streaming.loaded_kb() / 1024.0 if streaming != null else 0.0,
		settings.quality_preset,
	])
	lines.append("WASD mover · CTRL caminhar · SHIFT sprint · ESPAÇO pular · E interagir · roda zoom · F1 perfil · F2 câmera · F3 HUD · F5 toque")
	overlay.text = "\n".join(lines)


func _on_player_state_changed(state: int, previous: int) -> void:
	if hud != null and state != previous:
		# Uma linha só, curta: estado do personagem não é diagnóstico técnico.
		pass


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
	var height := terrain.height_at(start_metric) + 2.0
	player.teleport_to_local(floating.metric_to_local(start_metric, height))
	streaming.rebuild_all()
	if hud != null:
		hud.flash("De volta ao centro de Guapimirim", 3.0)
