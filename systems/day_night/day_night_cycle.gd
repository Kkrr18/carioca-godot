class_name DayNightCycle
extends Node

## Ciclo de 24 horas.
##
## O sol percorre um arco leste-oeste: nasce às 6h, culmina ao meio-dia e se põe
## às 18h. A orientação da DirectionalLight3D é montada pela base da matriz
## (Basis.looking_at) em vez de ângulos de Euler — assim não existe ambiguidade
## de ordem de rotação e o sol nunca aponta para o lado errado.
##
## À noite a luz direcional é desligada e a iluminação pública acende pela
## emissão compartilhada das luminárias. Não há luz pontual por poste: em um
## iPhone 12 isso estouraria o orçamento de luzes por cluster.

signal hour_changed(hours: float)

const SUNRISE := 6.0
const SUNSET := 18.0
const MAX_ELEVATION_DEG := 72.0

const NIGHT_SKY := Color(0.016, 0.024, 0.055)
const DAY_SKY := Color(0.28, 0.48, 0.82)
const DUSK_SKY := Color(0.46, 0.30, 0.34)
const NIGHT_GROUND := Color(0.02, 0.02, 0.03)
const DAY_GROUND := Color(0.34, 0.33, 0.30)

var environment: WorldEnvironment = null
var sun: DirectionalLight3D = null
var hours: float = 9.0
var day_length_minutes: float = 48.0
var paused: bool = false

var _last_emitted: float = -1.0


func setup(world_environment: WorldEnvironment, sun_light: DirectionalLight3D, start_hours: float = 9.0) -> void:
	environment = world_environment
	sun = sun_light
	hours = fposmod(start_hours, 24.0)
	_apply()


func _process(delta: float) -> void:
	if paused:
		return
	var seconds_per_hour := (day_length_minutes * 60.0) / 24.0
	hours = fposmod(hours + delta / maxf(seconds_per_hour, 0.01), 24.0)
	_apply()


func set_hours(value: float) -> void:
	hours = fposmod(value, 24.0)
	_apply()


func advance_hours(value: float) -> void:
	set_hours(hours + value)


func is_night() -> bool:
	return hours < SUNRISE or hours > SUNSET


func time_string() -> String:
	var whole := int(floor(hours))
	var minutes := int((hours - float(whole)) * 60.0)
	return "%02d:%02d" % [whole, minutes]


func daylight_factor() -> float:
	var angle := (hours - SUNRISE) / (SUNSET - SUNRISE) * PI
	var elevation := sin(angle)
	return clampf(elevation, 0.0, 1.0)


func _apply() -> void:
	if sun != null:
		_apply_sun()
	if environment != null and environment.environment != null:
		_apply_environment(environment.environment)
	_update_lamps()
	if absf(hours - _last_emitted) > 0.02:
		_last_emitted = hours
		hour_changed.emit(hours)
		CariocaBus.get_instance().clock_changed.emit(hours)


func _apply_sun() -> void:
	var angle := (hours - SUNRISE) / (SUNSET - SUNRISE) * PI
	var elevation := sin(angle) * deg_to_rad(MAX_ELEVATION_DEG)
	var azimuth := deg_to_rad(90.0) - angle
	var sun_position := Vector3(
		cos(elevation) * sin(azimuth),
		sin(elevation),
		-cos(elevation) * cos(azimuth)
	).normalized()
	var light_direction := -sun_position
	if absf(light_direction.dot(Vector3.UP)) > 0.995:
		light_direction = (light_direction + Vector3(0.02, 0.0, 0.02)).normalized()
	sun.basis = Basis.looking_at(light_direction, Vector3.UP)

	var height := sin(angle)
	sun.visible = height > -0.02
	sun.light_energy = clampf(height * 1.5, 0.0, 1.25)
	sun.light_color = Color(1.0, 0.93, 0.82).lerp(Color(1.0, 0.72, 0.46), clampf(1.0 - height * 2.4, 0.0, 1.0))
	sun.shadow_enabled = height > 0.05


func _apply_environment(env: Environment) -> void:
	var daylight := daylight_factor()
	var dusk := clampf(1.0 - absf(daylight - 0.15) * 6.0, 0.0, 1.0)
	var sky_color := NIGHT_SKY.lerp(DAY_SKY, daylight)
	sky_color = sky_color.lerp(DUSK_SKY, dusk * 0.55)
	if env.sky != null:
		var sky_material := env.sky.sky_material
		var procedural := sky_material as ProceduralSkyMaterial
		if procedural != null:
			procedural.sky_top_color = sky_color
			procedural.sky_horizon_color = sky_color.lerp(Color(0.72, 0.66, 0.58), daylight * 0.7)
			procedural.ground_horizon_color = procedural.sky_horizon_color
			procedural.ground_bottom_color = NIGHT_GROUND.lerp(DAY_GROUND, daylight)
	env.ambient_light_color = NIGHT_SKY.lerp(Color(0.62, 0.66, 0.72), daylight)
	env.ambient_light_energy = lerpf(0.22, 0.85, daylight)


## Luminárias públicas: um material emissivo compartilhado, aceso ao anoitecer.
func _update_lamps() -> void:
	var lamps := MaterialLibrary.street_lamps()
	var electric := 1.0 - daylight_factor()
	lamps.emission_energy_multiplier = clampf(electric * 2.8, 0.0, 2.8)
	lamps.albedo_color = Color(0.92, 0.88, 0.72).lerp(Color(1.0, 0.86, 0.55), electric)
