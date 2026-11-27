class_name SectorInstance
extends Node3D

## Um setor carregado: terreno com colisão, vias, prédios, vegetação e mobiliário.
##
## É a unidade de memória do jogo. Carregar = construir este nó; descarregar =
## liberar. Nada aqui guarda estado global, então qualquer ordem de carga e
## descarga produz o mesmo mundo.
##
## A partir da Etapa 2 o terreno é a única camada que troca de resolução em tempo
## de execução (`set_terrain_lod`). Vias, prédios, árvores e postes são
## construídos uma vez: reconstruí-los a cada troca de nível custaria mais que a
## economia de triângulos do terreno. Sobre eles, o nível só decide visibilidade
## (`apply_detail`), que é grátis.

var coord: Vector2i = Vector2i.ZERO
var payload: Dictionary = {}
var is_urban: bool = false
var density: float = 0.0
var build_microseconds: int = 0

## Nível de LOD aplicado hoje e resolução efetiva do terreno.
var lod_level: int = 0
var terrain_divisions: int = 0
var has_terrain_collision: bool = false

var terrain_ref: TerrainService = null

var _terrain_mesh: MeshInstance3D = null
var _terrain_body: StaticBody3D = null
var _roads_mesh: MeshInstance3D = null
var _buildings_mesh: MeshInstance3D = null
var _buildings_body: StaticBody3D = null
var _trees_mesh: MultiMeshInstance3D = null
var _lights_mesh: MultiMeshInstance3D = null
var _lamp_heads_mesh: MultiMeshInstance3D = null

## Camada urbana da Etapa 3. Só existe quando o payload traz `urban_v3`; nesse
## caso ela substitui os prédios, árvores e postes da Etapa 1, e as variáveis
## acima ficam nulas.
var _urban_buildings: MeshInstance3D = null
var _urban_pavement: MeshInstance3D = null
var _urban_vegetation: Array = []
var _urban_props: Array = []
var _urban_stats: Dictionary = {}


## Constrói o setor inteiro. Retorna o próprio nó para encadear chamadas.
## `skirt` e `with_collision` permitem já nascer no nível de LOD correto, em vez
## de nascer detalhado e encolher no frame seguinte.
func build(p_coord: Vector2i, p_payload: Dictionary, terrain: TerrainService, divisions: int, skirt: float = 0.0, with_collision: bool = true) -> SectorInstance:
	var started := Time.get_ticks_usec()
	coord = p_coord
	payload = p_payload
	terrain_ref = terrain
	density = float(payload.get("density", 0.0))
	is_urban = bool(payload.get("urban", false))
	name = "Sector_%d_%d" % [coord.x, coord.y]

	var origin_metric := SectorGrid.sector_origin(coord)
	_build_terrain(terrain, divisions, skirt, with_collision)
	_build_roads(terrain, origin_metric)
	if bool(payload.get("urban_v3", false)):
		_build_urban(terrain, origin_metric)
	else:
		_build_buildings()
		_build_trees(terrain, origin_metric)
		_build_props(terrain, origin_metric)

	build_microseconds = Time.get_ticks_usec() - started
	return self


func _build_terrain(terrain: TerrainService, divisions: int, skirt: float, with_collision: bool) -> void:
	var mesh := TerrainMeshBuilder.build(coord, divisions, terrain, skirt)
	var instance := MeshInstance3D.new()
	instance.name = "Terrain"
	instance.mesh = mesh
	instance.material_override = MaterialLibrary.terrain()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(instance)
	_terrain_mesh = instance
	terrain_divisions = divisions
	_apply_terrain_collision(with_collision)


## Troca a resolução do terreno deste setor, no lugar.
##
## Só a malha e a colisão do terreno são refeitas. Retorna falso quando o pedido
## é idêntico ao estado atual — o que evita reconstruir a malha à toa quando o
## perfil de qualidade e o controlador de LOD concordam.
func set_terrain_lod(divisions: int, with_collision: bool, skirt: float = 0.0) -> bool:
	if _terrain_mesh == null or terrain_ref == null:
		return false
	var wanted := maxi(divisions, 2)
	if wanted == terrain_divisions and with_collision == has_terrain_collision:
		return false
	_terrain_mesh.mesh = TerrainMeshBuilder.build(coord, wanted, terrain_ref, skirt)
	terrain_divisions = wanted
	_apply_terrain_collision(with_collision)
	return true


