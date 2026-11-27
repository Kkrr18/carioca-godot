class_name BuildingMeshBuilder
extends RefCounted

## Prédios de um setor numa única malha com cor por vértice.
##
## Cada construção é uma caixa orientada (testada, profundidade, pé-direito),
## com cor variando por andar — o suficiente para ler como fachada a distância
## sem textura nenhuma. Uma malha para o setor inteiro mantém o custo de draw
## calls proporcional ao número de setores, não ao número de prédios.
##
## A colisão não usa essa malha: o SectorInstance cria uma caixa por prédio, que
## é bem mais barata para o CharacterBody3D e para o trânsito.

const FLOOR_HEIGHT := 3.15


static func build(buildings: Array) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for raw in buildings:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		if _append_building(tool, raw):
			any = true
	if not any:
		return null
	return tool.commit()


static func _append_building(tool: SurfaceTool, building: Dictionary) -> bool:
	var center := _vec2(building.get("center", [0.0, 0.0]))
	var size := _vec2(building.get("size", [10.0, 10.0]))
	var angle := float(building.get("angle", 0.0))
	var levels := maxi(int(building.get("levels", 1)), 1)
	var height := float(building.get("height", float(levels) * FLOOR_HEIGHT))
	if size.x <= 0.5 or size.y <= 0.5:
		return false
	var sort_key := str(building.get("id", "b"))
	var variation := float(Deterministic.hash2(sort_key.length(), levels, 7) % 100) / 100.0
	var base := _palette(str(building.get("kind", "residential")), variation)

	var basis := Basis(Vector3.UP, angle)
	var half := size * 0.5
	var corners := [
		center + _rotate(Vector2(-half.x, -half.y), angle),
		center + _rotate(Vector2(half.x, -half.y), angle),
		center + _rotate(Vector2(half.x, half.y), angle),
		center + _rotate(Vector2(-half.x, half.y), angle),
	]

	for level in range(levels):
		var y0 := float(level) * FLOOR_HEIGHT
		var y1 := y0 + FLOOR_HEIGHT
		if y1 > height + 0.01:
			y1 = height
		var shade := 1.0 + (float(level % 3) - 1.0) * 0.07
		var color := Color(
			clampf(base.r * shade, 0.0, 1.0),
			clampf(base.g * shade, 0.0, 1.0),
			clampf(base.b * shade, 0.0, 1.0)
		)
		for i in range(4):
			var p0: Vector2 = corners[i]
			var p1: Vector2 = corners[(i + 1) % 4]
			_quad(tool,
				Vector3(p0.x, y0, p0.y), Vector3(p1.x, y0, p1.y),
				Vector3(p1.x, y1, p1.y), Vector3(p0.x, y1, p0.y),
				color, 0.55)

	var roof := base.darkened(0.35)
	_quad(tool,
		Vector3(corners[0].x, height, corners[0].y),
		Vector3(corners[3].x, height, corners[3].y),
		Vector3(corners[2].x, height, corners[2].y),
		Vector3(corners[1].x, height, corners[1].y),
		roof, 1.0)
	return true


static func _rotate(v: Vector2, angle: float) -> Vector2:
	var c := cos(angle)
	var s := sin(angle)
	return Vector2(v.x * c - v.y * s, v.x * s + v.y * c)


static func _vec2(value: Variant) -> Vector2:
	if typeof(value) == TYPE_ARRAY:
		var array: Array = value
		if array.size() >= 2:
			return Vector2(float(array[0]), float(array[1]))
	return Vector2.ZERO


static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, normal_hint: float) -> void:
	tool.set_color(color)
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)
	tool.add_vertex(a)
	tool.add_vertex(c)
	tool.add_vertex(d)


static func _palette(kind: String, variation: float) -> Color:
	match kind:
		"commercial":
			return Color(0.62, 0.63, 0.66).lerp(Color(0.48, 0.53, 0.60), variation)
		"public":
			return Color(0.78, 0.74, 0.62).lerp(Color(0.68, 0.65, 0.55), variation)
		_:
			return Color(0.83, 0.79, 0.71).lerp(Color(0.74, 0.61, 0.49), variation)
