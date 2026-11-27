class_name ProceduralMeshes
extends RefCounted

## Malhas primitivas geradas em código e reaproveitadas por MultiMesh.
## Nada de asset externo: o projeto abre e roda sem importar nada.

static var _cache: Dictionary = {}


static func reset_cache() -> void:
	_cache.clear()


## Copa de árvore estilizada (cone). O tronco é omitido de propósito: a
## instância aparece a partir de ~30 m e o cone com cor variável lê melhor que
## tronco + copa com o dobro de vértices.
static func tree_crown() -> Mesh:
	if _cache.has("tree"):
		return _cache["tree"]
	var cone := CylinderMesh.new()
	cone.top_radius = 0.35
	cone.bottom_radius = 1.9
	cone.height = 4.2
	cone.radial_segments = 7
	cone.rings = 1
	_cache["tree"] = cone
	return cone


static func pole() -> Mesh:
	if _cache.has("pole"):
		return _cache["pole"]
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.09
	cylinder.bottom_radius = 0.14
	cylinder.height = 6.4
	cylinder.radial_segments = 6
	cylinder.rings = 1
	_cache["pole"] = cylinder
	return cylinder


static func street_light_head() -> Mesh:
	if _cache.has("light_head"):
		return _cache["light_head"]
	var box := BoxMesh.new()
	box.size = Vector3(0.34, 0.18, 0.9)
	_cache["light_head"] = box
	return box


## Carroceria baixa e cabine, unidas num só mesh.
static func car_body() -> Mesh:
	if _cache.has("car_body"):
		return _cache["car_body"]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lower := BoxMesh.new()
	lower.size = Vector3(1.82, 0.72, 4.25)
	tool.append_from(lower, 0, Transform3D(Basis(), Vector3(0.0, 0.62, 0.0)))
	var cabin := BoxMesh.new()
	cabin.size = Vector3(1.62, 0.62, 2.05)
	tool.append_from(cabin, 0, Transform3D(Basis(), Vector3(0.0, 1.24, -0.15)))
	var mesh := tool.commit()
	_cache["car_body"] = mesh
	return mesh


# --- carro detalhado da Etapa 5 ----------------------------------------------
#
# Quatro malhas por carro, cada uma com um material próprio:
#   car_shell()  pintura: capô, teto, porta-malas, laterais e colunas
#   car_trim()   plástico escuro: para-choques, grade, retrovisores, saia
#   car_glass()  para-brisa, vidros laterais e vigia traseiro (um mesh só)
#   car_lights() faróis e lanternas, geometria neutra, cor vem do material
# Tudo em caixas compostas por SurfaceTool — é provisório, mas lê como carro e
# não como caixa. Um modelo melhor entra por cima sem tocar na física.


## Casco pintado: chassi longo, capô, teto, porta-malas e colunas A/B/C.
static func car_shell() -> Mesh:
	if _cache.has("car_shell"):
		return _cache["car_shell"]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lower := BoxMesh.new()
	lower.size = Vector3(1.84, 0.52, 4.3)
	tool.append_from(lower, 0, Transform3D(Basis(), Vector3(0.0, 0.55, 0.0)))
	var hood := BoxMesh.new()
	hood.size = Vector3(1.76, 0.1, 1.34)
	tool.append_from(hood, 0, Transform3D(Basis(), Vector3(0.0, 0.86, -1.34)))
	var trunk := BoxMesh.new()
	trunk.size = Vector3(1.76, 0.1, 1.1)
	tool.append_from(trunk, 0, Transform3D(Basis(), Vector3(0.0, 0.86, 1.55)))
	var roof := BoxMesh.new()
	roof.size = Vector3(1.58, 0.08, 1.95)
	tool.append_from(roof, 0, Transform3D(Basis(), Vector3(0.0, 1.5, 0.12)))
	for side in [-0.87, 0.87]:
		var pillar_a := BoxMesh.new()
		pillar_a.size = Vector3(0.1, 0.62, 0.16)
		tool.append_from(pillar_a, 0, Transform3D(Basis(), Vector3(side, 1.19, -0.9)))
		var pillar_b := BoxMesh.new()
		pillar_b.size = Vector3(0.1, 0.6, 0.14)
		tool.append_from(pillar_b, 0, Transform3D(Basis(), Vector3(side, 1.2, 0.18)))
		var pillar_c := BoxMesh.new()
		pillar_c.size = Vector3(0.1, 0.55, 0.14)
		tool.append_from(pillar_c, 0, Transform3D(Basis(), Vector3(side, 1.17, 1.06)))
	var sill := BoxMesh.new()
	sill.size = Vector3(1.9, 0.14, 3.4)
	tool.append_from(sill, 0, Transform3D(Basis(), Vector3(0.0, 0.34, 0.1)))
	var mesh := tool.commit()
	_cache["car_shell"] = mesh
	return mesh


