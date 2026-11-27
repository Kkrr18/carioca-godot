class_name TerrainMeshBuilder
extends RefCounted

## Malha de terreno de um setor.
##
## A altura é amostrada no espaço métrico global, não no local do setor. Essa é
## a única razão pela qual dois setores vizinhos terminam na mesma borda: a
## amostra da coluna 33 do setor A é exatamente a amostra da coluna 0 do setor B,
## porque as duas caem na mesma coordenada métrica. Nada de costura, nada de
## correção manual.
##
## A malha inclui uma coroa de uma célula em volta (para calcular normal nas
## bordas sem consultar o terreno com diferenças finitas caras) e o material é
## duplo-face por segurança: um erro de ordem de vértice não deixa o chão
## invisível em nenhum dispositivo.


## `skirt` > 0 acrescenta uma saia vertical em volta da borda. Ela só é visível
## onde haveria fresta: com todos os setores na mesma resolução a saia fica
## escondida sob a superfície. É o preço (algumas centenas de triângulos) para o
## LOD poder variar de setor para setor sem abrir buraco no horizonte.
##
## A saia é acrescentada **depois** da grade: os primeiros (divisões+1)² vértices
## continuam sendo exatamente o terreno, o que mantém o teste de costura válido.
static func build(coord: Vector2i, divisions: int, terrain: TerrainService, skirt: float = 0.0) -> ArrayMesh:
	var div := maxi(divisions, 2)
	var step := SectorGrid.SECTOR_SIZE / float(div)
	var origin := SectorGrid.sector_origin(coord)

	var ext := div + 3
	var heights := PackedFloat32Array()
	heights.resize(ext * ext)
	for jy in range(ext):
		for jx in range(ext):
			var local_x := (float(jx) - 1.0) * step
			var local_z := (float(jy) - 1.0) * step
			heights[jy * ext + jx] = terrain.height_at(origin + Vector2(local_x, -local_z))

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var side := div + 1
	vertices.resize(side * side)
	normals.resize(side * side)
	uvs.resize(side * side)

	for iy in range(side):
		for ix in range(side):
			var index := iy * side + ix
			var local_x := float(ix) * step
			var local_z := float(iy) * step
			vertices[index] = Vector3(local_x, heights[(iy + 1) * ext + (ix + 1)], local_z)
			normals[index] = _normal(heights, ext, ix + 1, iy + 1, step)
			uvs[index] = Vector2(local_x, local_z) / 16.0

	for iy in range(div):
		for ix in range(div):
			var i0 := iy * side + ix
			var i1 := i0 + 1
			var i2 := i0 + side
			var i3 := i2 + 1
			indices.append(i0)
			indices.append(i2)
			indices.append(i1)
			indices.append(i1)
			indices.append(i2)
			indices.append(i3)

	if skirt > 0.0:
		# `_add_skirt` devolve os arrays: PackedArray é tipo de valor em GDScript,
		# então anexar dentro da função alteraria só a cópia do parâmetro.
		var skirted := _add_skirt(vertices, normals, uvs, indices, side, step, skirt)
		vertices = skirted[0]
		normals = skirted[1]
		uvs = skirted[2]
		indices = skirted[3]

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Anexa o anel de saia e devolve os quatro arrays como
## `[vértices, normais, uvs, índices]`.
static func _add_skirt(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, side: int, step: float, skirt: float) -> Array:
	var half := float(side - 1) * step * 0.5
	var edges: Array = []
	for i in range(side - 1):
		edges.append([i, i + 1])
		edges.append([(side - 1) * side + i + 1, (side - 1) * side + i])
	for j in range(side - 1):
		edges.append([j * side, (j + 1) * side])
		edges.append([(j + 1) * side + side - 1, j * side + side - 1])
	for edge in edges:
		var a: int = edge[0]
		var b: int = edge[1]
		var va := vertices[a]
		var vb := vertices[b]
		var bottom := vertices.size()
		vertices.append(va + Vector3.DOWN * skirt)
		vertices.append(vb + Vector3.DOWN * skirt)
		var mid := (va + vb) * 0.5
		var outward := Vector3(mid.x - half, 0.0, mid.z - half)
		if outward.length_squared() < 1e-8:
			outward = Vector3.UP
		outward = outward.normalized()
		normals.append(outward)
		normals.append(outward)
		uvs.append(Vector2(va.x, va.z) / 16.0)
		uvs.append(Vector2(vb.x, vb.z) / 16.0)
		indices.append(a)
		indices.append(b)
		indices.append(bottom + 1)
		indices.append(a)
		indices.append(bottom + 1)
		indices.append(bottom)
	return [vertices, normals, uvs, indices]


static func _normal(heights: PackedFloat32Array, ext: int, x: int, y: int, step: float) -> Vector3:
	var west := heights[y * ext + (x - 1)]
	var east := heights[y * ext + (x + 1)]
	var north := heights[(y - 1) * ext + x]
	var south := heights[(y + 1) * ext + x]
	return Vector3(west - east, 2.0 * step, north - south).normalized()


## Malha quadrada usada pelo protótipo de chão liso e pelos testes visuais.
static func build_flat(size: float, divisions: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var step := size / float(divisions)
	for iy in range(divisions + 1):
		for ix in range(divisions + 1):
			vertices.append(Vector3(float(ix) * step, 0.0, float(iy) * step))
			normals.append(Vector3.UP)
	for iy in range(divisions):
		for ix in range(divisions):
			var i0 := iy * (divisions + 1) + ix
			var i1 := i0 + 1
			var i2 := i0 + divisions + 1
			var i3 := i2 + 1
			indices.append(i0)
			indices.append(i2)
			indices.append(i1)
			indices.append(i1)
			indices.append(i2)
			indices.append(i3)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
