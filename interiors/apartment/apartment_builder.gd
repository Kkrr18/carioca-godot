class_name ApartmentBuilder
extends RefCounted

## Apartamento modular construído em código: sala, cozinha, corredor, dois
## quartos, banheiro e área de serviço.
##
## Cada ambiente é uma laje com paredes próprias. Paredes de cômodos vizinhos se
## sobrepõem com 6 cm de folga de cada lado, o que evita briga de profundidade e
## dispensa calcular parede compartilhada. Como só existe um interior vivo por
## vez, o custo de alguns nós extras é irrelevante.

const WALL_HEIGHT := 2.7
const WALL_THICKNESS := 0.12
const DOOR_WIDTH := 1.0

const ROOMS := [
	{"name": "Sala", "rect": Rect2(0.0, 0.0, 5.0, 4.0), "doors": {"north": 2.5, "east": 2.0}},
	{"name": "Cozinha", "rect": Rect2(5.0, 0.0, 4.0, 3.0), "doors": {"west": 1.5}},
	{"name": "Area de servico", "rect": Rect2(9.0, 0.0, 3.0, 2.0), "doors": {"west": 1.0}},
	{"name": "Banheiro", "rect": Rect2(9.0, 2.0, 3.0, 2.0), "doors": {"west": 1.0}},
	{"name": "Corredor", "rect": Rect2(5.0, 3.0, 4.0, 1.6), "doors": {"west": 0.8}},
	{"name": "Quarto 1", "rect": Rect2(0.0, 4.0, 5.0, 4.0), "doors": {"south": 2.5}},
	{"name": "Quarto 2", "rect": Rect2(5.0, 4.6, 4.0, 3.4), "doors": {"south": 2.0}},
]

const EXIT_POINT := Vector3(2.5, 0.0, 0.15)


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Apartment"

	var body := StaticBody3D.new()
	body.name = "Shell"
	root.add_child(body)

	for room in ROOMS:
		var rect: Rect2 = room["rect"]
		_add_floor(body, root, rect)
		_add_ceiling(root, rect)
		_add_walls(body, rect, room.get("doors", {}))

	_add_furniture(root)
	_add_lights(root)
	_add_exit_door(root)
	return root


static func _add_floor(body: StaticBody3D, root: Node3D, rect: Rect2) -> void:
	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = rect.size
	mesh_instance.mesh = plane
	mesh_instance.material_override = MaterialLibrary.interior_floor()
	mesh_instance.position = Vector3(rect.position.x + rect.size.x * 0.5, 0.0, rect.position.y + rect.size.y * 0.5)
	root.add_child(mesh_instance)

	var shape := BoxShape3D.new()
	shape.size = Vector3(rect.size.x, 0.2, rect.size.y)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(rect.position.x + rect.size.x * 0.5, -0.1, rect.position.y + rect.size.y * 0.5)
	body.add_child(collision)


static func _add_ceiling(root: Node3D, rect: Rect2) -> void:
	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = rect.size
	mesh_instance.mesh = plane
	mesh_instance.material_override = MaterialLibrary.interior_wall()
	mesh_instance.position = Vector3(rect.position.x + rect.size.x * 0.5, WALL_HEIGHT, rect.position.y + rect.size.y * 0.5)
	root.add_child(mesh_instance)


static func _add_walls(body: StaticBody3D, rect: Rect2, doors: Dictionary) -> void:
	var sides := ["south", "north", "west", "east"]
	for side in sides:
		var door_center := float(doors.get(side, -1.0))
		for segment in _wall_segments(rect, side, door_center):
			_add_wall_segment(body, segment[0], segment[1])


## Divide um lado em até dois trechos quando existe porta.
static func _wall_segments(rect: Rect2, side: String, door_center: float) -> Array:
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var length := 0.0
	match side:
		"south":
			a = Vector2(rect.position.x, rect.position.y)
			b = Vector2(rect.position.x + rect.size.x, rect.position.y)
			length = rect.size.x
		"north":
			a = Vector2(rect.position.x, rect.position.y + rect.size.y)
			b = Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y)
			length = rect.size.x
		"west":
			a = Vector2(rect.position.x, rect.position.y)
			b = Vector2(rect.position.x, rect.position.y + rect.size.y)
			length = rect.size.y
		"east":
			a = Vector2(rect.position.x + rect.size.x, rect.position.y)
			b = Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y)
			length = rect.size.y
	if door_center < 0.0:
		return [[a, b]]
	var half := DOOR_WIDTH * 0.5
	var start := clampf(door_center - half, 0.0, length)
	var end := clampf(door_center + half, 0.0, length)
	var direction := (b - a) / maxf(length, 0.001)
	var segments: Array = []
	if start > 0.05:
		segments.append([a, a + direction * start])
	if end < length - 0.05:
		segments.append([a + direction * end, b])
	return segments


