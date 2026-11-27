class_name CariocaBus
extends RefCounted

## Barramento de eventos do CARIOCA.
##
## Regra de arquitetura: nenhum sistema conhece os detalhes internos de outro.
## Quem carrega um setor publica `sector_loaded`; quem precisa saber escuta.
## Também sem autoload: sobrevive a testes headless e a recarregamentos de cena.

signal world_started()
signal sector_loaded(coord: Vector2i)
signal sector_unloaded(coord: Vector2i)
signal streaming_busy(count: int)
signal world_rebased(offset: Vector3)
signal clock_changed(hours: float)
signal weather_changed(kind: String)
signal vehicle_entered(vehicle: Node3D)
signal vehicle_exited(vehicle: Node3D)
signal interior_entered(interior_id: String)
signal interior_exited()
signal prompt_changed(text: String)
signal save_finished(slot: int, ok: bool)
signal quality_applied(preset: String)
signal teleported(event: String)

static var _instance: CariocaBus = null


static func get_instance() -> CariocaBus:
	if _instance == null:
		_instance = CariocaBus.new()
	return _instance


## Os testes recriam o barramento para não herdarem conexões de execuções
## anteriores no mesmo processo.
static func reset_for_tests() -> CariocaBus:
	_instance = CariocaBus.new()
	return _instance
