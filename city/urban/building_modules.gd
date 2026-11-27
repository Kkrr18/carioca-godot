class_name BuildingModules
extends RefCounted

## Módulos reutilizáveis de fachada: parede, porta, janela, telhado, sacada,
## garagem, varanda, escada, vitrine. Aqui eles são **dados**, não malha.
##
## A separação é deliberada. O planejamento de módulo decide o que existe e onde;
## o `UrbanMeshBuilder` decide como isso vira triângulo. Assim dá para testar a
## composição da fachada sem GPU, sem árvore de cena e sem frame — e uma mudança
## de estilo não arrisca a geometria.
##
## Referencial do prédio: (u, n) do lote, com a origem na quina esquerda da
## frente. A frente é a aresta n = 0; n cresce para dentro do lote.
##
##   lado 0  frente    começa em (u=0, n=0)   segue +u   (comprimento = largura)
##   lado 1  direita   começa em (u=largura, n=0)  segue +n   (comprimento = prof.)
##   lado 2  fundos    começa em (u=largura, n=prof.) segue -u
##   lado 3  esquerda  começa em (u=0, n=prof.)  segue -n
##
## `along` é medido a partir do início do lado, no sentido do percurso acima. O
## construtor de malha usa exatamente a mesma convenção.

const WINDOW_SPACING := 3.1
const MIN_WINDOW_GAP := 1.4


## Plano de módulos de uma edificação.
## `building`: { "width", "depth", "levels", "typology", "kind", "floor_height", "detail" }
static func plan(building: Dictionary, config: UrbanConfig, salt: int) -> Array:
	var modules: Array = []
	var width := float(building.get("width", 10.0))
	var depth := float(building.get("depth", 10.0))
	var levels := maxi(int(building.get("levels", 1)), 1)
	var floor_height := float(building.get("floor_height", config.floor_height))
	var typology := str(building.get("typology", UrbanSchema.TYPOLOGY_HOUSE_GROUND))
	var kind := str(building.get("kind", UrbanSchema.KIND_RESIDENTIAL))
	if width < 3.0 or depth < 3.0:
		return modules
	if config.detail <= 0:
		return modules

	var door_along := _door_position(width, salt)
	modules.append({
		"type": UrbanSchema.MODULE_DOOR,
		"side": UrbanSchema.SIDE_FRONT,
		"along": door_along,
		"width": 1.05,
		"height": 2.15,
		"sill": 0.0,
		"floor": 0,
	})

	# Térreo comercial: vitrine ocupa o lugar das janelas.
	var commercial_ground := kind != UrbanSchema.KIND_RESIDENTIAL and config.detail >= 2
	if commercial_ground:
		modules.append({
			"type": UrbanSchema.MODULE_SHOPFRONT,
			"side": UrbanSchema.SIDE_FRONT,
			"along": 0.0,
			"width": width,
			"height": minf(floor_height - 0.5, 3.3),
			"sill": 0.12,
			"floor": 0,
			"category": str(building.get("category", UrbanSchema.CATEGORY_SMALL)),
			"awning": config.detail >= 2,
		})
	else:
		_append_windows(modules, width, 0, 0, floor_height, salt, 3)

	if typology == UrbanSchema.TYPOLOGY_HOUSE_GARAGE and config.detail >= 2:
		modules.append({
			"type": UrbanSchema.MODULE_GARAGE,
			"side": UrbanSchema.SIDE_FRONT,
			"along": clampf(width - 3.4, 0.0, maxf(width - 3.2, 0.0)),
			"width": minf(3.0, maxf(width * 0.34, 2.4)),
			"height": 2.3,
			"sill": 0.0,
			"floor": 0,
		})

	if typology == UrbanSchema.TYPOLOGY_HOUSE_PORCH and config.detail >= 2:
		modules.append({
			"type": UrbanSchema.MODULE_PORCH,
			"side": UrbanSchema.SIDE_FRONT,
			"along": clampf(door_along - 2.1, 0.0, maxf(width - 4.4, 0.0)),
			"width": minf(4.2, width),
			"depth": 2.0,
			"height": 2.7,
			"sill": 0.0,
			"floor": 0,
		})

	if typology != UrbanSchema.TYPOLOGY_HOUSE_GROUND and config.detail >= 2:
		modules.append({
			"type": UrbanSchema.MODULE_STAIRS,
			"side": UrbanSchema.SIDE_FRONT,
			"along": door_along,
			"width": 1.7,
			"height": 0.36,
			"sill": -0.36,
			"floor": 0,
		})

	for floor in range(1, levels):
		var sill := float(floor) * floor_height + 0.95
		var is_building := (
			typology == UrbanSchema.TYPOLOGY_RESIDENTIAL_BUILDING
			or typology == UrbanSchema.TYPOLOGY_COMMERCIAL_BUILDING
			or typology == UrbanSchema.TYPOLOGY_MIXED_BUILDING
		)
		if is_building and config.detail >= 2:
			modules.append({
				"type": UrbanSchema.MODULE_BALCONY,
				"side": UrbanSchema.SIDE_FRONT,
				"along": clampf(width * 0.5 - 2.2, 0.0, maxf(width - 4.4, 0.0)),
				"width": minf(4.4, width * 0.7),
				"depth": 1.15,
				"height": 1.05,
				"sill": sill - 0.95,
				"floor": floor,
			})
		_append_windows(modules, width, floor, int(floor) * int(floor_height), floor_height, salt, 0)

	if config.detail >= 2:
		_append_side_windows(modules, depth, levels, floor_height, salt)

	return modules


