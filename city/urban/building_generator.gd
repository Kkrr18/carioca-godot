class_name BuildingGenerator
extends RefCounted

## Escolhe e dimensiona uma edificação para um lote.
##
## A regra que evita "prédio aleatório solto no mapa": **nada nasce fora de um
## lote**. A edificação é construída a partir do polígono do lote, recuado pelos
## afastamentos, e a pegada final é sempre um recorte desse polígono — se não
## couber, ela encolhe; se continuar não cabendo, o lote fica vazio (vira quintal
## com vegetação, como num loteamento real).
##
## O que decide a tipologia: densidade urbana, área do lote, testada e um
## sorteio determinístico. Casa térrea, casa de dois pavimentos, casa com
## garagem, casa com varanda, edifício residencial, prédio comercial e construção
## mista saem dessa combinação, com proporções diferentes para densidade alta e
## baixa.
##
## O gerador **não** consulta o terreno. Isso é de propósito: a geração de
## payload roda nas threads de trabalho do streaming, e altura de terreno em
## outra thread significaria leitura concorrente do cache do SRTM. A adaptação ao
## relevo acontece na construção da malha, com embasamento (o prédio apoia no
## ponto mais baixo e o vão até o mais alto é preenchido). O inspetor
## (`tools/urban_tools`) mede a inclinação e aponta o que ficou fora de
## tolerância.

const TYPOLOGY_WIDTH := {
	UrbanSchema.TYPOLOGY_HOUSE_GROUND: Vector2(7.0, 12.0),
	UrbanSchema.TYPOLOGY_HOUSE_TWO_STOREY: Vector2(7.0, 11.5),
	UrbanSchema.TYPOLOGY_HOUSE_GARAGE: Vector2(8.0, 13.0),
	UrbanSchema.TYPOLOGY_HOUSE_PORCH: Vector2(7.5, 12.5),
	UrbanSchema.TYPOLOGY_RESIDENTIAL_BUILDING: Vector2(13.0, 26.0),
	UrbanSchema.TYPOLOGY_COMMERCIAL_BUILDING: Vector2(10.0, 24.0),
	UrbanSchema.TYPOLOGY_MIXED_BUILDING: Vector2(9.0, 18.0),
}

const TYPOLOGY_DEPTH := {
	UrbanSchema.TYPOLOGY_HOUSE_GROUND: Vector2(7.0, 13.0),
	UrbanSchema.TYPOLOGY_HOUSE_TWO_STOREY: Vector2(8.0, 14.0),
	UrbanSchema.TYPOLOGY_HOUSE_GARAGE: Vector2(9.0, 15.0),
	UrbanSchema.TYPOLOGY_HOUSE_PORCH: Vector2(8.0, 14.0),
	UrbanSchema.TYPOLOGY_RESIDENTIAL_BUILDING: Vector2(11.0, 22.0),
	UrbanSchema.TYPOLOGY_COMMERCIAL_BUILDING: Vector2(10.0, 24.0),
	UrbanSchema.TYPOLOGY_MIXED_BUILDING: Vector2(9.0, 18.0),
}

const MAX_FIT_ATTEMPTS := 4
const MIN_FIT_RATIO := 0.62


