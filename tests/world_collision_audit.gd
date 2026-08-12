extends Node
## Headless regression audit for the procedural world's most important routes.

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _expect_open(world: CityWorld, x: float, z: float, label: String) -> void:
	var altitude := world.surface_height(x, z)
	if world.collides_at(x, z, 0.35, altitude):
		failures.append("%s blocked at (%.1f, %.1f)" % [label, x, z])


func _inside_safehouse(x: float, z: float) -> bool:
	for property in PropertyCatalog.LIST:
		var center_x: float = property.x + (-CityWorld.BLOCK if property.x > 0.0 else CityWorld.BLOCK) / 2.0
		var center_z: float = property.z + (-CityWorld.BLOCK if property.z > 0.0 else CityWorld.BLOCK) / 2.0
		if absf(x - center_x) < 28.0 and absf(z - center_z) < 28.0:
			return true
	return false


func _run() -> void:
	var world := CityWorld.new()
	add_child(world)
	world.generate()

	# Every road centreline through the city must remain walkable. Sample often
	# enough to catch an accidental prop or oversized building collision.
	for i in range(CityWorld.GRID + 1):
		var road_x := -CityWorld.WORLD_HALF + i * CityWorld.BLOCK
		for z in range(-196, 197, 8):
			if not _inside_safehouse(road_x, float(z)):
				_expect_open(world, road_x, float(z), "north-south road")
		var road_z := -CityWorld.WORLD_HALF + i * CityWorld.BLOCK
		for x in range(-196, 197, 8):
			if not _inside_safehouse(float(x), road_z):
				_expect_open(world, float(x), road_z, "cross street")

	# The beach visibly continues into a shallow-water band; deep water still
	# stops ground movement, while the airport causeway remains open through it.
	_expect_open(world, 0.0, CityWorld.WORLD_HALF + 8.0, "shoreline")
	if not world.collides_at(0.0, CityWorld.WORLD_HALF + 14.0, 0.35, 0.0):
		failures.append("deep water boundary is open")
	_expect_open(world, 80.0, CityWorld.WORLD_HALF + 20.0, "airport causeway")

	# No scenery collision should be remotely mountain-sized anymore.
	for b in world.buildings:
		if float(b.w) > 220.0 and float(b.d) > 220.0:
			failures.append("oversized collision at (%.1f, %.1f): %.1f x %.1f" \
				% [b.x, b.z, b.w, b.d])

	if failures.is_empty():
		print("WORLD_COLLISION_AUDIT_OK buildings=%d" % world.buildings.size())
		get_tree().quit(0)
	else:
		for message in failures.slice(0, 30):
			push_error(message)
		push_error("World collision audit failed: %d issue(s)" % failures.size())
		get_tree().quit(1)