func _apply_terrain_collision(enabled: bool) -> void:
	if _terrain_body != null:
		# `free` e não `queue_free`: o corpo novo ocuparia o mesmo nome e a
		# colisão antiga continuaria existindo até o fim do frame.
		_terrain_body.free()
		_terrain_body = null
	has_terrain_collision = false
	if not enabled or _terrain_mesh == null or _terrain_mesh.mesh == null:
		return
	var body := StaticBody3D.new()
	body.name = "Collision"
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(_terrain_mesh.mesh.get_faces())
	shape.shape = concave
	body.add_child(shape)
	_terrain_mesh.add_child(body)
	_terrain_body = body
	has_terrain_collision = true


## Aplica o nível de detalhe às camadas que não valem reconstrução: esconde
## mobiliário e sombra nos setores distantes. Barato e reversível.
func apply_detail(level: int) -> void:
	lod_level = level
	var distant := level >= 2
	var far := level >= 3
	if _lights_mesh != null:
		_lights_mesh.visible = not distant
	if _lamp_heads_mesh != null:
		_lamp_heads_mesh.visible = not distant
	if _trees_mesh != null:
		_trees_mesh.visible = not far
	if _terrain_mesh != null:
		_terrain_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if distant else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Camada urbana: mobiliário de rua some antes da vegetação, prédio e calçada
	# nunca somem (a silhueta da cidade é o que se vê de longe).
	for instance in _urban_props:
		var node := instance as Node3D
		if node != null:
			node.visible = not distant
	for instance in _urban_vegetation:
		var node := instance as Node3D
		if node != null:
			node.visible = not far
	if _urban_buildings != null:
		_urban_buildings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if far else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _build_roads(terrain: TerrainService, origin_metric: Vector2) -> void:
	var roads: Array = payload.get("roads", [])
	if roads.is_empty():
		return
	var mesh := RoadMeshBuilder.build(roads, terrain, origin_metric)
	if mesh == null:
		return
	var instance := MeshInstance3D.new()
	instance.name = "Roads"
	instance.mesh = mesh
	instance.material_override = MaterialLibrary.road()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_roads_mesh = instance


func _build_buildings() -> void:
	var buildings: Array = payload.get("buildings", [])
	if buildings.is_empty():
		return
	var mesh := BuildingMeshBuilder.build(buildings)
	if mesh == null:
		return
	var instance := MeshInstance3D.new()
	instance.name = "Buildings"
	instance.mesh = mesh
	instance.material_override = MaterialLibrary.vertex_colored(0.78)
	add_child(instance)
	_buildings_mesh = instance

	var body := StaticBody3D.new()
	body.name = "BuildingBodies"
	body.set_meta("kind", "buildings")
	add_child(body)
	_buildings_body = body
	for raw in buildings:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var building: Dictionary = raw
		var size := _vec2(building.get("size", [10.0, 10.0]))
		var center := _vec2(building.get("center", [0.0, 0.0]))
		var height := float(building.get("height", 6.0))
		var angle := float(building.get("angle", 0.0))
		if size.x <= 0.5 or size.y <= 0.5:
			continue
		var shape := BoxShape3D.new()
		shape.size = Vector3(size.x, height, size.y)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = Vector3(center.x, height * 0.5 - 0.5, center.y)
		collision.rotation.y = -angle
		body.add_child(collision)