## Gera a edificação de um lote.
##
## `context`: { "config": UrbanConfig, "network": RoadNetwork, "density": float,
## "seed_value": int, "sector_id": String }
##
## Devolve um dicionário em **espaço métrico**, ou vazio quando o lote fica sem
## construção. A conversão para o espaço local do setor é feita pelo
## `UrbanGenerator`, num lugar só.
static func generate(parcel: Dictionary, context: Dictionary) -> Dictionary:
	var config: UrbanConfig = context.get("config", UrbanConfig.active())
	var network: RoadNetwork = context.get("network")
	var density := clampf(float(context.get("density", 0.5)), 0.0, 1.0)
	var seed_value := int(context.get("seed_value", 20170))
	var sector_id := str(context.get("sector_id", "RJ"))

	var poly: PackedVector2Array = parcel.get("poly", PackedVector2Array())
	var front: Dictionary = parcel.get("front", {})
	if poly.size() < 3 or front.is_empty():
		return {}
	var area := float(parcel.get("area", PolygonUtils.area(poly)))
	if area < config.min_building_area:
		return {}

	var u: Vector2 = front["dir"]
	var n: Vector2 = front["normal"]
	var corner: Vector2 = front["a"]
	var frontage := float(parcel.get("frontage_width", 0.0))
	if frontage <= 0.0:
		frontage = PolygonUtils.project_range(poly, u).y - PolygonUtils.project_range(poly, u).x
	var salt := Deterministic.hash2(int(PolygonUtils.centroid(poly).x), int(PolygonUtils.centroid(poly).y), seed_value)

	var typology := _choose_typology(density, area, frontage, salt, seed_value)
	var kind := UrbanSchema.kind_for_typology(typology)
	var commercial := kind != UrbanSchema.KIND_RESIDENTIAL
	var front_setback := config.setback_front_commercial if commercial else config.setback_front_house
	var side_setback := config.setback_side
	var rear_setback := config.setback_rear

	var u_range := PolygonUtils.project_range(poly, u)
	var n_range := PolygonUtils.project_range(poly, n)
	var buildable := PolygonUtils.clip_slab(poly, u, u_range.x + side_setback, u_range.y - side_setback)
	buildable = PolygonUtils.clip_slab(buildable, n, n_range.x + front_setback, n_range.y - rear_setback)
	if buildable.size() < 3:
		return {}
	if PolygonUtils.area(buildable) < config.min_building_area:
		return {}

	var footprint := _fit_footprint(buildable, u, n, typology, salt, seed_value)
	if footprint.is_empty():
		return {}

	var size := PolygonUtils.project_range(footprint, u)
	var depth_range := PolygonUtils.project_range(footprint, n)
	var width := size.y - size.x
	var depth := depth_range.y - depth_range.x
	if width < 3.0 or depth < 3.0:
		return {}

	if network != null:
		for point in footprint:
			if network.clearance_to_road(point) < config.road_clearance:
				# Rede de segurança: um recorte nunca deveria chegar ao asfalto.
				return {}

	var levels := _levels_for(typology, density, salt, seed_value)
	var floor_height := config.floor_height
	var building_height := float(levels) * floor_height
	var roof := BuildingModules.roof_for(typology, salt, seed_value)
	if str(roof["type"]) != UrbanSchema.ROOF_FLAT:
		building_height += tan(deg_to_rad(float(roof["pitch_deg"]))) * minf(width, depth) * 0.5

	var center := PolygonUtils.centroid(footprint)
	var palette := BuildingModules.palette_for(typology, kind, salt, seed_value)
	var modules := BuildingModules.plan({
		"width": width,
		"depth": depth,
		"levels": levels,
		"typology": typology,
		"kind": kind,
		"floor_height": floor_height,
		"detail": config.detail,
		"category": _category_for(salt, seed_value) if commercial else UrbanSchema.CATEGORY_SMALL,
	}, config, salt)

	# `size` e `depth_range` são projeções absolutas nos eixos (u, n). Como o par
	# é ortonormal, `u*size.x + n*depth_range.x` **é** o canto do prédio no mundo:
	# não se soma `corner` a isso, ou a coordenada dobraria de escala.
	var frame_origin := u * size.x + n * depth_range.x
	var door_along_ratio := 0.5
	var door_modules := modules.filter(func(module: Dictionary) -> bool:
		return str(module.get("type", "")) == UrbanSchema.MODULE_DOOR)
	if not door_modules.is_empty():
		door_along_ratio = clampf(float(door_modules[0].get("along", width * 0.5)) / maxf(width, 0.01), 0.0, 1.0)
	var door := frame_origin + u * (width * door_along_ratio)
	var entrance := door - n * 0.9

	return {
		"id": "",
		"parcel_id": str(parcel.get("id", "")),
		"block_id": str(parcel.get("block_id", "")),
		"sector_id": sector_id,
		"typology": typology,
		"kind": kind,
		"center": center,
		"size": Vector2(width, depth),
		"angle": atan2(u.y, u.x),
		"frame_origin": frame_origin,
		"lot_corner": corner,
		"lot_width": frontage,
		"levels": levels,
		"floor_height": floor_height,
		"height": building_height,
		"footprint": footprint,
		"roof": roof,
		"palette": palette,
		"modules": modules,
		"door": door,
		"entrance": entrance,
		"wall": _wall_for(typology, kind, config, salt, seed_value, width),
		"shopfront": _shopfront_for(commercial, modules),
		"landmark_id": "",
		"confidence": "",
		"category": _category_for(salt, seed_value) if commercial else "",
	}