## Plástico escuro: para-choques, grade, alojamento dos retrovisores e para-lama.
static func car_trim() -> Mesh:
	if _cache.has("car_trim"):
		return _cache["car_trim"]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var front := BoxMesh.new()
	front.size = Vector3(1.86, 0.34, 0.24)
	tool.append_from(front, 0, Transform3D(Basis(), Vector3(0.0, 0.5, -2.26)))
	var rear := BoxMesh.new()
	rear.size = Vector3(1.86, 0.34, 0.22)
	tool.append_from(rear, 0, Transform3D(Basis(), Vector3(0.0, 0.5, 2.24)))
	var grille := BoxMesh.new()
	grille.size = Vector3(0.94, 0.22, 0.06)
	tool.append_from(grille, 0, Transform3D(Basis(), Vector3(0.0, 0.72, -2.2)))
	for side in [-0.96, 0.96]:
		var mirror := BoxMesh.new()
		mirror.size = Vector3(0.16, 0.12, 0.08)
		tool.append_from(mirror, 0, Transform3D(Basis(), Vector3(side * 1.06, 1.06, -0.78)))
	var mesh := tool.commit()
	_cache["car_trim"] = mesh
	return mesh


## Vidros num mesh só: para-brisa inclinado, vigia traseiro inclinado e duas
## janelas laterais. O material cuida da transparência.
static func car_glass() -> Mesh:
	if _cache.has("car_glass"):
		return _cache["car_glass"]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var windshield := BoxMesh.new()
	windshield.size = Vector3(1.5, 0.62, 0.06)
	windshield.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-38.0)), Vector3(0.0, 1.24, -0.82))
	tool.append_from(windshield, 0, Transform3D.IDENTITY)
	var rear_window := BoxMesh.new()
	rear_window.size = Vector3(1.46, 0.52, 0.06)
	rear_window.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(34.0)), Vector3(0.0, 1.24, 1.02))
	tool.append_from(rear_window, 0, Transform3D.IDENTITY)
	for side in [-0.8, 0.8]:
		var front_window := BoxMesh.new()
		front_window.size = Vector3(0.05, 0.5, 1.0)
		tool.append_from(front_window, 0, Transform3D(Basis(), Vector3(side, 1.25, -0.36)))
		var rear_window_side := BoxMesh.new()
		rear_window_side.size = Vector3(0.05, 0.46, 0.84)
		tool.append_from(rear_window_side, 0, Transform3D(Basis(), Vector3(side, 1.24, 0.62)))
	var mesh := tool.commit()
	_cache["car_glass"] = mesh
	return mesh


## Par de luzes (uma função, dois usos): faróis e lanternas têm a mesma
## geometria e materiais diferentes.
static func car_lights(width: float = 0.44) -> Mesh:
	var key := "car_lights_%.2f" % width
	if _cache.has(key):
		return _cache[key]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var light := BoxMesh.new()
		light.size = Vector3(width, 0.16, 0.08)
		tool.append_from(light, 0, Transform3D(Basis(), Vector3(side * 0.62, 0.78, -2.3)))
	var mesh := tool.commit()
	_cache[key] = mesh
	return mesh


## Roda com aro: pneu preto + disco central mais claro, um mesh só.
static func wheel() -> Mesh:
	if _cache.has("wheel"):
		return _cache["wheel"]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tire := CylinderMesh.new()
	tire.top_radius = 0.34
	tire.bottom_radius = 0.34
	tire.height = 0.24
	tire.radial_segments = 12
	tire.rings = 1
	tool.append_from(tire, 0, Transform3D.IDENTITY)
	var rim := CylinderMesh.new()
	rim.top_radius = 0.19
	rim.bottom_radius = 0.19
	rim.height = 0.26
	rim.radial_segments = 9
	rim.rings = 1
	tool.append_from(rim, 0, Transform3D.IDENTITY)
	var mesh := tool.commit()
	_cache["wheel"] = mesh
	return mesh


