extends TestCase

## Integração: montar um setor de verdade, com terreno, colisão, vias e prédios.
## Roda headless porque a física da Godot funciona sem janela.

func _coord(offset: int = 0) -> Vector2i:
	MunicipalityIndex.ensure_loaded()
	var base := SectorGrid.sector_of(MunicipalityIndex.center_of("GUAPI"))
	return Vector2i(base.x + offset, base.y)


func test_sector_instance_builds_all_layers() -> void:
	var terrain := TerrainService.new(20170)
	var coord := _coord()
	var payload := CityGenerator.build_payload(coord, 20170)
	var instance := SectorInstance.new()
	instance.build(coord, payload, terrain, 8)

	assert_eq(instance.coord, coord, "coordenada registrada")
	assert_greater(float(instance.build_microseconds), 0.0, "tempo de construção medido")
	assert_greater(float(instance.get_child_count()), 0.0, "nós criados")
	assert_not_null(instance.get_node_or_null("Terrain"), "terreno construído")
	assert_true(instance.is_urban, "setor urbano reconhecido")

	var doors := instance.door_positions(SectorGrid.sector_origin(coord))
	assert_greater(float(doors.size()), 0.0, "portas de interior disponíveis")
	if doors.size() > 0:
		var door: Dictionary = doors[0]
		assert_true(door.has("metric"), "porta com posição métrica")
		assert_true(door.has("building_id"), "porta com identificação da edificação")

	instance.free()


func test_collision_was_created() -> void:
	var terrain := TerrainService.new(20170)
	var coord := _coord(1)
	var payload := CityGenerator.build_payload(coord, 20170)
	var instance := SectorInstance.new()
	instance.build(coord, payload, terrain, 6)
	var terrain_node := instance.get_node_or_null("Terrain")
	assert_not_null(terrain_node, "nó do terreno")
	if terrain_node != null:
		var has_static := false
		for child in terrain_node.get_children():
			if child is StaticBody3D:
				has_static = true
		assert_true(has_static, "corpo estático de colisão criado para o terreno")
	instance.free()