## Edificação de ponto de referência, a partir da massa declarada no dado.
## O dado diz largura, profundidade, altura e giro; o gerador não inventa nada
## além disso — e marca `confidence` no registro para que ninguém leia a massa
## como reprodução fiel.
static func generate_landmark(landmark: Dictionary, config: UrbanConfig, sector_id: String, seed_value: int) -> Dictionary:
	var massing: Dictionary = landmark.get("generate", {})
	var point: Vector2 = landmark.get("point", Vector2.ZERO)
	var footprint_m: Array = massing.get("footprint_m", [0.0, 0.0])
	var width := float(footprint_m[0]) if footprint_m.size() > 0 else 0.0
	var depth := float(footprint_m[1]) if footprint_m.size() > 1 else 0.0
	if width < 3.0 or depth < 4.0:
		return {}
	var angle := deg_to_rad(float(massing.get("rotation_deg", 0.0)))
	var u := Vector2(cos(angle), sin(angle))
	var n := Vector2(-u.y, u.x)
	var corner := point - u * (width * 0.5) - n * (depth * 0.5)
	var footprint := PolygonUtils.oriented_rect(corner, u, n, 0.0, width, 0.0, depth)
	var levels := maxi(int(massing.get("levels", 1)), 1)
	var height := maxf(float(massing.get("height_m", float(levels) * config.floor_height)), 3.0)
	var salt := Deterministic.hash2(int(point.x), int(point.y), seed_value)
	var typology := str(massing.get("typology", UrbanSchema.TYPOLOGY_COMMERCIAL_BUILDING))
	var palette := BuildingModules.palette_for(typology, UrbanSchema.KIND_PUBLIC, salt, seed_value)
	var roof := BuildingModules.roof_for(typology, salt, seed_value)
	if massing.has("roof"):
		roof = {"type": str(massing.get("roof")), "pitch_deg": 18.0, "overhang": 0.4}
	var modules := BuildingModules.plan({
		"width": width,
		"depth": depth,
		"levels": levels,
		"typology": typology,
		"kind": UrbanSchema.KIND_PUBLIC,
		"floor_height": config.floor_height,
		"detail": config.detail,
	}, config, salt)
	return {
		"id": "",
		"parcel_id": "",
		"block_id": "",
		"sector_id": sector_id,
		"typology": typology,
		"kind": UrbanSchema.KIND_PUBLIC,
		"center": point,
		"size": Vector2(width, depth),
		"angle": angle,
		"frame_origin": corner,
		"levels": levels,
		"floor_height": config.floor_height,
		"height": height,
		"footprint": footprint,
		"roof": roof,
		"palette": palette,
		"modules": modules,
		"door": point - n * (depth * 0.5),
		"entrance": point - n * (depth * 0.5 + 1.2),
		"wall": {},
		"shopfront": {},
		"landmark_id": str(landmark.get("id", "")),
		"landmark_name": str(landmark.get("name", "")),
		"confidence": str(landmark.get("confidence", UrbanSchema.CONFIDENCE_LOW)),
		"category": "",
	}


