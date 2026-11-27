extends SceneTree

## Executor de testes do CARIOCA.
##
##   godot --headless --script res://tests/run_tests.gd
##
## Descobre todo método `test_*` de cada classe de teste, roda em ordem e sai com
## código 1 se algo falhar — pronto para integração contínua.

const TEST_SCRIPTS: Array[String] = [
	"res://tests/unit/test_projection.gd",
	"res://tests/unit/test_sector_grid.gd",
	"res://tests/unit/test_detail_grid.gd",
	"res://tests/unit/test_world_grid_config.gd",
	"res://tests/unit/test_municipality_index.gd",
	"res://tests/unit/test_deterministic.gd",
	"res://tests/unit/test_terrain.gd",
	"res://tests/unit/test_road_mesh_builder.gd",
	"res://tests/unit/test_lod_profile.gd",
	"res://tests/unit/test_sector_lod_controller.gd",
	"res://tests/unit/test_request_queue.gd",
	"res://tests/unit/test_payload_cache.gd",
	"res://tests/unit/test_memory_budget.gd",
	"res://tests/unit/test_load_retry_policy.gd",
	"res://tests/unit/test_city_generator.gd",
	"res://tests/unit/test_road_graph.gd",
	"res://tests/unit/test_save_system.gd",
	"res://tests/unit/test_polygon_utils.gd",
	"res://tests/unit/test_road_network.gd",
	"res://tests/unit/test_urban_block_builder.gd",
	"res://tests/unit/test_parcel_splitter.gd",
	"res://tests/unit/test_building_generator.gd",
	"res://tests/unit/test_urban_furniture.gd",
	"res://tests/unit/test_landmark_registry.gd",
	"res://tests/unit/test_street_framework.gd",
	"res://tests/unit/test_urban_generator.gd",
	"res://tests/unit/test_movement_state_machine.gd",
	"res://tests/unit/test_player_motor.gd",
	"res://tests/unit/test_character_animator.gd",
	"res://tests/unit/test_placeholder_character.gd",
	"res://tests/unit/test_player_interaction.gd",
	"res://tests/unit/test_input_bindings.gd",
	"res://tests/unit/test_player_camera.gd",
	"res://tests/unit/test_driving_profile.gd",
	"res://tests/unit/test_drive_model.gd",
	"res://tests/unit/test_vehicle_camera.gd",
	"res://tests/unit/test_vehicle_audio.gd",
	"res://tests/integration/test_floating_origin.gd",
	"res://tests/integration/test_sector_instance.gd",
	"res://tests/integration/test_streaming_manager.gd",
	"res://tests/integration/test_streaming_soak.gd",
	"res://tests/integration/test_urban_sector.gd",
	"res://tests/integration/test_urban_streaming.gd",
	"res://tests/integration/test_player_world.gd",
	"res://tests/integration/test_vehicle_interaction.gd",
	"res://tests/integration/test_vehicle_world.gd",
]


func _initialize() -> void:
	print("")
	print("=== CARIOCA — suíte de testes ===")
	var started := Time.get_ticks_msec()
	var total_tests := 0
	var total_failures := 0
	var failing_files: Array[String] = []

	for path in TEST_SCRIPTS:
		var script = load(path)
		if script == null:
			print("  [ERRO] não foi possível carregar %s" % path)
			total_failures += 1
			failing_files.append(path)
			continue
		var instance = script.new()
		if not (instance is TestCase):
			print("  [ERRO] %s não estende TestCase" % path)
			total_failures += 1
			failing_files.append(path)
			continue

		var test_case: TestCase = instance
		test_case.set_context(self, path)
		var methods := _test_methods(test_case)
		var local_failures := 0
		for method_name in methods:
			test_case.call(method_name)
			var failures := test_case.take_failures()
			local_failures += failures.size()
			for failure in failures:
				print("  FALHOU  %s::%s\n          %s" % [path.get_file(), method_name, failure])
		total_tests += methods.size()
		total_failures += local_failures
		var status := "ok" if local_failures == 0 else "FALHOU"
		print("  %-34s %2d testes  %s" % [path.get_file(), methods.size(), status])
		if local_failures > 0:
			failing_files.append(path)

	var elapsed := Time.get_ticks_msec() - started
	print("")
	print("Testes: %d   falhas: %d   tempo: %d ms" % [total_tests, total_failures, elapsed])
	if total_failures == 0:
		print("TUDO PASSOU")
	else:
		print("FALHAS EM: %s" % ", ".join(failing_files))
	print("")
	quit(0 if total_failures == 0 else 1)


func _test_methods(test_case: TestCase) -> Array[String]:
	var names: Array[String] = []
	for entry in test_case.get_method_list():
		var method_name := str(entry.get("name", ""))
		if method_name.begins_with("test_") and not names.has(method_name):
			names.append(method_name)
	names.sort()
	return names
