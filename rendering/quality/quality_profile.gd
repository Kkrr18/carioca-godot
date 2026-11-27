class_name QualityProfile
extends RefCounted

## Perfis gráficos. Um mundo, três níveis de custo.
##
## O preset mobile é calibrado para o iPhone 12: raio de setor menor, terreno com
## menos divisões, menos agentes e teto de 30 FPS — porque 30 estáveis é melhor
## que 45 com queda a cada setor carregado.
##
## Chaves de LOD e memória (Etapa 2):
##   lod_divisions         divisões do terreno por nível; índice 0 é o nível
##                         próximo e precisa ser igual a `divisions`
##   lod_distances         distância-limite de cada nível, 0 = sem limite
##   lod_collision_level   até que nível o terreno tem colisão de trimesh
##   lod_skirt             altura da saia anti-rachadura, em metros
##   lod_update_distance   quanto o jogador anda antes de reavaliar os níveis
##   lod_max_switches      trocas de malha por frame
##   lod_switch_budget_usec orçamento de microssegundos para essas trocas
##   lod_switch_delay      tempo que uma mudança precisa se sustentar
##   max_loaded_sectors    teto de setores simultâneos (o raio já limita, isto
##                         protege contra antecipação e oscilação)
##   memory_budget_kb      teto de memória estimada dos setores
##   payload_cache_kb      teto do cache de payloads (voltar para trás)
##   prefetch_gain         quanto a antecipação na direção do movimento pesa
##
## Chaves urbanas (Etapa 3) — lidas por `UrbanConfig.from_preset`:
##   urban_detail            0 caixote, 1 janela, 2 fachada completa
##   urban_tree_density      fração da vegetação de rua que nasce
##   urban_prop_density      fração do mobiliário que nasce
##   urban_max_buildings     teto de edificações por setor
##   urban_parcel_scale      largura de lote (>1 = lotes maiores = menos prédios)
##   urban_max_vegetation    teto de instâncias de vegetação por setor
##   urban_max_props         teto de instâncias de mobiliário por setor
##   urban_landmark_radius   reserva mínima em volta de ponto de referência
##
## Chaves de personagem e câmera (Etapa 4) — lidas por `MovementProfile.from_preset`
## e por `PlayerCamera.apply_preset`:
##   player_walk_speed / player_run_speed / player_sprint_speed   m/s
##   player_jump_velocity   impulso do pulo, m/s
##   player_turn_rate       giro do corpo em direção ao movimento, rad/s
##   player_substep_distance  avanço máximo por `move_and_slide`, em metros
##   camera_distance        distância de repouso do braço da câmera
##   camera_min_distance / camera_max_distance   limites, inclusive de zoom
##   camera_smoothing       multiplicador de suavização do pivô
##   camera_collision_margin folga entre câmera e parede
##   camera_sensitivity     sensibilidade do mouse