## Pneu sozinho (goma preta). O aro vem em `wheel_rim()`, com material próprio.
static func wheel_tire() -> Mesh:
	if _cache.has("wheel_tire"):
		return _cache["wheel_tire"]
	var tire := CylinderMesh.new()
	tire.top_radius = 0.34
	tire.bottom_radius = 0.34
	tire.height = 0.24
	tire.radial_segments = 12
	tire.rings = 1
	_cache["wheel_tire"] = tire
	return tire


static func wheel_rim() -> Mesh:
	if _cache.has("wheel_rim"):
		return _cache["wheel_rim"]
	var rim := CylinderMesh.new()
	rim.top_radius = 0.19
	rim.bottom_radius = 0.19
	rim.height = 0.27
	rim.radial_segments = 9
	rim.rings = 1
	_cache["wheel_rim"] = rim
	return rim



static func pedestrian_body() -> Mesh:
	if _cache.has("ped_body"):
		return _cache["ped_body"]
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.26
	capsule.height = 1.7
	capsule.radial_segments = 8
	capsule.rings = 3
	_cache["ped_body"] = capsule
	return capsule


static func traffic_light_head() -> Mesh:
	if _cache.has("traffic_head"):
		return _cache["traffic_head"]
	var box := BoxMesh.new()
	box.size = Vector3(0.34, 0.95, 0.28)
	_cache["traffic_head"] = box
	return box


## Semáforo completo: poste, braço e caixa de três luzes, com a base em y = 0.
static func traffic_signal() -> Mesh:
	if _cache.has("signal"):
		return _cache["signal"]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var post := CylinderMesh.new()
	post.top_radius = 0.07
	post.bottom_radius = 0.1
	post.height = 3.4
	post.radial_segments = 6
	post.rings = 1
	tool.append_from(post, 0, Transform3D(Basis(), Vector3(0.0, 1.7, 0.0)))
	var arm := BoxMesh.new()
	arm.size = Vector3(0.09, 0.09, 0.9)
	tool.append_from(arm, 0, Transform3D(Basis(), Vector3(0.0, 3.32, 0.45)))
	var head := BoxMesh.new()
	head.size = Vector3(0.28, 0.9, 0.26)
	tool.append_from(head, 0, Transform3D(Basis(), Vector3(0.0, 2.92, 0.86)))
	var mesh := tool.commit()
	_cache["signal"] = mesh
	return mesh


## Quad em XZ, usado como telhado de interiores.
static func flat_quad(size: Vector2) -> Mesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	tool.set_normal(Vector3.UP)
	tool.add_vertex(Vector3(-hx, 0.0, -hz))
	tool.add_vertex(Vector3(hx, 0.0, -hz))
	tool.add_vertex(Vector3(hx, 0.0, hz))
	tool.add_vertex(Vector3(-hx, 0.0, -hz))
	tool.add_vertex(Vector3(hx, 0.0, hz))
	tool.add_vertex(Vector3(-hx, 0.0, hz))
	return tool.commit()




# --- vegetação e mobiliário da Etapa 3 ---------------------------------------
#
# Todas as malhas abaixo nascem com a base em y = 0. A instância é posicionada
# pela altura do terreno sem correção nenhuma, o que evita o ajuste mágico por
# tipo de objeto espalhado pelo `SectorInstance`.


static func tree_crown_tall() -> Mesh:
	if _cache.has("tree_tall"):
		return _cache["tree_tall"]
	var cone := CylinderMesh.new()
	cone.top_radius = 0.28
	cone.bottom_radius = 1.5
	cone.height = 7.0
	cone.radial_segments = 7
	cone.rings = 1
	_cache["tree_tall"] = _translated(cone, 3.5)
	return _cache["tree_tall"]


## Copa baixa de árvore de calçada, com a base no chão.
static func tree_crown_grounded() -> Mesh:
	if _cache.has("tree_grounded"):
		return _cache["tree_grounded"]
	var cone := CylinderMesh.new()
	cone.top_radius = 0.35
	cone.bottom_radius = 1.9
	cone.height = 4.2
	cone.radial_segments = 7
	cone.rings = 1
	_cache["tree_grounded"] = _translated(cone, 2.1)
	return _cache["tree_grounded"]


static func bush() -> Mesh:
	if _cache.has("bush"):
		return _cache["bush"]
	var sphere := SphereMesh.new()
	sphere.radius = 0.85
	sphere.height = 1.3
	sphere.radial_segments = 7
	sphere.rings = 3
	_cache["bush"] = _translated(sphere, 0.55)
	return _cache["bush"]