static func _choose_typology(density: float, area: float, frontage: float, salt: int, seed_value: int) -> String:
	var roll := Deterministic.rand01(salt, 19, seed_value + 83)
	if density >= 0.80 and area >= 900.0 and frontage >= 26.0:
		return UrbanSchema.TYPOLOGY_RESIDENTIAL_BUILDING if roll > 0.32 else UrbanSchema.TYPOLOGY_COMMERCIAL_BUILDING
	if density >= 0.62 and area >= 420.0 and frontage >= 18.0:
		if roll > 0.72:
			return UrbanSchema.TYPOLOGY_RESIDENTIAL_BUILDING
		if roll > 0.48:
			return UrbanSchema.TYPOLOGY_MIXED_BUILDING
		if roll > 0.26:
			return UrbanSchema.TYPOLOGY_COMMERCIAL_BUILDING
		return UrbanSchema.TYPOLOGY_HOUSE_TWO_STOREY
	if density >= 0.42 and area >= 240.0 and frontage >= 13.0:
		if roll > 0.78:
			return UrbanSchema.TYPOLOGY_MIXED_BUILDING
		if roll > 0.52:
			return UrbanSchema.TYPOLOGY_HOUSE_TWO_STOREY
		if roll > 0.34:
			return UrbanSchema.TYPOLOGY_HOUSE_PORCH
		return UrbanSchema.TYPOLOGY_HOUSE_GARAGE
	if density >= 0.30 and area >= 150.0 and frontage >= 10.0:
		if roll > 0.80:
			return UrbanSchema.TYPOLOGY_HOUSE_TWO_STOREY
		if roll > 0.58:
			return UrbanSchema.TYPOLOGY_HOUSE_GARAGE
		if roll > 0.36:
			return UrbanSchema.TYPOLOGY_HOUSE_PORCH
		return UrbanSchema.TYPOLOGY_HOUSE_GROUND
	if roll > 0.62:
		return UrbanSchema.TYPOLOGY_HOUSE_GARAGE
	if roll > 0.30:
		return UrbanSchema.TYPOLOGY_HOUSE_GROUND
	return UrbanSchema.TYPOLOGY_HOUSE_TWO_STOREY


static func _fit_footprint(buildable: PackedVector2Array, u: Vector2, n: Vector2, typology: String, salt: int, seed_value: int) -> PackedVector2Array:
	var u_range := PolygonUtils.project_range(buildable, u)
	var n_range := PolygonUtils.project_range(buildable, n)
	var available_width := u_range.y - u_range.x
	var available_depth := n_range.y - n_range.x
	if available_width < 3.0 or available_depth < 3.0:
		return PackedVector2Array()

	var width_bounds: Vector2 = TYPOLOGY_WIDTH.get(typology, Vector2(8.0, 14.0))
	var depth_bounds: Vector2 = TYPOLOGY_DEPTH.get(typology, Vector2(8.0, 14.0))
	var width := minf(available_width, Deterministic.rand_range(salt, 23, width_bounds.x, width_bounds.y, seed_value + 91))
	var depth := minf(available_depth, Deterministic.rand_range(salt, 29, depth_bounds.x, depth_bounds.y, seed_value + 97))

	# Frente a frente: encostado no recuo frontal, centralizado no eixo lateral.
	var center_u := u_range.x + available_width * 0.5
	var start_u := center_u - width * 0.5
	var start_n := n_range.x

	for attempt in range(MAX_FIT_ATTEMPTS):
		var rect := PolygonUtils.oriented_rect(
			Vector2.ZERO,
			u,
			n,
			start_u,
			start_u + width,
			start_n,
			start_n + depth
		)
		var clipped := PolygonUtils.clip_half_plane(rect, Vector2.ZERO, 0.0)
		clipped = _clip_by_polygon(rect, buildable)
		var rect_area := width * depth
		if clipped.size() >= 3 and rect_area > 1.0:
			var ratio := PolygonUtils.area(clipped) / rect_area
			if ratio >= MIN_FIT_RATIO:
				return clipped
		width *= 0.88
		depth *= 0.88
		start_u = center_u - width * 0.5
		if width < 3.0 or depth < 3.0:
			break
	return PackedVector2Array()


