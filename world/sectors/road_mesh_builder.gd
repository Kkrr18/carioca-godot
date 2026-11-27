class_name RoadMeshBuilder
extends RefCounted

## Faixa de asfalto de um setor, uma malha só para todas as vias.
##
## Defeito encontrado na primeira execução real do jogo (a rua não aparecia):
## a fita era amostrada **só nos dois extremos do trecho** e levantada 8 cm
## sobre o terreno contínuo — mas a malha do terreno interpola entre vértices
## distantes ~30 m. Entre os extremos, qualquer ondulação do relevo cobria a
## rua. Prédio aparece (é uma caixa alta); rua desaparece (fita fina). Um
## trecho esquemático de 900 m amostrado em dois pontos era o caso pior.
##
## Correção, três frentes:
##   1. **Subdivisão**: cada trecho é amostrado a cada `SAMPLE_STEP` metros;
##   2. **Altura**: a superfície sobe `SURFACE_LIFT` acima do terreno amostrado
##      em cada ponto, não só nos extremos;
##   3. **Saia**: as bordas descem `SKIRT_DROP` — onde o terreno ainda por
##      cima da superfície, o que aparece é a parede da via, e ela lê como
##      asfalto (o material é duplo-face).
## Um draw call por setor continua: mais vértices, não mais malhas.

const SURFACE_LIFT := 0.15
const SKIRT_DROP := 0.4
const SAMPLE_STEP := 8.0
const MAX_STEPS := 128


static func build(roads: Array, terrain: TerrainService, origin_metric: Vector2) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false

	for road in roads:
		if typeof(road) != TYPE_DICTIONARY:
			continue
		var points: Array = road.get("points", [])
		if points.size() < 2:
			continue
		var width := float(road.get("width", 6.0))
		var half := width * 0.5
		for i in range(points.size() - 1):
			var a := _plane(points[i])
			var b := _plane(points[i + 1])
			var segment := b - a
			if segment.length_squared() < 0.01:
				continue
			var length := segment.length()
			var dir := segment / length
			var normal := Vector2(-dir.y, dir.x) * half
			var steps := clampi(int(ceilf(length / SAMPLE_STEP)), 1, MAX_STEPS)

			var prev_left := Vector3.ZERO
			var prev_right := Vector3.ZERO
			for s in range(steps + 1):
				var t := float(s) / float(steps)
				var center := a.lerp(b, t)
				var height := _height_at(terrain, origin_metric, center) + SURFACE_LIFT
				var left := Vector3(center.x - normal.x, height, center.y - normal.y)
				var right := Vector3(center.x + normal.x, height, center.y + normal.y)
				if s > 0:
					_surface_quad(tool, prev_left, left, right, prev_right)
					_wall(tool, prev_left, left, Vector3(-normal.x, 0.0, -normal.y).normalized())
					_wall(tool, prev_right, right, Vector3(normal.x, 0.0, normal.y).normalized())
				prev_left = left
				prev_right = right
			any = true

	if not any:
		return null
	return tool.commit()


## Pista entre duas seções consecutivas, com as normais para cima.
static func _surface_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var up := Vector3.UP
	tool.set_normal(up)
	tool.add_vertex(a)
	tool.set_normal(up)
	tool.add_vertex(b)
	tool.set_normal(up)
	tool.add_vertex(c)
	tool.set_normal(up)
	tool.add_vertex(a)
	tool.set_normal(up)
	tool.add_vertex(c)
	tool.set_normal(up)
	tool.add_vertex(d)


## Parede vertical da borda da via, descendo até o relevo.
static func _wall(tool: SurfaceTool, top_a: Vector3, top_b: Vector3, outward: Vector3) -> void:
	var bottom_a := top_a + Vector3.DOWN * SKIRT_DROP
	var bottom_b := top_b + Vector3.DOWN * SKIRT_DROP
	tool.set_normal(outward)
	tool.add_vertex(top_a)
	tool.set_normal(outward)
	tool.add_vertex(top_b)
	tool.set_normal(outward)
	tool.add_vertex(bottom_b)
	tool.set_normal(outward)
	tool.add_vertex(top_a)
	tool.set_normal(outward)
	tool.add_vertex(bottom_b)
	tool.set_normal(outward)
	tool.add_vertex(bottom_a)


static func _plane(point: Variant) -> Vector2:
	if typeof(point) != TYPE_ARRAY:
		return Vector2.ZERO
	var array: Array = point
	if array.size() < 2:
		return Vector2.ZERO
	return Vector2(float(array[0]), float(array[1]))


static func _height_at(terrain: TerrainService, origin_metric: Vector2, local: Vector2) -> float:
	if terrain == null:
		return 0.0
	return terrain.height_at(origin_metric + Vector2(local.x, -local.y))