const PRESETS := {
	"mobile": {
		"view_radius": 2,
		"divisions": 17,
		"lod_divisions": [17, 13, 9, 5],
		"lod_distances": [384.0, 760.0, 1250.0, 0.0],
		"lod_collision_level": 1,
		"lod_skirt": 10.0,
		"lod_update_distance": 24.0,
		"lod_max_switches": 1,
		"lod_switch_budget_usec": 3500,
		"lod_switch_delay": 0.6,
		"max_loaded_sectors": 21,
		"memory_budget_kb": 42000.0,
		"payload_cache_kb": 6144.0,
		"prefetch_gain": 0.5,
		"max_builds_per_frame": 1,
		"build_budget_usec": 7000,
		"max_vehicles": 6,
		"max_pedestrians": 8,
		"shadow_size": 1024,
		"msaa": 0,
		"max_fps": 30,
		"far_fov": 70.0,
		"urban_detail": 1,
		"urban_tree_density": 0.55,
		"urban_prop_density": 0.5,
		"urban_max_buildings": 44,
		"urban_parcel_scale": 1.25,
		"urban_max_vegetation": 90,
		"urban_max_props": 70,
		"urban_landmark_radius": 12.0,
		"player_walk_speed": 4.2,
		"player_run_speed": 7.4,
		"player_sprint_speed": 9.8,
		"player_jump_velocity": 5.4,
		"player_turn_rate": 13.0,
		"player_substep_distance": 0.45,
		"camera_distance": 4.0,
		"camera_min_distance": 1.6,
		"camera_max_distance": 6.8,
		"camera_smoothing": 1.15,
		"camera_collision_margin": 0.4,
		"camera_sensitivity": 0.0026,
		# Etapa 5 — veículo. O celular tem motor e teto menores: o mundo é o
		# mesmo, o carro só não precisa voar.
		"vehicle_engine_force": 1250.0,
		"vehicle_max_speed": 28.0,
		"vehicle_brake_force": 11.0,
		"vehicle_max_steer": 0.52,
		"vehicle_grip": 3.0,
	},
	"pc_medium": {
		"view_radius": 3,
		"divisions": 33,
		"lod_divisions": [33, 21, 13, 7],
		"lod_distances": [512.0, 1100.0, 1800.0, 0.0],
		"lod_collision_level": 1,
		"lod_skirt": 8.0,
		"lod_update_distance": 32.0,
		"lod_max_switches": 2,
		"lod_switch_budget_usec": 6000,
		"lod_switch_delay": 0.5,
		"max_loaded_sectors": 41,
		"memory_budget_kb": 96000.0,
		"payload_cache_kb": 8192.0,
		"prefetch_gain": 0.6,
		"max_builds_per_frame": 1,
		"build_budget_usec": 9000,
		"max_vehicles": 12,
		"max_pedestrians": 20,
		"shadow_size": 2048,
		"msaa": 1,
		"max_fps": 60,
		"far_fov": 75.0,
		"urban_detail": 2,
		"urban_tree_density": 0.85,
		"urban_prop_density": 0.85,
		"urban_max_buildings": 96,
		"urban_parcel_scale": 1.0,
		"urban_max_vegetation": 220,
		"urban_max_props": 180,
		"urban_landmark_radius": 16.0,
		"player_walk_speed": 4.2,
		"player_run_speed": 7.8,
		"player_sprint_speed": 10.4,
		"player_jump_velocity": 5.4,
		"player_turn_rate": 13.0,
		"player_substep_distance": 0.45,
		"camera_distance": 4.4,
		"camera_min_distance": 1.6,
		"camera_max_distance": 7.5,
		"camera_smoothing": 1.0,
		"camera_collision_margin": 0.35,
		"camera_sensitivity": 0.0022,
		"vehicle_engine_force": 1600.0,
		"vehicle_max_speed": 33.0,
		"vehicle_brake_force": 12.0,
		"vehicle_max_steer": 0.52,
		"vehicle_grip": 3.0,
	},
	"pc_high": {
		"view_radius": 4,
		"divisions": 65,
		"lod_divisions": [65, 33, 17, 9],
		"lod_distances": [640.0, 1400.0, 2300.0, 0.0],
		"lod_collision_level": 1,
		"lod_skirt": 6.0,
		"lod_update_distance": 40.0,
		"lod_max_switches": 2,
		"lod_switch_budget_usec": 8000,
		"lod_switch_delay": 0.4,
		"max_loaded_sectors": 61,
		"memory_budget_kb": 180000.0,
		"payload_cache_kb": 12288.0,
		"prefetch_gain": 0.7,
		"max_builds_per_frame": 2,
		"build_budget_usec": 14000,
		"max_vehicles": 20,
		"max_pedestrians": 36,
		"shadow_size": 4096,
		"msaa": 2,
		"max_fps": 0,
		"far_fov": 78.0,
		"urban_detail": 2,
		"urban_tree_density": 1.0,
		"urban_prop_density": 1.0,
		"urban_max_buildings": 160,
		"urban_parcel_scale": 0.92,
		"urban_max_vegetation": 320,
		"urban_max_props": 260,
		"urban_landmark_radius": 18.0,
		"player_walk_speed": 4.2,
		"player_run_speed": 8.2,
		"player_sprint_speed": 11.0,
		"player_jump_velocity": 5.6,
		"player_turn_rate": 14.0,
		"player_substep_distance": 0.45,
		"camera_distance": 4.6,
		"camera_min_distance": 1.6,
		"camera_max_distance": 8.0,
		"camera_smoothing": 0.95,
		"camera_collision_margin": 0.3,
		"camera_sensitivity": 0.0020,
		"vehicle_engine_force": 1700.0,
		"vehicle_max_speed": 35.0,
		"vehicle_brake_force": 12.0,
		"vehicle_max_steer": 0.54,
		"vehicle_grip": 3.1,
	},
}


static func names() -> Array[String]:
	return ["mobile", "pc_medium", "pc_high"]


static func get_preset(preset_name: String) -> Dictionary:
	if PRESETS.has(preset_name):
		return PRESETS[preset_name]
	return PRESETS["pc_medium"]


## Aplica um perfil a um conjunto de sistemas já criados.
## `context` aceita: streaming, traffic, pedestrians, viewport, camera, audio.
static func apply(preset_name: String, context: Dictionary) -> void:
	var preset := get_preset(preset_name)

	var streaming: SectorStreamingManager = context.get("streaming")
	if streaming != null:
		# Um caminho só: o manager aplica divisões, raio, LOD, cache e tetos de
		# memória, e recomeça o mundo. Antes cada número era escrito aqui, o que
		# deixava o perfil e o streaming discordarem quando um mudava.
		streaming.configure_quality(preset)

	var traffic: TrafficManager = context.get("traffic")
	if traffic != null:
		traffic.max_vehicles = int(preset["max_vehicles"])

	var pedestrians: PedestrianManager = context.get("pedestrians")
	if pedestrians != null:
		pedestrians.max_pedestrians = int(preset["max_pedestrians"])

	# Etapa 5: os carros do mundo seguem o mesmo preset que o resto do jogo.
	var vehicles: VehicleManager = context.get("vehicle_manager")
	if vehicles != null:
		vehicles.apply_preset(preset)

	var viewport: Viewport = context.get("viewport")
	if viewport != null:
		viewport.msaa_3d = int(preset["msaa"])

	var camera: Camera3D = context.get("camera")
	if camera != null:
		camera.fov = float(preset["far_fov"])

	RenderingServer.directional_shadow_atlas_set_size(int(preset["shadow_size"]), true)
	Engine.max_fps = int(preset["max_fps"])

	CariocaBus.get_instance().quality_applied.emit(preset_name)


static func describe(preset_name: String) -> String:
	var preset := get_preset(preset_name)
	return "%s: raio %d blocos, terreno %d/%d divisões (LOD), %d carros, %d pedestres" % [
		preset_name,
		int(preset["view_radius"]),
		int(preset["divisions"]),
		int(LodProfile.from_preset(preset).divisions_for(1)),
		int(preset["max_vehicles"]),
		int(preset["max_pedestrians"]),
	]
