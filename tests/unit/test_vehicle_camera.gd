extends TestCase

## Câmera veicular: modos, distâncias e a promessa de ser a mesma câmera.
##
## Sem consulta de física válida fora do mundo, o caminho de colisão devolve a
## distância pedida — o que se testa aqui é a regra dos modos, como no teste da
## câmera a pé.


func _camera() -> VehicleCamera:
	var holder := Node3D.new()
	tree.root.add_child(holder)
	var camera := VehicleCamera.new()
	holder.add_child(camera)
	return camera


func test_is_a_player_camera_subclass() -> void:
	var rig := _camera()
	assert_true(rig is PlayerCamera, "a câmera veicular é a câmera do personagem estendida")
	assert_not_null(rig.camera, "câmera 3D criada")
	rig.get_parent().free()


func test_vehicle_mode_changes_height_and_distance() -> void:
	var rig := _camera()
	var walk_height := rig.height_offset
	rig.enter_vehicle_mode()
	assert_almost_eq(rig.height_offset, VehicleCamera.VEHICLE_HEIGHT, 1e-6, "atrás do carro o pivô é mais alto")
	assert_true(rig.height_offset > walk_height, "modo carro olha de cima de modo a pé")
	rig.leave_vehicle_mode()
	assert_almost_eq(rig.height_offset, 1.55, 1e-6, "sair do carro devolve a altura de modo a pé")
	rig.get_parent().free()


func test_cycle_distance_toggles_near_and_far() -> void:
	var rig := _camera()
	rig.enter_vehicle_mode()
	var near_distance := rig.distance
	rig.cycle_distance()
	assert_eq(rig.mode, VehicleCamera.MODE_FAR, "primeira alternância vai para distante")
	assert_true(rig.distance > near_distance, "distante é mais longe")
	rig.cycle_distance()
	assert_eq(rig.mode, VehicleCamera.MODE_CHASE, "segunda alternância volta para perseguição")
	rig.get_parent().free()


func test_distance_respects_the_base_limits() -> void:
	var rig := _camera()
	rig.enter_vehicle_mode()
	rig.min_distance = 5.0
	rig.max_distance = 7.0
	rig.cycle_distance()
	assert_true(rig.distance <= 7.0, "a distância distante respeita o teto da câmera")
	rig.get_parent().free()


func test_vehicle_target_is_recognized() -> void:
	var rig := _camera()
	var bystander := Node3D.new()
	rig.get_parent().add_child(bystander)
	rig.set_target(bystander)
	assert_false(rig._is_vehicle_target(), "alvo a pé não é veículo")
	var vehicle := Vehicle.new()
	rig.get_parent().add_child(vehicle)
	rig.set_target(vehicle)
	assert_true(rig._is_vehicle_target(), "alvo do tipo Vehicle ativa o modo veicular")
	rig.set_target(bystander)
	assert_false(rig._is_vehicle_target(), "voltar ao personagem desativa o modo veicular")
	rig.get_parent().free()


func test_describe_names_the_mode() -> void:
	var rig := _camera()
	assert_true(rig.describe().contains("perseguição"), "modo padrão é perseguição")
	rig.enter_vehicle_mode()
	rig.cycle_distance()
	assert_true(rig.describe().contains("distante"), "distante aparece na descrição")
	rig.get_parent().free()
