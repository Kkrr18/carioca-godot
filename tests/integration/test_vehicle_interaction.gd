extends TestCase

## Entrada e saída do veículo, do jeito que o jogo faz — sem mundo montado.
##
## O que cabe aqui: sentar no banco do motorista (e não em cima do teto), a
## troca de alvo e de modo da câmera, o bloqueio de segunda entrada, a saída
## pelo lado livre e os sinais no barramento. A dirigibilidade em si tem mundo
## próprio: `test_drive_model` e `test_vehicle_world`.

const DT := 1.0 / 60.0


func _make_pair() -> Dictionary:
	CariocaBus.reset_for_tests()
	var player := Player.new()
	player.name = "Player"
	tree.root.add_child(player)
	var vehicle := Vehicle.new()
	vehicle.name = "Vehicle"
	tree.root.add_child(vehicle)
	var camera := VehicleCamera.new()
	camera.name = "Camera"
	tree.root.add_child(camera)
	camera.set_target(player)
	player.camera_rig = camera
	return {
		"player": player,
		"vehicle": vehicle,
		"camera": camera,
	}


func _dispose(pair: Dictionary) -> void:
	(pair["camera"] as Node).free()
	(pair["vehicle"] as Node).free()
	(pair["player"] as Node).free()


func test_enter_seats_the_driver() -> void:
	var pair := _make_pair()
	var player: Player = pair["player"]
	var vehicle: Vehicle = pair["vehicle"]
	player.enter_vehicle(vehicle)
	assert_eq(vehicle.driver, player, "o carro reconhece o motorista")
	assert_eq(player.current_vehicle, vehicle, "o jogador reconhece o carro")
	assert_false(player.visible, "a pé, o corpo some de dentro do carro")
	assert_false(player.can_move, "o controlador a pé desliga")
	player.step_physics(DT, Vector2.ZERO)
	var seat := vehicle.global_position + vehicle.global_transform.basis * Player.DRIVER_SEAT_OFFSET
	assert_true(player.global_position.distance_to(seat) < 0.01, "o motorista senta no banco, não sobre o teto")
	_dispose(pair)


func test_enter_swaps_the_camera_to_the_vehicle_mode() -> void:
	var pair := _make_pair()
	var player: Player = pair["player"]
	var vehicle: Vehicle = pair["vehicle"]
	var camera: VehicleCamera = pair["camera"]
	camera.set_target(player)
	player.enter_vehicle(vehicle)
	assert_eq(camera.target, vehicle, "a câmera passa a seguir o carro")
	assert_almost_eq(camera.height_offset, VehicleCamera.VEHICLE_HEIGHT, 1e-6, "modo veicular eleva o pivô")
	player.exit_vehicle()
	assert_eq(camera.target, player, "saindo, a câmera volta ao personagem")
	assert_almost_eq(camera.height_offset, 1.55, 1e-6, "saindo, o pivô volta à altura a pé")
	_dispose(pair)


func test_entering_twice_is_ignored() -> void:
	var pair := _make_pair()
	var player: Player = pair["player"]
	var vehicle: Vehicle = pair["vehicle"]
	player.enter_vehicle(vehicle)
	var other := Vehicle.new()
	other.name = "Other"
	tree.root.add_child(other)
	player.enter_vehicle(other)
	assert_eq(player.current_vehicle, vehicle, "dirigindo, o segundo carro não entra")
	assert_eq(other.driver, null, "o segundo carro continua vazio")
	other.free()
	_dispose(pair)


func test_exit_releases_control_and_signals() -> void:
	CariocaBus.reset_for_tests()
	var pair := _make_pair()
	var player: Player = pair["player"]
	var vehicle: Vehicle = pair["vehicle"]
	var entered: Array = []
	var exited: Array = []
	player.entered_vehicle.connect(func(v: Vehicle) -> void: entered.append(v))
	player.exited_vehicle.connect(func(v: Vehicle) -> void: exited.append(v))
	var bus_entered: Array = []
	var bus_exited: Array = []
	CariocaBus.get_instance().vehicle_entered.connect(func(v: Node3D) -> void: bus_entered.append(v))
	CariocaBus.get_instance().vehicle_exited.connect(func(v: Node3D) -> void: bus_exited.append(v))
	player.enter_vehicle(vehicle)
	player.exit_vehicle()
	assert_eq(vehicle.driver, null, "o carro fica sem motorista")
	assert_eq(player.current_vehicle, null, "o jogador fica sem carro")
	assert_true(player.visible, "a pé, o corpo volta")
	assert_true(player.can_move, "o controlador a pé volta")
	assert_eq(entered.size(), 1, "sinal de entrada")
	assert_eq(exited.size(), 1, "sinal de saída")
	assert_eq(bus_entered.size(), 1, "barramento recebe a entrada")
	assert_eq(bus_exited.size(), 1, "barramento recebe a saída")
	_dispose(pair)


func test_exit_places_the_player_beside_the_car() -> void:
	var pair := _make_pair()
	var player: Player = pair["player"]
	var vehicle: Vehicle = pair["vehicle"]
	player.enter_vehicle(vehicle)
	var right := vehicle.exit_position(1.0)
	var left := vehicle.exit_position(-1.0)
	player.exit_vehicle()
	var placed := player.global_position
	var near_right := placed.distance_to(right)
	var near_left := placed.distance_to(left)
	assert_true(minf(near_right, near_left) < 0.01, "o jogador sai ao lado do carro, em uma das portas")
	_dispose(pair)


func test_exit_side_prefers_the_side_closest_to_the_driver() -> void:
	var pair := _make_pair()
	var player: Player = pair["player"]
	var vehicle: Vehicle = pair["vehicle"]
	# Motorista 5 m à direita do carro (lado +X do corpo): nada bloqueia, e o
	# lado preferido é o da direita.
	player.global_position = vehicle.global_position + vehicle.global_transform.basis.x * 5.0
	assert_almost_eq(vehicle.best_exit_side(player.global_position), 1.0, 1e-9, "lado próximo vence")
	player.global_position = vehicle.global_position - vehicle.global_transform.basis.x * 5.0
	assert_almost_eq(vehicle.best_exit_side(player.global_position), -1.0, 1e-9, "do outro lado, o esquerdo vence")
	_dispose(pair)


func test_parked_vehicle_has_no_driver() -> void:
	var pair := _make_pair()
	var vehicle: Vehicle = pair["vehicle"]
	assert_eq(vehicle.driver, null, "carro novo não tem motorista")
	assert_true(vehicle.describe().contains("estacionado"), "a descrição diz que está estacionado")
	_dispose(pair)


func test_interaction_prompt_survives_the_drive_loop() -> void:
	var pair := _make_pair()
	var player: Player = pair["player"]
	var vehicle: Vehicle = pair["vehicle"]
	player.enter_vehicle(vehicle)
	for _i in range(10):
		player.step_physics(DT, Vector2(0.3, 0.8))
	assert_eq(player.state_name(), "no veículo", "dirigindo, o estado é o de veículo")
	player.exit_vehicle()
	assert_true(player.state_name() != "no veículo", "sair devolve os estados a pé")
	_dispose(pair)