func _build_trees(terrain: TerrainService, origin_metric: Vector2) -> void:
	var trees: Array = payload.get("trees", [])
	if trees.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = ProceduralMeshes.tree_crown()
	multi.instance_count = trees.size()
	for i in range(trees.size()):
		var entry: Array = trees[i]
		var local := Vector2(float(entry[0]), float(entry[1]))
		var scale := float(entry[2]) if entry.size() > 2 else 1.0
		var metric := origin_metric + Vector2(local.x, -local.y)
		var height := terrain.height_at(metric)
		var basis := Basis(Vector3.UP, Deterministic.hash2(coord.x + i, coord.y, 3) % 628) * scale
		basis = basis.scaled(Vector3(1.0, 0.85 + scale * 0.3, 1.0))
		multi.set_instance_transform(i, Transform3D(basis, Vector3(local.x, height, local.y)))
		var green := 0.22 + Deterministic.rand01(coord.x + i, coord.y, 41) * 0.18
		multi.set_instance_color(i, Color(0.16 + green * 0.4, 0.30 + green, 0.14 + green * 0.3))
	var instance := MultiMeshInstance3D.new()
	instance.name = "Trees"
	instance.multimesh = multi
	instance.material_override = MaterialLibrary.foliage()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_trees_mesh = instance


func _build_props(terrain: TerrainService, origin_metric: Vector2) -> void:
	var props: Array = payload.get("props", [])
	if props.is_empty():
		return
	var pole_multi := MultiMesh.new()
	pole_multi.transform_format = MultiMesh.TRANSFORM_3D
	pole_multi.mesh = ProceduralMeshes.pole()
	pole_multi.instance_count = props.size()
	var head_multi := MultiMesh.new()
	head_multi.transform_format = MultiMesh.TRANSFORM_3D
	head_multi.mesh = ProceduralMeshes.street_light_head()
	head_multi.instance_count = props.size()
	var placed := 0
	for raw in props:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var prop: Dictionary = raw
		var local := _vec2(prop.get("pos", [0.0, 0.0]))
		var metric := origin_metric + Vector2(local.x, -local.y)
		var height := terrain.height_at(metric)
		var basis := Basis(Vector3.UP, float(prop.get("rot", 0.0)))
		pole_multi.set_instance_transform(placed, Transform3D(basis, Vector3(local.x, height + 3.2, local.y)))
		head_multi.set_instance_transform(placed, Transform3D(basis, Vector3(local.x, height + 6.35, local.y)))
		placed += 1
	pole_multi.instance_count = placed
	head_multi.instance_count = placed
	if placed == 0:
		return
	var instance := MultiMeshInstance3D.new()
	instance.name = "StreetLights"
	instance.multimesh = pole_multi
	instance.material_override = MaterialLibrary.prop()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_lights_mesh = instance

	var heads := MultiMeshInstance3D.new()
	heads.name = "LampHeads"
	heads.multimesh = head_multi
	heads.material_override = MaterialLibrary.street_lamps()
	heads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(heads)
	_lamp_heads_mesh = heads


# --- camada urbana (Etapa 3) -------------------------------------------------


## Constrói prédios com fachada, calçada, guia, faixas, vegetação e mobiliário.
##
## A ordem importa: colisão depois da malha (precisa do terreno), vegetação
## depois do mobiliário (ela desvia do que já existe) e mobilário depois de
## tudo, porque é a camada mais fina e a primeira a sumir com a distância.
func _build_urban(terrain: TerrainService, origin_metric: Vector2) -> void:
	var buildings_mesh := UrbanMeshBuilder.build_buildings(payload, terrain, origin_metric)
	if buildings_mesh != null:
		var instance := MeshInstance3D.new()
		instance.name = "UrbanBuildings"
		instance.mesh = buildings_mesh
		instance.material_override = MaterialLibrary.vertex_colored(0.82)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(instance)
		_urban_buildings = instance

	var pavement := UrbanMeshBuilder.build_pavement(payload, terrain, origin_metric)
	if pavement != null:
		var instance := MeshInstance3D.new()
		instance.name = "Pavement"
		instance.mesh = pavement
		instance.material_override = MaterialLibrary.vertex_colored(0.92)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		_urban_pavement = instance

	_build_urban_colliders(terrain, origin_metric)
	_build_urban_vegetation(terrain, origin_metric)
	_build_urban_props(terrain, origin_metric)
	_urban_stats = (payload.get("urban_stats", {}) as Dictionary).duplicate()


