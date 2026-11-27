class_name TerrainService
extends RefCounted

## Altura do terreno em qualquer ponto do estado, em metros.
##
## Duas fontes, na ordem:
##   1. Modelo digital de elevação real (SRTM .hgt) quando existe em disco;
##   2. Relevo procedural determinístico, para o projeto rodar sem baixar dado.
##
## A função é pura em relação à posição no espaço métrico — nunca ao setor.
## É isso que garante que dois setores vizinhos calculem a mesma altura na
## borda e a malha não abra fresta.

const DEFAULT_SEED := 20170


var seed_value: int = DEFAULT_SEED
var elevation: HGTElevationSource = null
var using_real_elevation: bool = false


func _init(world_seed: int = DEFAULT_SEED, elevation_dir: String = "res://data/geographic/elevation") -> void:
	seed_value = world_seed
	elevation = HGTElevationSource.new(elevation_dir)
	using_real_elevation = elevation.has_data()


func height_at(metric: Vector2) -> float:
	if using_real_elevation and elevation != null:
		var lat_lon := CariocaProjection.inverse(metric.x, metric.y)
		var real_height: float = elevation.height_at(lat_lon.x, lat_lon.y)
		if not is_nan(real_height):
			return real_height
	return procedural_height(metric)


## Relevo sintético plausível: planície baixa, serra ao fundo, vales suaves e
## áreas urbanas aplainadas. Não substitui dado real — é o palco provisório
## até o SRTM entrar.
func procedural_height(metric: Vector2) -> float:
	var warp := Deterministic.fbm(metric.x / 9000.0, metric.y / 9000.0, 2, seed_value) * 700.0
	var base := Deterministic.fbm((metric.x + warp) / 2400.0, (metric.y + warp) / 2400.0, 4, seed_value + 11) * 0.5 + 0.5
	var ridge := Deterministic.fbm(metric.x / 14000.0, metric.y / 14000.0, 2, seed_value + 71) * 0.5 + 0.5
	var relief := smoothstep(0.44, 0.94, ridge)
	var height := base * 65.0 + relief * (480.0 + base * 680.0)
	var density := MunicipalityIndex.density_at(metric)
	height *= 1.0 - density * 0.55
	return maxf(height, 0.0)


## Normal da superfície no espaço local da Godot (x = leste, y = cima,
## z = sul), coerente com a convenção de coordenadas do projeto.
func normal_at(metric: Vector2, sample: float = 2.0) -> Vector3:
	var west := height_at(metric - Vector2(sample, 0.0))
	var east := height_at(metric + Vector2(sample, 0.0))
	var north := height_at(metric + Vector2(0.0, sample))
	var south := height_at(metric - Vector2(0.0, sample))
	return Vector3(west - east, 2.0 * sample, north - south).normalized()


func slope_at(metric: Vector2, sample: float = 4.0) -> float:
	var normal := normal_at(metric, sample)
	return 1.0 - clampf(normal.y, 0.0, 1.0)


## Inclinação em graus — usada para decidir onde nasce construção e vegetação.
func slope_degrees(metric: Vector2) -> float:
	var normal := normal_at(metric, 4.0)
	return rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))


func height_at_lat_lon(latitude: float, longitude: float) -> float:
	return height_at(GeoCoordinateSystem.geographic_to_metric(latitude, longitude))
