class_name GameBootstrap
extends Node3D

## Montagem do jogo.
##
## Um arquivo só cria e liga todos os sistemas, na ordem em que as dependências
## existem, sem autoload nenhum. Isso mantém o grafo de dependências explícito e
## legível — e é a razão pela qual as ferramentas headless e os testes conseguem
## montar pedaços do mundo sem subir o jogo inteiro.
##
## Ordem obrigatória:
##   configuração -> índice geográfico -> terreno -> raízes -> jogador ->
##   câmera -> streaming -> atores -> clima -> interior -> HUD -> perfil

const START_HOURS := 9.0

var settings: CariocaSettings = null
var terrain: TerrainService = null
var floating: FloatingOrigin = null
var world_root: Node3D = null
var actor_root: Node3D = null
var player: Player = null
var camera_rig: PlayerCamera = null
var streaming: SectorStreamingManager = null
var vehicle_manager: VehicleManager = null
var traffic: TrafficManager = null
var pedestrians: PedestrianManager = null
var day_night: DayNightCycle = null
var weather: WeatherManager = null
var audio: AudioManager = null
var save_system: SaveSystem = null
var interior: InteriorManager = null
var hud: HUD = null
var environment: WorldEnvironment = null
var sun: DirectionalLight3D = null
var start_metric: Vector2 = Vector2.ZERO


func _ready() -> void:
	var first_run := not FileAccess.file_exists(CariocaSettings.SETTINGS_PATH)
	settings = CariocaSettings.get_instance()
	if first_run:
		settings.quality_preset = PlatformProfile.recommended_preset()
		settings.save_to_disk()

	MunicipalityIndex.ensure_loaded()
	terrain = TerrainService.new(settings.world_seed)
	start_metric = MunicipalityIndex.center_of(settings.start_municipality)

	_build_environment()
	_build_roots()
	_build_player()
	_build_camera()
	_build_streaming()
	_build_actors()
	_build_environment_systems()
	_build_interior()
	_build_hud()
	_build_save_system()
	_apply_quality(settings.quality_preset)
	_spawn_starter_vehicle()

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
	sky_material.sky_horizon_color = Color(0.72, 0.68, 0.60)
	sky_material.sky_curve = 0.14
	sky_material.ground_bottom_color = Color(0.16, 0.16, 0.15)
	sky_material.ground_horizon_color = Color(0.58, 0.56, 0.50)
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = false
	env.fog_light_color = Color(0.70, 0.75, 0.80)
	env.glow_enabled = false
	environment.environment = env
	add_child(environment)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.24
	sun.directional_shadow_split_3 = 0.55
	sun.light_energy = 1.1
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

	player.position = Vector3(0.0, terrain.height_at(start_metric) + 2.0, 0.0)
	player.floating = floating
	player.terrain = terrain


func _build_camera() -> void:
	camera_rig = PlayerCamera.new()
	camera_rig.name = "PlayerCamera"
	camera_rig.sensitivity = settings.mouse_sensitivity
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

	traffic = TrafficManager.new()
	traffic.name = "TrafficManager"
	add_child(traffic)
	traffic.setup(floating, streaming, terrain, actor_root, player)

	pedestrians = PedestrianManager.new()
	pedestrians.name = "PedestrianManager"
	add_child(pedestrians)
	pedestrians.setup(floating, streaming, terrain, actor_root, player)

	player.vehicle_manager = vehicle_manager


func _build_environment_systems() -> void:
	audio = AudioManager.new()
	audio.name = "AudioManager"
	add_child(audio)

	weather = WeatherManager.new()
	weather.name = "WeatherManager"
	weather.audio = audio
	weather.vehicle_manager = vehicle_manager
	add_child(weather)
	weather.setup(environment, camera_rig.camera)

	day_night = DayNightCycle.new()
	day_night.name = "DayNightCycle"
	add_child(day_night)
	day_night.setup(environment, sun, START_HOURS)