## Interseção exata de dois polígonos, usada só para conformar a pegada ao lote.
## Sutherland–Hodgman exige um recorte convexo; aqui o recorte é o lote, que pode
## ser côncavo, então o caminho é o inverso: recortar o retângulo (convexo) pelas
## arestas do lote, uma a uma, o que é exato quando o resultado é convexo — que é
## o caso de uma pegada retangular dentro de um lote simples.
static func _clip_by_polygon(subject: PackedVector2Array, clip: PackedVector2Array) -> PackedVector2Array:
	if subject.size() < 3 or clip.size() < 3:
		return PackedVector2Array()
	var clip_ccw := PolygonUtils.to_ccw(clip)
	var result := subject
	var count := clip_ccw.size()
	for i in range(count):
		var a := clip_ccw[i]
		var b := clip_ccw[(i + 1) % count]
		var edge := b - a
		if edge.length_squared() < 1.0e-8:
			continue
		edge = edge.normalized()
		var inward := Vector2(-edge.y, edge.x)
		result = PolygonUtils.clip_half_plane(result, inward, inward.dot(a))
		if result.size() < 3:
			return PackedVector2Array()
	return result


static func _levels_for(typology: String, density: float, salt: int, seed_value: int) -> int:
	var roll := Deterministic.rand01(salt, 31, seed_value + 127)
	match typology:
		UrbanSchema.TYPOLOGY_HOUSE_GROUND:
			return 1
		UrbanSchema.TYPOLOGY_HOUSE_TWO_STOREY:
			return 2
		UrbanSchema.TYPOLOGY_HOUSE_GARAGE:
			return 1 if roll < 0.62 else 2
		UrbanSchema.TYPOLOGY_HOUSE_PORCH:
			return 1 if roll < 0.45 else 2
		UrbanSchema.TYPOLOGY_RESIDENTIAL_BUILDING:
			return 4 + int(roll * (4.0 + density * 8.0))
		UrbanSchema.TYPOLOGY_COMMERCIAL_BUILDING:
			return 2 + int(roll * 3.0)
		UrbanSchema.TYPOLOGY_MIXED_BUILDING:
			return 2 + int(roll * 4.0)
		_:
			return 1


static func _category_for(salt: int, seed_value: int) -> String:
	var index := Deterministic.hash2(salt, 37, seed_value) % UrbanSchema.COMMERCE_CATEGORIES.size()
	return UrbanSchema.COMMERCE_CATEGORIES[index]


static func _shopfront_for(commercial: bool, modules: Array) -> Dictionary:
	if not commercial:
		return {}
	for module in modules:
		if str(module.get("type", "")) == UrbanSchema.MODULE_SHOPFRONT:
			return {
				"width": float(module.get("width", 0.0)),
				"height": float(module.get("height", 0.0)),
				"awning": bool(module.get("awning", false)),
				"category": str(module.get("category", UrbanSchema.CATEGORY_SMALL)),
			}
	return {}


## Muro e portão na testada. Nem todo lote tem: casa recuada em rua comercial
## costuma não ter, e o sorteio respeita isso. Devolve vazio quando não há muro.
static func _wall_for(typology: String, kind: String, config: UrbanConfig, salt: int, seed_value: int, width: float) -> Dictionary:
	if kind != UrbanSchema.KIND_RESIDENTIAL:
		return {}
	if typology == UrbanSchema.TYPOLOGY_RESIDENTIAL_BUILDING:
		return {}
	var roll := Deterministic.rand01(salt, 43, seed_value + 131)
	if roll < 0.42:
		return {}
	var gate_width := clampf(width * 0.32, 2.6, 4.2)
	var gate_along := Deterministic.rand_range(salt, 47, 0.5, maxf(width - gate_width - 0.5, 0.5), seed_value + 137)
	return {
		"height": 1.65 + roll * 0.6,
		"thickness": 0.18,
		"gate_width": gate_width,
		"gate_along": gate_along,
		"span": width,
	}
