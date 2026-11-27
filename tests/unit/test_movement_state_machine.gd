extends TestCase

## Máquina de estados do personagem: função pura, sem física.

func _context(overrides: Dictionary = {}) -> Dictionary:
	var base := {
		"in_vehicle": false,
		"movement_enabled": true,
		"interact_timer": 0.0,
		"on_floor": true,
		"speed": 0.0,
		"vertical_velocity": 0.0,
		"landing_timer": 0.0,
		"turning": false,
		"sprinting": false,
		"idle_threshold": 0.32,
		"run_threshold": 4.8,
		"sprint_threshold": 7.6,
	}
	for key in overrides.keys():
		base[key] = overrides[key]
	return base


func test_ground_states_by_speed() -> void:
	assert_eq(MovementStateMachine.resolve(_context({"speed": 0.0})), MovementStateMachine.State.IDLE, "parado")
	assert_eq(MovementStateMachine.resolve(_context({"speed": 1.5})), MovementStateMachine.State.WALK, "andando")
	assert_eq(MovementStateMachine.resolve(_context({"speed": 6.0})), MovementStateMachine.State.RUN, "correndo")
	assert_eq(MovementStateMachine.resolve(_context({"speed": 9.0, "sprinting": true})), MovementStateMachine.State.SPRINT, "sprint")


func test_sprint_state_requires_the_modifier() -> void:
	assert_eq(MovementStateMachine.resolve(_context({"speed": 9.0, "sprinting": false})), MovementStateMachine.State.RUN, "velocidade alta sem modificador é corrida")


func test_air_states() -> void:
	assert_eq(MovementStateMachine.resolve(_context({"on_floor": false, "vertical_velocity": 3.0})), MovementStateMachine.State.JUMP, "subindo")
	assert_eq(MovementStateMachine.resolve(_context({"on_floor": false, "vertical_velocity": -3.0})), MovementStateMachine.State.FALL, "caindo")


func test_landing_has_priority_over_speed() -> void:
	assert_eq(MovementStateMachine.resolve(_context({"speed": 6.0, "landing_timer": 0.1})), MovementStateMachine.State.LAND, "aterrissagem antes de corrida")


func test_turn_only_when_slow() -> void:
	assert_eq(MovementStateMachine.resolve(_context({"speed": 1.0, "turning": true})), MovementStateMachine.State.TURN, "virando devagar")
	assert_eq(MovementStateMachine.resolve(_context({"speed": 6.0, "turning": true})), MovementStateMachine.State.RUN, "correndo não é virar")


func test_vehicle_and_disabled_override_everything() -> void:
	assert_eq(MovementStateMachine.resolve(_context({"in_vehicle": true, "speed": 9.0, "sprinting": true})), MovementStateMachine.State.VEHICLE, "veículo tem prioridade máxima")
	assert_eq(MovementStateMachine.resolve(_context({"movement_enabled": false, "speed": 6.0})), MovementStateMachine.State.DISABLED, "movimento desligado")


func test_interaction_window() -> void:
	var machine := MovementStateMachine.new()
	machine.notify_interaction()
	assert_eq(machine.update(1.0 / 60.0, _context({"speed": 0.0})), MovementStateMachine.State.INTERACT, "interação entra no estado")
	machine.update(0.4, _context({"speed": 0.0}))
	assert_eq(machine.state, MovementStateMachine.State.IDLE, "janela de interação termina")


func test_transitions_are_counted() -> void:
	var machine := MovementStateMachine.new()
	machine.update(1.0 / 60.0, _context({"speed": 0.0}))
	assert_eq(machine.transitions, 0, "começa em IDLE sem transição")
	machine.update(1.0 / 60.0, _context({"speed": 6.0}))
	assert_eq(machine.transitions, 1, "uma transição para corrida")
	assert_eq(machine.previous, MovementStateMachine.State.IDLE, "estado anterior guardado")
	machine.update(1.0 / 60.0, _context({"speed": 6.0}))
	assert_eq(machine.transitions, 1, "estado estável não conta transição")


func test_names_and_animation_mapping() -> void:
	assert_eq(MovementStateMachine.state_name(MovementStateMachine.State.SPRINT), "sprint", "nome do estado")
	assert_eq(str(MovementStateMachine.animation_name(MovementStateMachine.State.FALL)), "fall", "animação de queda")
	assert_true(MovementStateMachine.is_airborne(MovementStateMachine.State.JUMP), "pulo é aéreo")
	assert_false(MovementStateMachine.is_airborne(MovementStateMachine.State.LAND), "aterrissagem não é aérea")


func test_reset_returns_to_idle() -> void:
	var machine := MovementStateMachine.new()
	machine.update(1.0 / 60.0, _context({"speed": 9.0, "sprinting": true}))
	machine.reset()
	assert_eq(machine.state, MovementStateMachine.State.IDLE, "reset volta ao parado")
	assert_eq(machine.transitions, 0, "contador zerado")