func _build_interior() -> void:
	interior = InteriorManager.new()
	interior.name = "InteriorManager"
	interior.traffic = traffic
	interior.pedestrians = pedestrians
	interior.audio = audio
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
		"traffic": traffic,
		"pedestrians": pedestrians,
		"day_night": day_night,
		"weather": weather,
		"vehicle_manager": vehicle_manager,
		"interior_manager": interior,
	})
	add_child(hud)
	if hud.debug_label != null:
		hud.debug_label.visible = settings.show_debug_hud


func _build_save_system() -> void:
	save_system = SaveSystem.new()
	save_system.name = "SaveSystem"
	add_child(save_system)


func _spawn_starter_vehicle() -> void:
	var vehicle := vehicle_manager.spawn_near(player.position, Vector3(7.0, 0.0, 3.0))
	if vehicle != null:
		vehicle.rotation.y = 0.4


func apply_quality(preset_name: String) -> void:
	_apply_quality(preset_name)


func _apply_quality(preset_name: String) -> void:
	QualityProfile.apply(preset_name, {
		"streaming": streaming,
		"traffic": traffic,
		"pedestrians": pedestrians,
		"viewport": get_viewport(),
		"camera": camera_rig.camera if camera_rig != null else null,
	})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key((event as InputEventKey).keycode)
	elif event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and not PlatformProfile.is_mobile():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _handle_key(key: int) -> void:
	match key:
		KEY_E:
			player.try_interact()
		KEY_R:
			_respawn()
		KEY_F1:
			_cycle_quality()
		KEY_F3:
			if hud != null:
				hud.toggle_debug()
				settings.show_debug_hud = hud.debug_visible()
				settings.save_to_disk()
		KEY_F5:
			_save(1)
		KEY_F9:
			_load(1)
		KEY_F6:
			if weather != null:
				weather.cycle()
		KEY_F7:
			if day_night != null:
				day_night.advance_hours(2.0)
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		KEY_F11:
			var mode := DisplayServer.window_get_mode()
			if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _cycle_quality() -> void:
	var presets := QualityProfile.names()
	var index := presets.find(settings.quality_preset)
	var next_preset := presets[(index + 1) % presets.size()]
	settings.set_quality_preset(next_preset)
	_apply_quality(next_preset)
	_flash("Perfil: %s" % QualityProfile.describe(next_preset), 4.0)


func _respawn() -> void:
	var height := terrain.height_at(start_metric) + 2.0
	player.teleport_to_local(floating.metric_to_local(start_metric, height))
	streaming.rebuild_all()
	_flash("De volta a %s" % MunicipalityIndex.nearest(start_metric).get("name", "Guapimirim"))


func _save(slot: int) -> void:
	var metric := floating.viewer_metric()
	var municipality := MunicipalityIndex.nearest(metric)
	var payload := save_system.build_payload({
		"seed": settings.world_seed,
		"time_hours": day_night.hours if day_night != null else START_HOURS,
		"weather": weather.kind if weather != null else "clear",
		"quality_preset": settings.quality_preset,
		"municipality": str(municipality.get("code", "?")),
		"metric": metric,
		"vehicle": {"occupied": player.current_vehicle != null},
	})
	if save_system.save(slot, payload):
		_flash("Jogo salvo no slot %d" % slot)
		CariocaBus.get_instance().save_finished.emit(slot, true)
	else:
		_flash("Falha ao salvar: %s" % save_system.last_error, 5.0)
		CariocaBus.get_instance().save_finished.emit(slot, false)


func _load(slot: int) -> void:
	var payload := save_system.load_slot(slot)
	if payload.is_empty():
		_flash("Nada para carregar (%s)" % save_system.last_error, 4.0)
		return
	if day_night != null:
		day_night.set_hours(float(payload.get("time_hours", START_HOURS)))
	if weather != null:
		weather.set_weather(str(payload.get("weather", "clear")), true)
	var position: Array = payload.get("position_metric", [])
	if position.size() >= 2:
		var metric := Vector2(float(position[0]), float(position[1]))
		var height := terrain.height_at(metric) + 1.5
		player.teleport_to_local(floating.metric_to_local(metric, height))
		streaming.rebuild_all()
	_flash("Jogo carregado do slot %d" % slot)


func _flash(message: String, seconds: float = 3.0) -> void:
	if hud != null:
		hud.flash(message, seconds)