static func _door_position(width: float, salt: int) -> float:
	var roll := Deterministic.rand01(salt, 3, 17)
	var along := lerpf(width * 0.25, width * 0.75, roll)
	return clampf(along, 1.2, maxf(width - 1.6, 1.2))


static func _append_windows(modules: Array, width: float, floor: int, base: int, floor_height: float, salt: int, skip: int) -> void:
	var usable := width - 1.6
	if usable < 2.0:
		return
	var count := maxi(1, int(usable / WINDOW_SPACING))
	if count > 6:
		count = 6
	var span := usable / float(count)
	for i in range(count):
		if i < skip:
			continue
		var window_width := clampf(span * 0.55, 0.75, 1.6)
		var window_height := clampf(floor_height * 0.44, 1.0, 1.7)
		var along := 0.8 + span * (float(i) + 0.5)
		if along - window_width * 0.5 < 0.5:
			continue
		modules.append({
			"type": UrbanSchema.MODULE_WINDOW,
			"side": UrbanSchema.SIDE_FRONT,
			"along": along,
			"width": window_width,
			"height": window_height,
			"sill": float(base) + (floor_height - window_height) * 0.55,
			"floor": floor,
		})


static func _append_side_windows(modules: Array, depth: float, levels: int, floor_height: float, salt: int) -> void:
	if depth < 6.0:
		return
	var count := clampi(int(depth / 3.6), 1, 3)
	var span := depth / float(count)
	for floor in range(levels):
		for i in range(count):
			var side := UrbanSchema.SIDE_RIGHT if (i + floor) % 2 == 0 else UrbanSchema.SIDE_LEFT
			modules.append({
				"type": UrbanSchema.MODULE_WINDOW,
				"side": side,
				"along": span * (float(i) + 0.5),
				"width": 0.9,
				"height": 1.15,
				"sill": float(floor) * floor_height + 1.15,
				"floor": floor,
			})