static func _add_wall_segment(body: StaticBody3D, a: Vector2, b: Vector2) -> void:
	var length := a.distance_to(b)
	if length < 0.05:
		return
	var center := (a + b) * 0.5
	var angle := atan2(b.y - a.y, b.x - a.x)
	var horizontal := absf(b.x - a.x) > absf(b.y - a.y)

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(length, WALL_HEIGHT, WALL_THICKNESS) if horizontal else Vector3(WALL_THICKNESS, WALL_HEIGHT, length)
	mesh_instance.mesh = box
	mesh_instance.material_override = MaterialLibrary.interior_wall()
	mesh_instance.position = Vector3(center.x, WALL_HEIGHT * 0.5, center.y)
	body.add_child(mesh_instance)

	var shape := BoxShape3D.new()
	shape.size = box.size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = mesh_instance.position
	body.add_child(collision)


static func _add_furniture(root: Node3D) -> void:
	# Sala
	_box(root, Vector3(1.2, 0.45, 0.9), Vector3(0.42, 0.22, 0.25), Vector3(2.4, 0.5, 2.6), "Sofa")
	_box(root, Vector3(1.4, 0.08, 0.7), Vector3(0.28, 0.26, 0.30), Vector3(2.4, 0.42, 1.5), "Mesa de centro")
	_box(root, Vector3(1.1, 0.9, 0.12), Vector3(0.10, 0.10, 0.12), Vector3(2.4, 1.5, 0.12), "TV")
	# Cozinha
	_box(root, Vector3(2.2, 0.9, 0.65), Vector3(0.82, 0.80, 0.76), Vector3(7.1, 0.45, 0.4), "Bancada")
	_box(root, Vector3(0.7, 1.85, 0.68), Vector3(0.86, 0.87, 0.88), Vector3(6.0, 0.92, 0.4), "Geladeira")
	_box(root, Vector3(0.75, 0.9, 0.65), Vector3(0.30, 0.30, 0.32), Vector3(8.4, 0.45, 0.4), "Fogao")
	# Quarto 1
	_box(root, Vector3(1.45, 0.55, 1.95), Vector3(0.55, 0.42, 0.36), Vector3(2.4, 0.28, 6.1), "Cama")
	_box(root, Vector3(0.5, 1.9, 0.5), Vector3(0.60, 0.45, 0.28), Vector3(0.5, 0.95, 5.0), "Guarda-roupa")
	# Quarto 2
	_box(root, Vector3(1.3, 0.55, 1.9), Vector3(0.50, 0.40, 0.38), Vector3(6.6, 0.28, 6.6), "Cama 2")
	# Banheiro
	_box(root, Vector3(0.4, 0.45, 0.55), Vector3(0.92, 0.92, 0.94), Vector3(10.2, 0.22, 3.4), "Vaso")
	_box(root, Vector3(0.7, 0.85, 0.5), Vector3(0.88, 0.88, 0.90), Vector3(11.2, 0.42, 2.6), "Pia")
	# Área de serviço
	_box(root, Vector3(0.65, 0.85, 0.65), Vector3(0.90, 0.90, 0.92), Vector3(10.4, 0.42, 1.0), "Tanque")


static func _box(parent: Node3D, size: Vector3, color: Vector3, position: Vector3, label: String) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.name = label
	mesh_instance.material_override = MaterialLibrary.furniture(Color(color.x, color.y, color.z))
	mesh_instance.position = position
	parent.add_child(mesh_instance)


static func _add_lights(root: Node3D) -> void:
	var spots := [
		Vector3(2.4, 2.5, 2.0),
		Vector3(7.0, 2.5, 1.6),
		Vector3(2.5, 2.5, 6.0),
		Vector3(7.0, 2.5, 6.0),
	]
	for spot in spots:
		var light := OmniLight3D.new()
		light.position = spot
		light.light_energy = 0.85
		light.omni_range = 6.5
		light.light_color = Color(1.0, 0.92, 0.80)
		light.shadow_enabled = false
		root.add_child(light)


static func _add_exit_door(root: Node3D) -> void:
	var frame := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(DOOR_WIDTH + 0.16, 2.2, 0.18)
	frame.mesh = box
	frame.material_override = MaterialLibrary.furniture(Color(0.34, 0.22, 0.14))
	frame.position = Vector3(EXIT_POINT.x, 1.1, EXIT_POINT.z)
	root.add_child(frame)
