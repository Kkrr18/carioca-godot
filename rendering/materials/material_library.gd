class_name MaterialLibrary
extends RefCounted

## Materiais compartilhados. Criados uma vez e reaproveitados: materiais
## duplicados impedem o agrupamento de draw calls, e o alvo de 30 FPS no
## iPhone 12 depende justamente disso.

static var _cache: Dictionary = {}


static func _get_or_create(key: String, factory: Callable) -> Material:
	if _cache.has(key):
		return _cache[key]
	var created: Material = factory.call()
	_cache[key] = created
	return created


static func reset_cache() -> void:
	_cache.clear()


static func terrain() -> ShaderMaterial:
	return _get_or_create("terrain", func() -> Material:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://rendering/materials/terrain.gdshader")
		return mat)


static func road() -> StandardMaterial3D:
	return _get_or_create("road", func() -> Material:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.145, 0.145, 0.16)
		mat.roughness = 0.88
		mat.metallic = 0.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		return mat)


static func vertex_colored(roughness: float = 0.75) -> StandardMaterial3D:
	return _get_or_create("vertex_%.2f" % roughness, func() -> Material:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = Color.WHITE
		mat.roughness = roughness
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		return mat)


static func foliage() -> StandardMaterial3D:
	return _get_or_create("foliage", func() -> Material:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = Color(0.26, 0.38, 0.20)
		mat.roughness = 0.95
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		return mat)


static func prop() -> StandardMaterial3D:
	return _get_or_create("prop", func() -> Material:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.36, 0.37, 0.38)
		mat.roughness = 0.7
		mat.metallic = 0.35
		return mat)


## Luminária pública: um único material emissivo compartilhado por todas as
## luminárias do mundo. O ciclo dia/noite altera a emissão aqui e todas acendem
## ao mesmo tempo, sem uma luz por poste.
static func street_lamps() -> StandardMaterial3D:
	return _get_or_create("street_lamp", func() -> Material:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.92, 0.88, 0.72)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.86, 0.55)
		mat.emission_energy_multiplier = 0.0
		mat.roughness = 0.35
		return mat)


static func vehicle(body_color: Color) -> StandardMaterial3D:
	var key := "vehicle_%s" % body_color.to_html(false)
	return _get_or_create(key, func() -> Material:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = body_color
		mat.roughness = 0.35
		mat.metallic = 0.45
		return mat)


## Vidro do carro: transparente, reflexivo, dois lados (o para-brisa é visto
## de dentro e de fora).
static func vehicle_glass() -> StandardMaterial3D:
	return _get_or_create("vehicle_glass", func() -> Material:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.42, 0.5, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.08
		mat.metallic = 0.2
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		return mat)


## Plástico/preto fosco: para-choque, grade, retrovisor.
static func vehicle_trim() -> StandardMaterial3D:
	return _get_or_create("vehicle_trim", func() -> Material:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.09, 0.09, 0.1)
		mat.roughness = 0.85
		return mat)


## Aro da roda: mais claro que o pneu, metálico.
static func vehicle_rim() -> StandardMaterial3D:
	return _get_or_create("vehicle_rim", func() -> Material:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.62, 0.62, 0.64)
		mat.roughness = 0.3
		mat.metallic = 0.8
		return mat)


## Faróis e lanternas: emissivos, compartilhados como as luminárias públicas.
## Acendem com o ciclo do dia? Ainda não — o gancho é este material único.
static func vehicle_headlight() -> StandardMaterial3D:
	return _get_or_create("vehicle_headlight", func() -> Material:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.92, 0.93, 0.88)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.97, 0.85)
		mat.emission_energy_multiplier = 0.35
		mat.roughness = 0.2
		return mat)


static func vehicle_taillight() -> StandardMaterial3D:
	return _get_or_create("vehicle_taillight", func() -> Material:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.06, 0.05)
		mat.emission_enabled = true
		mat.emission = Color(0.9, 0.1, 0.06)
		mat.emission_energy_multiplier = 0.25
		mat.roughness = 0.25
		return mat)


static func pedestrian(cloth_color: Color) -> StandardMaterial3D:
	var key := "ped_%s" % cloth_color.to_html(false)
	return _get_or_create(key, func() -> Material:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = cloth_color
		mat.roughness = 0.85
		return mat)


static func interior_wall() -> StandardMaterial3D:
	return _get_or_create("int_wall", func() -> Material:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.86, 0.84, 0.79)
		mat.roughness = 0.9
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		return mat)


static func interior_floor() -> StandardMaterial3D:
	return _get_or_create("int_floor", func() -> Material:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.42, 0.31, 0.22)
		mat.roughness = 0.8
		return mat)


static func furniture(color: Color) -> StandardMaterial3D:
	var key := "furn_%s" % color.to_html(false)
	return _get_or_create(key, func() -> Material:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.75
		return mat)
