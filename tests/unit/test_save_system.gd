extends TestCase

## Save: ida e volta, checksum e migração. Um save corrompido não pode carregar
## pela metade nem estourar exceção.

const TEST_SLOT := 3


func test_save_and_load_round_trip() -> void:
	var system := SaveSystem.new()
	system.delete_slot(TEST_SLOT)
	var payload := system.build_payload({
		"seed": 20170,
		"time_hours": 14.5,
		"weather": "rain",
		"municipality": "GUAPI",
		"metric": Vector2(310000.0, 8010000.0),
	})
	assert_true(system.save(TEST_SLOT, payload), "gravação concluída")
	assert_true(system.has_slot(TEST_SLOT), "slot existe")

	var loaded := system.load_slot(TEST_SLOT)
	assert_true(not loaded.is_empty(), "carregou payload")
	assert_almost_eq(float(loaded.get("time_hours", 0.0)), 14.5, 1e-6, "hora preservada")
	assert_eq(str(loaded.get("weather", "")), "rain", "clima preservado")
	assert_eq(int(loaded.get("save_version", 0)), WorldSchema.SAVE_FORMAT_VERSION, "versão do formato")
	var metric: Array = loaded.get("position_metric", [])
	assert_array_size(metric, 2, "posição métrica preservada")
	system.delete_slot(TEST_SLOT)


func test_missing_slot_returns_empty() -> void:
	var system := SaveSystem.new()
	system.delete_slot(TEST_SLOT)
	var loaded := system.load_slot(TEST_SLOT)
	assert_true(loaded.is_empty(), "slot vazio devolve payload vazio")
	assert_true(not system.last_error.is_empty(), "erro descrito")


func test_corrupted_save_is_rejected() -> void:
	var system := SaveSystem.new()
	system.delete_slot(TEST_SLOT)
	var payload := system.build_payload({"time_hours": 8.0})
	assert_true(system.save(TEST_SLOT, payload), "gravação inicial")
	var path := system.slot_path(TEST_SLOT)
	var file := FileAccess.open(path, FileAccess.READ)
	var text := ""
	if file != null:
		text = file.get_as_text()
		file.close()
	# Corrompe o checksum do envelope, mantendo o JSON válido: o save precisa ser
	# recusado por integridade, não por erro de sintaxe.
	text = text.replace("\"checksum\": \"", "\"checksum\": \"00")
	var writer := FileAccess.open(path, FileAccess.WRITE)
	if writer != null:
		writer.store_string(text)
		writer.close()
	var loaded := system.load_slot(TEST_SLOT)
	assert_true(loaded.is_empty(), "save adulterado é recusado")
	assert_true(system.last_error.contains("checksum"), "motivo aponta o checksum")
	system.delete_slot(TEST_SLOT)


func test_migration_from_older_version() -> void:
	var system := SaveSystem.new()
	var old := {"save_version": 0, "seed": 20170}
	var migrated := system.migrate(old, 0)
	assert_eq(int(migrated.get("save_version", 0)), WorldSchema.SAVE_FORMAT_VERSION, "versão promovida")
	assert_true(migrated.has("time_hours"), "hora preenchida na migração")
	assert_true(migrated.has("weather"), "clima preenchido na migração")


func test_metadata_reports_slot() -> void:
	var system := SaveSystem.new()
	system.delete_slot(TEST_SLOT)
	var payload := system.build_payload({"municipality": "MAGE", "time_hours": 7.25})
	assert_true(system.save(TEST_SLOT, payload), "gravação")
	var metadata := system.metadata(TEST_SLOT)
	assert_eq(str(metadata.get("municipality", "")), "MAGE", "município no metadado")
	assert_almost_eq(float(metadata.get("hours", 0.0)), 7.25, 1e-6, "hora no metadado")
	system.delete_slot(TEST_SLOT)
