class_name Minimap
extends Control

## Minimapa desenhado a partir dos próprio dados de setor já carregados.
##
## Não usa viewport nem câmera ortográfica: cada via é uma linha na tela. Custa
## quase nada, não aloca render target no celular e mostra exatamente a mesma
## geometria que o jogador vê no mundo — porque vem do mesmo payload.

var player: Node3D = null
var streaming: SectorStreamingManager = null
var radius_m: float = 640.0
var road_color := Color(0.86, 0.87, 0.90, 0.85)
var arterial_color := Color(1.0, 0.78, 0.42, 0.95)

var _timer: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(168.0, 168.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer = 0.0


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.35
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.04, 0.06, 0.09, 0.62))
	draw_rect(rect, Color(0.90, 0.92, 0.95, 0.28), false, 1.0)

	if player == null or streaming == null:
		return
	var center := player.position
	var scale := minf(size.x, size.y) * 0.5 / maxf(radius_m, 1.0)
	var limit_sq := radius_m * radius_m

	var coords: Array = streaming.loaded_coords()
	for coord in coords:
		var instance: SectorInstance = streaming.loaded_sector(coord)
		if instance == null:
			continue
		for raw in instance.payload.get("roads", []):
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var road: Dictionary = raw
			var points: Array = road.get("points", [])
			if points.size() < 2:
				continue
			var a_local := Vector2(float(points[0][0]), float(points[0][1]))
			var b_local := Vector2(float(points[1][0]), float(points[1][1]))
			var a := Vector3(instance.position.x + a_local.x, 0.0, instance.position.z + a_local.y)
			var b := Vector3(instance.position.x + b_local.x, 0.0, instance.position.z + b_local.y)
			var mid := (a + b) * 0.5
			var offset := Vector2(mid.x - center.x, mid.z - center.z)
			if offset.length_squared() > limit_sq:
				continue
			var screen_a := Vector2(
				size.x * 0.5 + (a.x - center.x) * scale,
				size.y * 0.5 + (a.z - center.z) * scale
			)
			var screen_b := Vector2(
				size.x * 0.5 + (b.x - center.x) * scale,
				size.y * 0.5 + (b.z - center.z) * scale
			)
			var is_arterial := str(road.get("class", "")) == WorldSchema.ROAD_ARTERIAL
			draw_line(screen_a, screen_b, arterial_color if is_arterial else road_color, 2.0 if is_arterial else 1.0)

	_draw_player(center, scale)
	_draw_north()


func _draw_player(_center: Vector3, _scale: float) -> void:
	var middle := size * 0.5
	var yaw := player.rotation.y
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(-forward.y, forward.x)
	var tip := middle + forward * 7.5
	var left := middle - forward * 4.5 + right * 4.5
	var right_point := middle - forward * 4.5 - right * 4.5
	draw_colored_polygon(PackedVector2Array([tip, left, right_point]), Color(1.0, 0.86, 0.36))
	draw_circle(middle, 2.5, Color(0.05, 0.05, 0.05, 1.0))


func _draw_north() -> void:
	var label := "N"
	var position := size - Vector2(14.0, 14.0)
	draw_string(ThemeDB.fallback_font, position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.92, 0.96, 0.85))
