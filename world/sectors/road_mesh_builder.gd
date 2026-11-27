class_name RoadMeshBuilder
extends RefCounted

## Faixa de asfalto de um setor, uma malha só para todas as vias.
##
## Cada via vira um retângulo ao longo do traçado, colado no terreno com 8 cm de
## folga para não brigar por profundidade. Um draw call por setor, não por rua.


static func build(roads: Array, terrain: TerrainService, origin_metric: Vector2) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	var any := false

	for road in roads:
		if typeof(road) != TYPE_DICTIONARY:
			continue
		var points: Array = road.get("points", [])
		if points.size() < 2:
			continue
		var width := float(road.get("width", 6.0))
		var half := width * 0.5
		var count := points.size()
		for i in range(count - 1):
			var a := _local_point(points[i], terrain, origin_metric, half)
			var b := _local_point(points[i + 1], terrain, origin_metric, half)
			var dir := Vector2(b.x - a.x, b.z - a.z)
			if dir.length_squared() < 0.01:
				continue
			dir = dir.normalized()
			var normal := Vector2(-dir.y, dir.x) * half
			var a0 := Vector3(a.x + normal.x, a.y, a.z + normal.y)
			var a1 := Vector3(a.x - normal.x, a.y, a.z - normal.y)
			var b0 := Vector3(b.x + normal.x, b.y, b.z + normal.y)
			var b1 := Vector3(b.x - normal.x, b.y, b.z - normal.y)
			tool.add_vertex(a0)
			tool.add_vertex(b0)
			tool.add_vertex(b1)
			tool.add_vertex(a0)
			tool.add_vertex(b1)
			tool.add_vertex(a1)
			any = true

	if not any:
		return null
	return tool.commit()


static func _local_point(point: Variant, terrain: TerrainService, origin_metric: Vector2, half: float) -> Vector3:
	var local := Vector2.ZERO
	if typeof(point) == TYPE_ARRAY:
		var array: Array = point
		if array.size() >= 2:
			local = Vector2(float(array[0]), float(array[1]))
	var metric := origin_metric + Vector2(local.x, -local.y)
	var height := terrain.height_at(metric) + 0.08
	return Vector3(local.x, height, local.y)
