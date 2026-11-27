class_name SectorRepository
extends RefCounted

## Acesso aos dados de setor.
##
## A partir da Etapa 3 existe **um** caminho de carga, e ele é o `UrbanGenerator`:
##
##   1. se há arquivo gerado pelo importador (OpenStreetMap, curadoria manual),
##      ele é a base — geometria real tem prioridade;
##   2. se não há, a base é a geração procedural da Etapa 1;
##   3. sobre essa base, a camada urbana monta quadras, lotes, edificações,
##      vegetação e mobiliário (ou devolve a base intacta, no caso rural).
##
## Antes da Etapa 3 esta função só escolhia entre arquivo e procedimento. O que
## mudou não foi a prioridade das fontes — foi existir uma camada em cima delas.
##
## Tudo aqui é puro em relação ao estado do jogo: pode rodar nas threads de
## trabalho do streaming.

const DATA_ROOT := "res://data/geographic/sectors"


static func path_for(coord: Vector2i) -> String:
	var municipality := MunicipalityIndex.nearest(SectorGrid.sector_center(coord))
	var region := str(municipality.get("region", "METRO"))
	var code := str(municipality.get("code", "GERAL"))
	return DATA_ROOT.path_join(region).path_join(code).path_join(SectorGrid.key(coord) + ".json")


static func exists(coord: Vector2i) -> bool:
	return FileAccess.file_exists(path_for(coord))


## Carregador puro: pode rodar fora da thread principal.
static func load_payload(coord: Vector2i, seed_value: int = 20170) -> Dictionary:
	return UrbanGenerator.build_payload(coord, seed_value)


static func save_payload(coord: Vector2i, payload: Dictionary) -> bool:
	var path := path_for(coord)
	var directory := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		var err := DirAccess.make_dir_recursive_absolute(directory)
		if err != OK:
			push_error("SectorRepository: não foi possível criar %s" % directory)
			return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SectorRepository: não foi possível gravar %s" % path)
		return false
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	return true


static func delete_payload(coord: Vector2i) -> void:
	var path := path_for(coord)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Caminho relativo à raiz de dados, útil para relatórios das ferramentas.
static func relative_path_for(coord: Vector2i) -> String:
	var municipality := MunicipalityIndex.nearest(SectorGrid.sector_center(coord))
	return "%s/%s/%s.json" % [
		str(municipality.get("region", "METRO")),
		str(municipality.get("code", "GERAL")),
		SectorGrid.key(coord),
	]
