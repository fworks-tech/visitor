extends SceneTree

## Sight audit: from the house spawn camera, list every mesh that lands near
## frame center, with its glow (emission) — identifies mystery white blobs.
##   godot --headless --path <project> --script res://tools/sight_audit.gd
## (Plain script: dynamic access only, so --script mode compiles it.)

func _init() -> void:
	_run()

func _run() -> void:
	for i in range(60):
		await process_frame
	var scene := root.get_node_or_null("HouseScene")
	if scene == null:
		var packed: PackedScene = load("res://scenes/house/HouseScene.tscn")
		scene = packed.instantiate()
		root.add_child(scene)
		for i in range(60):
			await process_frame
	var house3d: Node = scene.get_node("View3D/SubViewport/House3D")
	var player: Node3D = house3d.get("player") as Node3D
	var cam := player.get("camera") as Camera3D
	# Spawn view, then staged poses: office desk, hall center.
	await _audit_pose(house3d, player, cam, "SPAWN")
	player.position = Vector3(-1.5, 0.05, -4.5)
	player.rotation.y = 0.0  # face -Z: the desk on the north wall
	for i in range(30):
		await process_frame
	await _audit_pose(house3d, player, cam, "OFFICE-DESK")
	player.position = Vector3(0, 0.05, 0.5)
	player.rotation.y = 0.0
	for i in range(30):
		await process_frame
	await _audit_pose(house3d, player, cam, "HALL")
	player.position = Vector3(-1.5, 0.05, 0.5)
	player.rotation.y = -PI / 2.0  # face +X: the east wall + bedroom doorway
	for i in range(30):
		await process_frame
	await _audit_pose(house3d, player, cam, "HALL-EAST")
	quit()

func _audit_pose(house3d: Node, player: Node3D, cam: Camera3D, label: String) -> void:
	print("=== %s CAM pos=%s fwd=%s" % [label, str(cam.global_position),
		str(-cam.global_transform.basis.z)])
	var hits := []
	var vsz := cam.get_viewport().get_visible_rect().size
	_collect(house3d, cam, vsz, hits)
	hits.sort_custom(func(a, b): return a[0] < b[0])
	print("viewport=", vsz, " total near-center:")
	print("NEAR-CENTER MESHES (dist | norm-xy | size | emission | path):")
	for h in hits:
		print("%.1fm | (%.0f,%.0f) | %.2fm | e=%.1f | %s" % [h[0], h[1].x, h[1].y, h[2], h[3], h[4]])

func _collect(n: Node, cam: Camera3D, vsz: Vector2, hits: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var aabb: AABB = mi.get_aabb()
			var center: Vector3 = (mi as Node3D).global_transform * aabb.get_center()
			var to: Vector3 = center - cam.global_position
			var dist := to.length()
			if dist > 0.1 and dist < 14.0 and not cam.is_position_behind(center):
				var s := cam.unproject_position(center)
				var nx := (s.x - vsz.x / 2.0) / (vsz.x / 2.0)
				var ny := (s.y - vsz.y / 2.0) / (vsz.y / 2.0)
				if absf(nx) < 0.45 and ny > -0.6 and ny < 0.6:
					hits.append([dist, Vector2(nx, ny), aabb.size.length(), _emission(mi), String(mi.get_path())])
		_collect(c, cam, vsz, hits)

func _emission(mi: MeshInstance3D) -> float:
	var m := mi.material_override
	if m is StandardMaterial3D and (m as StandardMaterial3D).emission_enabled:
		return (m as StandardMaterial3D).emission_energy_multiplier
	var mesh := mi.mesh
	if mesh != null and mesh.get_surface_count() > 0:
		var sm := mesh.surface_get_material(0)
		if sm is StandardMaterial3D and (sm as StandardMaterial3D).emission_enabled:
			return (sm as StandardMaterial3D).emission_energy_multiplier
	return 0.0