## Tufo de grama: dois quads cruzados, barato e suficiente a distância.
static func grass_tuft() -> Mesh:
	if _cache.has("grass"):
		return _cache["grass"]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for angle in [0.0, PI * 0.5]:
		var dir := Vector2(cos(angle), sin(angle)) * 0.42
		var a := Vector3(-dir.x, 0.0, -dir.y)
		var b := Vector3(dir.x, 0.0, dir.y)
		var c := Vector3(dir.x, 0.42, dir.y)
		var d := Vector3(-dir.x, 0.42, -dir.y)
		tool.set_normal(Vector3.UP)
		tool.add_vertex(a)
		tool.add_vertex(b)
		tool.add_vertex(c)
		tool.add_vertex(a)
		tool.add_vertex(c)
		tool.add_vertex(d)
	var mesh := tool.commit()
	_cache["grass"] = mesh
	return mesh


static func bench() -> Mesh:
	if _cache.has("bench"):
		return _cache["bench"]
	var seat := BoxMesh.new()
	seat.size = Vector3(1.8, 0.09, 0.46)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.append_from(seat, 0, Transform3D(Basis(), Vector3(0.0, 0.45, 0.0)))
	var back := BoxMesh.new()
	back.size = Vector3(1.8, 0.42, 0.07)
	tool.append_from(back, 0, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)), Vector3(0.0, 0.7, -0.2)))
	for side in [-0.75, 0.75]:
		var leg := BoxMesh.new()
		leg.size = Vector3(0.09, 0.45, 0.4)
		tool.append_from(leg, 0, Transform3D(Basis(), Vector3(side, 0.22, 0.0)))
	var mesh := tool.commit()
	_cache["bench"] = mesh
	return mesh


static func trash_bin() -> Mesh:
	if _cache.has("bin"):
		return _cache["bin"]
	var body := CylinderMesh.new()
	body.top_radius = 0.26
	body.bottom_radius = 0.22
	body.height = 0.78
	body.radial_segments = 8
	body.rings = 1
	_cache["bin"] = _translated(body, 0.39)
	return _cache["bin"]


static func street_sign() -> Mesh:
	if _cache.has("sign"):
		return _cache["sign"]
	var post := CylinderMesh.new()
	post.top_radius = 0.045
	post.bottom_radius = 0.055
	post.height = 2.35
	post.radial_segments = 5
	post.rings = 1
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.append_from(post, 0, Transform3D(Basis(), Vector3(0.0, 1.175, 0.0)))
	var plate := BoxMesh.new()
	plate.size = Vector3(0.62, 0.62, 0.05)
	tool.append_from(plate, 0, Transform3D(Basis(), Vector3(0.0, 2.1, 0.0)))
	var mesh := tool.commit()
	_cache["sign"] = mesh
	return mesh


static func bus_shelter() -> Mesh:
	if _cache.has("shelter"):
		return _cache["shelter"]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roof := BoxMesh.new()
	roof.size = Vector3(3.6, 0.12, 1.5)
	tool.append_from(roof, 0, Transform3D(Basis(), Vector3(0.0, 2.4, 0.0)))
	for side in [-1.72, 1.72]:
		var post := BoxMesh.new()
		post.size = Vector3(0.1, 2.4, 0.1)
		tool.append_from(post, 0, Transform3D(Basis(), Vector3(side, 1.2, 0.6)))
	var back := BoxMesh.new()
	back.size = Vector3(3.4, 1.9, 0.06)
	tool.append_from(back, 0, Transform3D(Basis(), Vector3(0.0, 1.35, -0.66)))
	var bench_slab := BoxMesh.new()
	bench_slab.size = Vector3(2.6, 0.08, 0.34)
	tool.append_from(bench_slab, 0, Transform3D(Basis(), Vector3(0.0, 0.5, -0.45)))
	var mesh := tool.commit()
	_cache["shelter"] = mesh
	return mesh


static func utility_box() -> Mesh:
	if _cache.has("utility"):
		return _cache["utility"]
	var box := BoxMesh.new()
	box.size = Vector3(0.62, 1.05, 0.42)
	_cache["utility"] = _translated(box, 0.52)
	return _cache["utility"]


static func _translated(mesh: Mesh, height: float) -> Mesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.append_from(mesh, 0, Transform3D(Basis(), Vector3(0.0, height, 0.0)))
	return tool.commit()
