class_name TestCase
extends RefCounted

## Base dos testes. Sem framework externo: um arquivo de 40 linhas evita uma
## dependência de addon que precisaria ser instalada para rodar a suíte.

var tree: SceneTree = null
var source_path: String = ""

var _failures: Array[String] = []


func set_context(scene_tree: SceneTree, path: String) -> void:
	tree = scene_tree
	source_path = path


func take_failures() -> Array[String]:
	var result := _failures.duplicate()
	_failures.clear()
	return result


func fail(message: String) -> void:
	_failures.append(message)


func assert_true(condition: bool, message: String) -> void:
	if not condition:
		fail(message)


func assert_false(condition: bool, message: String) -> void:
	if condition:
		fail(message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		fail("%s — obtido: %s, esperado: %s" % [message, str(actual), str(expected)])


func assert_not_eq(actual: Variant, unexpected: Variant, message: String) -> void:
	if actual == unexpected:
		fail("%s — valor não deveria ser %s" % [message, str(unexpected)])


func assert_almost_eq(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		fail("%s — obtido %.12f, esperado %.12f (tolerância %.12f)" % [message, actual, expected, tolerance])


func assert_not_null(value: Variant, message: String) -> void:
	if value == null:
		fail(message)


func assert_greater(actual: float, minimum: float, message: String) -> void:
	if not (actual > minimum):
		fail("%s — obtido %.6f, esperado maior que %.6f" % [message, actual, minimum])


func assert_array_size(value: Array, expected: int, message: String) -> void:
	if value.size() != expected:
		fail("%s — tamanho %d, esperado %d" % [message, value.size(), expected])
