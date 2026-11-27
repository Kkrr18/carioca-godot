extends TestCase

## Animação: pose procedural derivada de estado e velocidade.
##
## O que se testa aqui é a **regra** da animação (fase, amplitude, resposta a
## pulo/queda/aterrissagem), não o desenho. Também se testa o contrato do gancho
## para animação importada: sem `AnimationTree` ligado, `is_bound()` é falso e
## nada finge estar animado por asset.

const DT := 1.0 / 60.0


func _animator() -> CharacterAnimator:
	return CharacterAnimator.new()


func test_starts_neutral() -> void:
	var animator := _animator()
	assert_almost_eq(float(animator.pose["leg_swing"]), 0.0, 1.0e-6, "pose inicial neutra")
	assert_almost_eq(float(animator.pose["squash"]), 1.0, 1.0e-6, "sem esmagamento inicial")
	assert_false(animator.is_bound(), "nenhuma animação importada ligada")


func test_idle_does_not_stride() -> void:
	var animator := _animator()
	for _i in range(60):
		animator.advance(DT, MovementStateMachine.State.IDLE, 0.0, 0.0, 0.0)
	assert_almost_eq(animator.stride_phase, 0.0, 1.0e-6, "parado não avança a passada")
	assert_true(absf(float(animator.pose["bob"])) > 0.0, "parado ainda respira")


func test_walking_advances_the_stride() -> void:
	var animator := _animator()
	for _i in range(60):
		animator.advance(DT, MovementStateMachine.State.RUN, 6.0, 0.0, 0.0)
	assert_greater(animator.stride_phase, 0.5, "correr avança a fase da passada")


func test_amplitude_grows_with_speed() -> void:
	var slow := _animator()
	var fast := _animator()
	var slow_peak := 0.0
	var fast_peak := 0.0
	for i in range(30):
		var a := slow.advance(DT, MovementStateMachine.State.WALK, 1.5, 0.0, 0.0)
		var b := fast.advance(DT, MovementStateMachine.State.SPRINT, 9.0, 0.0, 0.0)
		slow_peak = maxf(slow_peak, absf(float(a["leg_swing"])))
		fast_peak = maxf(fast_peak, absf(float(b["leg_swing"])))
	assert_greater(fast_peak, slow_peak, "mais velocidade, mais amplitude")
	assert_true(fast_peak <= 0.8, "amplitude tem teto")


func test_airborne_freezes_the_stride_and_tucks_the_legs() -> void:
	var animator := _animator()
	for _i in range(30):
		animator.advance(DT, MovementStateMachine.State.RUN, 6.0, 0.0, 0.0)
	var phase := animator.stride_phase
	for _i in range(30):
		animator.advance(DT, MovementStateMachine.State.FALL, 6.0, -8.0, 0.0)
	assert_almost_eq(animator.stride_phase, phase, 1.0e-6, "no ar a passada congela")
	assert_true(float(animator.pose["leg_swing"]) > 0.0, "pernas assumem a pose de queda")


func test_landing_squashes() -> void:
	var animator := _animator()
	var pose := animator.advance(DT, MovementStateMachine.State.LAND, 0.0, -8.0, 0.18)
	assert_true(float(pose["squash"]) < 1.0, "aterrissagem esmaga")
	assert_true(float(pose["crouch"]) > 0.0, "aterrissagem agacha")


func test_animation_names_follow_states() -> void:
	var animator := _animator()
	assert_eq(str(animator.animation_for(MovementStateMachine.State.IDLE)), "idle", "parado")
	assert_eq(str(animator.animation_for(MovementStateMachine.State.WALK)), "walk", "andando")
	assert_eq(str(animator.animation_for(MovementStateMachine.State.JUMP)), "jump", "pulo")
	assert_eq(str(animator.animation_for(MovementStateMachine.State.LAND)), "land", "aterrissagem")


func test_binding_without_assets_does_not_pretend() -> void:
	var animator := _animator()
	var player := AnimationPlayer.new()
	animator.bind_player(player)
	assert_true(animator.is_bound(), "vínculo registrado")
	assert_eq(animator.available_states().size(), 0, "nenhum estado importado disponível")
	# Avançar ligado a um player sem animação não pode explodir nem fingir.
	animator.advance(DT, MovementStateMachine.State.RUN, 6.0, 0.0, 0.0)
	assert_true(animator.is_bound(), "vínculo continua registrado")


func test_reset_returns_to_neutral() -> void:
	var animator := _animator()
	for _i in range(20):
		animator.advance(DT, MovementStateMachine.State.SPRINT, 9.0, 0.0, 0.0)
	animator.reset()
	assert_almost_eq(animator.stride_phase, 0.0, 1.0e-6, "fase zerada")
	assert_almost_eq(float(animator.pose["squash"]), 1.0, 1.0e-6, "esmagamento neutro")
