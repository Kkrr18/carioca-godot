extends TestCase

## Política de retentativa: espera cresce, teto de tentativas existe e depois do
## teto a espera vira quarentena longa.

func test_backoff_grows_linearly() -> void:
	var policy := LoadRetryPolicy.new()
	policy.base_delay_s = 2.0
	assert_almost_eq(policy.delay_for(0), 0.0, 1e-9, "sem falha, sem espera")
	assert_almost_eq(policy.delay_for(1), 2.0, 1e-9, "primeira espera é a base")
	assert_almost_eq(policy.delay_for(3), 6.0, 1e-9, "terceira espera é o triplo")


func test_retry_ceiling() -> void:
	var policy := LoadRetryPolicy.new()
	policy.max_attempts = 2
	assert_true(policy.can_retry(1), "primeira tentativa pode repetir")
	assert_true(policy.can_retry(2), "segunda tentativa pode repetir")
	assert_false(policy.can_retry(3), "acima do teto não repete")


func test_quarantine_after_ceiling() -> void:
	var policy := LoadRetryPolicy.new()
	policy.max_attempts = 3
	policy.quarantine_s = 60.0
	assert_greater(float(policy.delay_msec_for(4)), 30000.0, "quarentena longa depois do teto")
	assert_true(policy.delay_msec_for(1) < 10000, "espera curta nas primeiras tentativas")


func test_delay_is_monotonic() -> void:
	var policy := LoadRetryPolicy.new()
	var previous := -1
	for attempts in range(1, 5):
		var value := policy.delay_msec_for(attempts)
		assert_true(value > previous, "espera cresce na tentativa %d" % attempts)
		previous = value