## Paleta da edificação. Cores vêm daqui e não do construtor de malha: mudar
## paleta não pode exigir recompilar geometria, e o payload guarda a cor final.
static func palette_for(typology: String, kind: String, salt: int, seed_value: int) -> Dictionary:
	var roll := Deterministic.rand01(salt, 5, seed_value + 41)
	var roll2 := Deterministic.rand01(salt, 9, seed_value + 43)
	var wall := Color(0.86, 0.83, 0.76)
	match typology:
		UrbanSchema.TYPOLOGY_HOUSE_GROUND, UrbanSchema.TYPOLOGY_HOUSE_GARAGE:
			wall = Color(0.88, 0.85, 0.78).lerp(Color(0.78, 0.66, 0.55), roll)
		UrbanSchema.TYPOLOGY_HOUSE_TWO_STOREY, UrbanSchema.TYPOLOGY_HOUSE_PORCH:
			wall = Color(0.90, 0.88, 0.83).lerp(Color(0.72, 0.62, 0.54), roll)
		UrbanSchema.TYPOLOGY_RESIDENTIAL_BUILDING:
			wall = Color(0.85, 0.84, 0.81).lerp(Color(0.66, 0.68, 0.70), roll)
		UrbanSchema.TYPOLOGY_COMMERCIAL_BUILDING:
			wall = Color(0.80, 0.81, 0.83).lerp(Color(0.58, 0.62, 0.68), roll)
		UrbanSchema.TYPOLOGY_MIXED_BUILDING:
			wall = Color(0.86, 0.82, 0.75).lerp(Color(0.70, 0.66, 0.62), roll)
	if kind == UrbanSchema.KIND_MIXED:
		wall = wall.lerp(Color(0.88, 0.86, 0.80), 0.25)
	var roof := Color(0.46, 0.29, 0.24).lerp(Color(0.33, 0.34, 0.36), roll2)
	var trim := Color(0.96, 0.96, 0.94).lerp(Color(0.80, 0.76, 0.68), roll)
	return {
		"wall": _to_array(wall),
		"roof": _to_array(roof),
		"trim": _to_array(trim),
		"glass": _to_array(Color(0.20, 0.27, 0.32).lerp(Color(0.30, 0.38, 0.42), roll2)),
		"accent": _to_array(_accent_color(kind, roll)),
	}


static func _accent_color(kind: String, roll: float) -> Color:
	match kind:
		UrbanSchema.KIND_COMMERCIAL:
			return Color(0.78, 0.35, 0.22).lerp(Color(0.22, 0.42, 0.62), roll)
		UrbanSchema.KIND_PUBLIC:
			return Color(0.72, 0.68, 0.52)
		_:
			return Color(0.55, 0.42, 0.30).lerp(Color(0.34, 0.44, 0.38), roll)


## Cobertura coerente com a tipologia. Casa térrea e de dois pavimentos recebem
## telhado inclinado; edifício alto recebe laje — é o que a silhueta da cidade
## mostra, e é o que permite o telhado ser lido a distância.
static func roof_for(typology: String, salt: int, seed_value: int) -> Dictionary:
	var roll := Deterministic.rand01(salt, 13, seed_value + 59)
	match typology:
		UrbanSchema.TYPOLOGY_HOUSE_GROUND:
			return _roof(UrbanSchema.ROOF_GABLE if roll > 0.35 else UrbanSchema.ROOF_HIP, 26.0, 0.45)
		UrbanSchema.TYPOLOGY_HOUSE_TWO_STOREY:
			return _roof(UrbanSchema.ROOF_GABLE if roll > 0.45 else UrbanSchema.ROOF_HIP, 24.0, 0.42)
		UrbanSchema.TYPOLOGY_HOUSE_GARAGE:
			return _roof(UrbanSchema.ROOF_GABLE if roll > 0.5 else UrbanSchema.ROOF_MONOSLOPE, 20.0, 0.40)
		UrbanSchema.TYPOLOGY_HOUSE_PORCH:
			return _roof(UrbanSchema.ROOF_GABLE if roll > 0.4 else UrbanSchema.ROOF_HIP, 25.0, 0.50)
		UrbanSchema.TYPOLOGY_MIXED_BUILDING:
			if roll > 0.72:
				return _roof(UrbanSchema.ROOF_FLAT, 0.0, 0.30)
			return _roof(UrbanSchema.ROOF_SHED, 16.0, 0.35)
		_:
			return _roof(UrbanSchema.ROOF_FLAT, 0.0, 0.25)


static func _roof(roof_type: String, pitch: float, overhang: float) -> Dictionary:
	return {"type": roof_type, "pitch_deg": pitch, "overhang": overhang}


static func _to_array(color: Color) -> Array:
	return [
		snappedf(color.r, 0.001),
		snappedf(color.g, 0.001),
		snappedf(color.b, 0.001),
	]
