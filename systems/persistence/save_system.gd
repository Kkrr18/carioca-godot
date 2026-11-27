class_name SaveSystem
extends Node

## Persistência com versão, checksum e gravação atômica.
##
## O arquivo guarda o payload como TEXTO, e o checksum é calculado sobre esse
## texto — não sobre o dicionário re-serializado. Isso elimina a dependência da
## ordem das chaves e faz o checksum significar exatamente "estes bytes".
##
## Gravação atômica: escreve `.tmp`, faz flush e só então renomeia sobre o
## arquivo bom. Um desligamento no meio da gravação deixa o save anterior
## intacto em vez de um arquivo pela metade.

const SAVE_ROOT := "user://saves"
const SLOT_COUNT := 3

var last_error: String = ""


func slot_dir(slot: int) -> String:
	return SAVE_ROOT.path_join("slot_%02d" % slot)


func slot_path(slot: int) -> String:
	return slot_dir(slot).path_join("save.json")


func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func save(slot: int, payload: Dictionary) -> bool:
	last_error = ""
	var directory := slot_dir(slot)
	if not DirAccess.dir_exists_absolute(directory):
		var err := DirAccess.make_dir_recursive_absolute(directory)
		if err != OK:
			last_error = "não foi possível criar %s" % directory
			return false
	var body := payload.duplicate(true)
	body["save_version"] = WorldSchema.SAVE_FORMAT_VERSION
	body["saved_at"] = Time.get_datetime_string_from_system()
	var text := JSON.stringify(body, "  ")
	var envelope := {
		"version": WorldSchema.SAVE_FORMAT_VERSION,
		"checksum": _checksum(text),
		"payload": text,
	}
	var final_path := slot_path(slot)
	var temp_path := final_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		last_error = "não foi possível abrir %s" % temp_path
		return false
	file.store_string(JSON.stringify(envelope, "  "))
	file.flush()
	file.close()
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	var rename_error := DirAccess.rename_absolute(temp_path, final_path)
	if rename_error != OK:
		last_error = "falha ao renomear save (%d)" % rename_error
		return false
	last_error = ""
	return true


func load_slot(slot: int) -> Dictionary:
	last_error = ""
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		last_error = "slot %d vazio" % slot
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "não foi possível ler %s" % path
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		last_error = "save corrompido: JSON inválido"
		return {}
	var envelope: Dictionary = parsed
	var text := str(envelope.get("payload", ""))
	if _checksum(text) != str(envelope.get("checksum", "")):
		last_error = "save corrompido: checksum não confere"
		return {}
	var body = JSON.parse_string(text)
	if typeof(body) != TYPE_DICTIONARY:
		last_error = "save corrompido: payload inválido"
		return {}
	var payload: Dictionary = body
	var version := int(payload.get("save_version", 0))
	if version > WorldSchema.SAVE_FORMAT_VERSION:
		last_error = "save de versão mais nova (%d)" % version
		return {}
	if version < WorldSchema.SAVE_FORMAT_VERSION:
		payload = migrate(payload, version)
	return payload


func delete_slot(slot: int) -> void:
	var path := slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func metadata(slot: int) -> Dictionary:
	var payload := load_slot(slot)
	if payload.is_empty():
		return {}
	return {
		"slot": slot,
		"saved_at": str(payload.get("saved_at", "?")),
		"municipality": str(payload.get("municipality", "?")),
		"hours": float(payload.get("time_hours", 0.0)),
	}


## Migração de formato. Cada versão antiga ganha um passo explícito; nada de
## "tentar e ver no que dá" com save de jogador.
func migrate(payload: Dictionary, from_version: int) -> Dictionary:
	var migrated := payload.duplicate(true)
	var version := from_version
	while version < WorldSchema.SAVE_FORMAT_VERSION:
		match version:
			0:
				if not migrated.has("time_hours"):
					migrated["time_hours"] = 9.0
				if not migrated.has("weather"):
					migrated["weather"] = "clear"
				if not migrated.has("quality_preset"):
					migrated["quality_preset"] = "pc_medium"
			_:
				pass
		version += 1
	migrated["save_version"] = WorldSchema.SAVE_FORMAT_VERSION
	return migrated


func _checksum(text: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(text.to_utf8_buffer())
	return context.finish().hex_encode()


## Payload padrão do mundo. Quem monta é quem conhece os sistemas; o SaveSystem
## só grava e lê.
func build_payload(context: Dictionary) -> Dictionary:
	var payload := {
		"save_version": WorldSchema.SAVE_FORMAT_VERSION,
		"seed": int(context.get("seed", 20170)),
		"time_hours": float(context.get("time_hours", 9.0)),
		"weather": str(context.get("weather", "clear")),
		"quality_preset": str(context.get("quality_preset", "pc_medium")),
		"municipality": str(context.get("municipality", "GUAPI")),
		"position_metric": [
			float(context.get("metric", Vector2.ZERO).x),
			float(context.get("metric", Vector2.ZERO).y),
		],
		"vehicle": context.get("vehicle", {}),
		"flags": context.get("flags", {}),
	}
	return payload
