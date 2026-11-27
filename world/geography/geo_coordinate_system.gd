class_name GeoCoordinateSystem
extends RefCounted

## Fachada única de conversão entre coordenadas geográficas e o espaço métrico
## global do jogo. Nada no projeto converte latitude/longitude por conta
## própria: todos passam por aqui.
##
## Convenções (documentadas uma vez, usadas em todo o código):
##   latitude/longitude  WGS84/SIRGAS 2000, graus decimais, sul e oeste negativos.
##   espaço métrico      Vector2(easting, northing), metros, northing para norte.
##   espaço 3D da Godot  Vector3(east, altura, -north) — -Z é norte, como manda a
##                       convenção de câmera da engine.

const EARTH_RADIUS := 6378137.0


static func geographic_to_metric(latitude: float, longitude: float) -> Vector2:
	return CariocaProjection.forward(latitude, longitude)


## Retorna Vector2(latitude, longitude).
static func metric_to_geographic(metric: Vector2) -> Vector2:
	return CariocaProjection.inverse(metric.x, metric.y)


## Aproximação de plano tangente local (x = leste, y = norte, metros).
## Serve para trechos curtos — a diferença em relação à projeção cresce com a
## distância e é justamente o que os testes medem.
static func tangent_offsets(latitude: float, longitude: float, origin_lat: float, origin_lon: float) -> Vector2:
	var lat_rad := deg_to_rad(origin_lat)
	var east := EARTH_RADIUS * deg_to_rad(longitude - origin_lon) * cos(lat_rad)
	var north := EARTH_RADIUS * deg_to_rad(latitude - origin_lat)
	return Vector2(east, north)


static func horizontal_distance(a_lat: float, a_lon: float, b_lat: float, b_lon: float) -> float:
	var pa := geographic_to_metric(a_lat, a_lon)
	var pb := geographic_to_metric(b_lat, b_lon)
	return pa.distance_to(pb)


## Espaço métrico -> posição 3D local relativa a uma origem métrica.
## A altura entra separada porque o relevo não faz parte da projeção.
static func metric_to_local(metric: Vector2, origin_metric: Vector2, height: float = 0.0) -> Vector3:
	var delta := metric - origin_metric
	return Vector3(delta.x, height, -delta.y)


## Inverso do anterior: posição 3D local -> espaço métrico global.
static func local_to_metric(local: Vector3, origin_metric: Vector2) -> Vector2:
	return origin_metric + Vector2(local.x, -local.z)


static func format_lat_lon(latitude: float, longitude: float) -> String:
	var ns := "S" if latitude < 0.0 else "N"
	var ew := "W" if longitude < 0.0 else "E"
	return "%.6f%s %.6f%s" % [absf(latitude), ns, absf(longitude), ew]


static func format_metric(metric: Vector2) -> String:
	return "E %.0f / N %.0f" % [metric.x, metric.y]