## Colisão da camada urbana: uma caixa por edificação e uma por trecho de muro.
##
## Caixa e não trimesh de propósito — é a mesma escolha da Etapa 1 e o motivo é o
## custo no iPhone 12: o `CharacterBody3D` e o trânsito consultam essa colisão a
## cada passo de física, e uma BVH da fachada inteira custaria mais que a cidade.
## Apoio no terreno é medido no centro, então a caixa acompanha a rua inclinada
## em vez de ficar no plano y = 0.
func _build_urban_colliders(terrain: TerrainService, origin_metric: Vector2) -> void:
	var buildings: Array = payload.get("buildings", [])
	if buildings.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "BuildingBodies"
	body.set_meta("kind", "buildings")
	add_child(body)
	_buildings_body = body
	for raw in buildings:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var building: Dictionary = raw
		var size := _vec2(building.get("size", [10.0, 10.0]))
		var center := _vec2(building.get("center", [0.0, 0.0]))
		var height := float(building.get("height", 6.0))
		var angle := float(building.get("angle", 0.0))
		if size.x <= 0.5 or size.y <= 0.5 or height <= 0.5:
			continue
		var shape := BoxShape3D.new()
		shape.size = Vector3(size.x, height, size.y)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = Vector3(center.x, _ground_at(terrain, origin_metric, center) + height * 0.5, center.y)
		collision.rotation.y = -angle
		body.add_child(collision)

		var wall: Dictionary = building.get("wall", {})
		var lot: Dictionary = building.get("lot", {})
		if wall.is_empty() or lot.is_empty():
			continue
		_add_wall_colliders(body, wall, lot, terrain, origin_metric)


func _add_wall_colliders(body: StaticBody3D, wall: Dictionary, lot: Dictionary, terrain: TerrainService, origin_metric: Vector2) -> void:
	var origin := _vec2(lot.get("origin", [0.0, 0.0]))
	var direction := _vec2(lot.get("dir", [1.0, 0.0]))
	var span := float(lot.get("width", 6.0))
	var height := float(wall.get("height", 1.8))
	var thickness := maxf(float(wall.get("thickness", 0.18)), 0.1)
	var gate_along := float(wall.get("gate_along", 1.0))
	var gate_width := float(wall.get("gate_width", 3.0))
	if span < 2.0 or height < 0.4:
		return
	var angle := atan2(direction.y, direction.x)
	var pieces: Array = [
		Vector2(0.0, gate_along),
		Vector2(gate_along + gate_width, span),
	]
	for piece in pieces:
		var limits: Vector2 = piece
		var length := limits.y - limits.x
		if length < 0.4:
			continue
		var middle := origin + direction * (limits.x + length * 0.5)
		var shape := BoxShape3D.new()
		shape.size = Vector3(length, height, thickness)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = Vector3(middle.x, _ground_at(terrain, origin_metric, middle) + height * 0.5, middle.y)
		collision.rotation.y = -angle
		body.add_child(collision)


func _build_urban_vegetation(terrain: TerrainService, origin_metric: Vector2) -> void:
	var vegetation: Dictionary = payload.get("vegetation", {})
	if vegetation.is_empty():
		return
	var definitions: Array = [
		{
			"species": UrbanSchema.SPECIES_TREE,
			"entries": vegetation.get("trees", []),
			"mesh": ProceduralMeshes.tree_crown_grounded(),
			"material": MaterialLibrary.foliage(),
			"shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		},
		{
			"species": UrbanSchema.SPECIES_TREE_TALL,
			"entries": vegetation.get("trees", []),
			"mesh": ProceduralMeshes.tree_crown_tall(),
			"material": MaterialLibrary.foliage(),
			"shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		},
		{
			"species": UrbanSchema.SPECIES_BUSH,
			"entries": vegetation.get("bushes", []),
			"mesh": ProceduralMeshes.bush(),
			"material": MaterialLibrary.foliage(),
			"shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		},
		{
			"species": UrbanSchema.SPECIES_GRASS,
			"entries": vegetation.get("grass", []),
			"mesh": ProceduralMeshes.grass_tuft(),
			"material": MaterialLibrary.foliage(),
			"shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		},
	]
	for definition in definitions:
		var data: Dictionary = definition
		var wanted := int(data["species"])
		var entries: Array = []
		for raw in data["entries"]:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = raw
			if int(entry.get("species", 0)) != wanted:
				continue
			entries.append(entry)
		if entries.is_empty():
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = data["mesh"]
		multi.instance_count = entries.size()
		for i in range(entries.size()):
			var entry: Dictionary = entries[i]
			var local := _vec2(entry.get("pos", [0.0, 0.0]))
			var scale := float(entry.get("scale", 1.0))
			var ground := _ground_at(terrain, origin_metric, local)
			var basis := Basis(Vector3.UP, float(entry.get("rot", 0.0))).scaled(Vector3(scale, scale, scale))
			multi.set_instance_transform(i, Transform3D(basis, Vector3(local.x, ground, local.y)))
			var tint := Deterministic.rand01(coord.x + i, coord.y + wanted, 61)
			multi.set_instance_color(i, Color(0.20 + tint * 0.16, 0.30 + tint * 0.22, 0.16 + tint * 0.12))
		var instance := MultiMeshInstance3D.new()
		instance.name = "Vegetation_%d" % wanted
		instance.multimesh = multi
		instance.material_override = data["material"]
		instance.cast_shadow = data["shadow"]
		add_child(instance)
		_urban_vegetation.append(instance)


func _build_urban_props(terrain: TerrainService, origin_metric: Vector2) -> void:
	var objects: Dictionary = payload.get("street_objects", {})
	if objects.is_empty():
		return
	# Cada tipo vira um MultiMesh por malha. Poste é o único com duas peças
	# (mastro e luminária); os demais são uma só, com a base em y = 0.
	var groups := {
		UrbanSchema.PROP_LIGHT: [
			{"mesh": ProceduralMeshes.pole(), "offset": 3.2, "material": MaterialLibrary.prop()},
			{"mesh": ProceduralMeshes.street_light_head(), "offset": 6.35, "material": MaterialLibrary.street_lamps()},
		],
		UrbanSchema.PROP_TRAFFIC_LIGHT: [
			{"mesh": ProceduralMeshes.traffic_signal(), "offset": 0.0, "material": MaterialLibrary.prop()},
		],
		UrbanSchema.PROP_SIGN: [
			{"mesh": ProceduralMeshes.street_sign(), "offset": 0.0, "material": MaterialLibrary.prop()},
		],
		UrbanSchema.PROP_BIN: [
			{"mesh": ProceduralMeshes.trash_bin(), "offset": 0.0, "material": MaterialLibrary.prop()},
		],
		UrbanSchema.PROP_BENCH: [
			{"mesh": ProceduralMeshes.bench(), "offset": 0.0, "material": MaterialLibrary.prop()},
		],
		UrbanSchema.PROP_SHELTER: [
			{"mesh": ProceduralMeshes.bus_shelter(), "offset": 0.0, "material": MaterialLibrary.prop()},
		],
		UrbanSchema.PROP_UTILITY_BOX: [
			{"mesh": ProceduralMeshes.utility_box(), "offset": 0.0, "material": MaterialLibrary.prop()},
		],
	}
	for type in groups.keys():
		var entries: Array = objects.get(type, [])
		if entries.is_empty():
			continue
		for layer in groups[type]:
			var definition: Dictionary = layer
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = definition["mesh"]
			multi.instance_count = entries.size()
			for i in range(entries.size()):
				var entry: Dictionary = entries[i]
				var local := _vec2(entry.get("pos", [0.0, 0.0]))
				var ground := _ground_at(terrain, origin_metric, local)
				var scale := float(entry.get("scale", 1.0))
				var basis := Basis(Vector3.UP, float(entry.get("rot", 0.0))).scaled(Vector3(scale, scale, scale))
				multi.set_instance_transform(i, Transform3D(basis, Vector3(local.x, ground + float(definition["offset"]), local.y)))
			var instance := MultiMeshInstance3D.new()
			instance.name = "StreetProps_%s" % str(type)
			instance.multimesh = multi
			instance.material_override = definition["material"]
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(instance)
			_urban_props.append(instance)


func _ground_at(terrain: TerrainService, origin_metric: Vector2, local: Vector2) -> float:
	if terrain == null:
		return 0.0
	return terrain.height_at(origin_metric + Vector2(local.x, -local.y))


## Números da camada urbana deste setor, para HUD, depuração e testes.
func urban_stats() -> Dictionary:
	return _urban_stats


func urban_buildings() -> int:
	return (payload.get("buildings", []) as Array).size()


func urban_blocks() -> int:
	return (payload.get("blocks", []) as Array).size()


func urban_parcels() -> int:
	return (payload.get("parcels", []) as Array).size()


func is_urban_layer() -> bool:
	return bool(payload.get("urban_v3", false))


func _vec2(value: Variant) -> Vector2:
	if typeof(value) == TYPE_ARRAY:
		var array: Array = value
		if array.size() >= 2:
			return Vector2(float(array[0]), float(array[1]))
	return Vector2.ZERO


## Portas de interior presentes neste setor, em espaço métrico global.
## O InteriorManager usa isso para saber onde o jogador pode entrar.
func door_positions(origin_metric: Vector2) -> Array:
	var out: Array = []
	for raw in payload.get("buildings", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var building: Dictionary = raw
		if not building.has("door"):
			continue
		var door := _vec2(building["door"])
		out.append({
			"metric": origin_metric + Vector2(door.x, -door.y),
			"building_id": str(building.get("id", "?")),
			"kind": str(building.get("kind", "residential")),
			"levels": int(building.get("levels", 1)),
		})
	return out


## Estimativa de memória do setor, em KB.
##
## Conta os arrays que o motor realmente guarda — vértices, normais, UVs, cores e
## índices de cada superfície, mais as instâncias de MultiMesh. Não é medidor de
## alocador: é uma unidade estável para o orçamento comparar setores entre si.
func memory_estimate_kb() -> float:
	var bytes := 0.0
	for child in get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh != null:
			bytes += _mesh_bytes(mesh_instance.mesh)
			continue
		var multi := child as MultiMeshInstance3D
		if multi != null and multi.multimesh != null:
			# 12 floats de transformação (48 B) + 4 de cor (16 B) por instância.
			bytes += float(multi.multimesh.instance_count) * 64.0
	return bytes / 1024.0


static func _mesh_bytes(mesh: Mesh) -> float:
	var bytes := 0.0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
		if typeof(vertices) == TYPE_PACKED_VECTOR3_ARRAY:
			bytes += float((vertices as PackedVector3Array).size()) * 12.0
		var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
		if typeof(normals) == TYPE_PACKED_VECTOR3_ARRAY:
			bytes += float((normals as PackedVector3Array).size()) * 12.0
		var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		if typeof(uvs) == TYPE_PACKED_VECTOR2_ARRAY:
			bytes += float((uvs as PackedVector2Array).size()) * 8.0
		var colors: Variant = arrays[Mesh.ARRAY_COLOR]
		if typeof(colors) == TYPE_PACKED_COLOR_ARRAY:
			bytes += float((colors as PackedColorArray).size()) * 16.0
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if typeof(indices) == TYPE_PACKED_INT32_ARRAY:
			bytes += float((indices as PackedInt32Array).size()) * 4.0
	return bytes


## Sai da árvore imediatamente e libera a memória.
##
## Dentro da árvore, `queue_free` é o caminho seguro do motor. Fora dela — nos
## testes headless, que não têm laço de frame para drenar a fila de exclusão —
## o nó é liberado na hora, senão uma sessão de teste longa acumularia centenas
## de setores vivos.
func release() -> void:
	var was_inside_tree := is_inside_tree()
	var parent := get_parent()
	if parent != null:
		parent.remove_child(self)
	if was_inside_tree:
		queue_free()
	else:
		free()
