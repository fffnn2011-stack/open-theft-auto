class_name Build
## Static helpers for procedural mesh construction.

static func hex(h: int) -> Color:
	return Color(((h >> 16) & 0xFF) / 255.0, ((h >> 8) & 0xFF) / 255.0, (h & 0xFF) / 255.0)

static var _mat_cache: Dictionary = {}
static var _surface_cache: Dictionary = {}

static func mat(color: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m

## Shared cached material — one instance per unique (color, rough, metal).
## Callers must treat the result as immutable; use mat() for a private copy.
static func cmat(color: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var key := color.to_rgba32() * 1000003 + int(rough * 100.0) * 101 + int(metal * 100.0)
	if not _mat_cache.has(key):
		_mat_cache[key] = mat(color, rough, metal)
	return _mat_cache[key]

static func emissive(color: Color, emit: Color, energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = emit
	m.emission_energy_multiplier = energy
	return m


## Lightweight procedural surface materials. They provide visible scale and
## breakup without shipping another large texture pack, and tile consistently
## across procedural meshes instead of stretching one bitmap per building.
static func facade(color: Color, style := "stucco") -> ShaderMaterial:
	var key := style + ":" + str(color.to_rgba32())
	if _surface_cache.has(key):
		return _surface_cache[key]
	var shader := Shader.new()
	if style == "brick":
		shader.code = """
shader_type spatial;
uniform vec4 base_color : source_color;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = vec2((wp.x + wp.z) * 1.25, wp.y * 1.55);
	float row = floor(p.y);
	p.x += mod(row, 2.0) * 0.5;
	vec2 cell = fract(p);
	float mortar = 1.0 - step(0.055, min(min(cell.x, 1.0-cell.x), min(cell.y, 1.0-cell.y)));
	float grain = sin(wp.x * 17.0 + wp.y * 9.0 + wp.z * 13.0) * 0.025;
	ALBEDO = mix(base_color.rgb * (0.9 + grain), vec3(0.58), mortar * 0.34);
	NORMAL = normalize(vec3(grain * 1.8, 1.0, grain * 1.2));
	ROUGHNESS = 0.88;
}
"""
	else:
		shader.code = """
shader_type spatial;
uniform vec4 base_color : source_color;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float fine = sin(wp.x * 19.1 + sin(wp.y * 7.7) + wp.z * 17.3);
	float broad = sin(wp.x * 1.7 + wp.z * 1.3) * 0.5 + 0.5;
	ALBEDO = base_color.rgb * (0.91 + broad * 0.07 + fine * 0.018);
	NORMAL = normalize(vec3(fine * 0.08, 1.0, sin(wp.z * 13.0) * 0.05));
	ROUGHNESS = 0.92;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base_color", color)
	_surface_cache[key] = material
	return material


static func roof_tiles(color: Color) -> ShaderMaterial:
	var key := "roof:" + str(color.to_rgba32())
	if _surface_cache.has(key):
		return _surface_cache[key]
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
uniform vec4 base_color : source_color;
void fragment() {
	vec2 p = UV * vec2(12.0, 9.0);
	float row = floor(p.y);
	p.x += mod(row, 2.0) * 0.5;
	vec2 c = fract(p);
	float seam = 1.0 - step(0.055, min(min(c.x, 1.0-c.x), min(c.y, 1.0-c.y)));
	float shade = 0.88 + 0.12 * sin(c.y * 3.14159);
	ALBEDO = mix(base_color.rgb * shade, base_color.rgb * 0.48, seam);
	ROUGHNESS = 0.84;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base_color", color)
	_surface_cache[key] = material
	return material


static func water() -> ShaderMaterial:
	if _surface_cache.has("water"):
		return _surface_cache.water
	var shader := Shader.new()
	# Long, gentle swells in world space. The previous high-frequency local-vertex
	# waves on a 24×24 grid made each face a random height, so land under the
	# bay punched through as diamond tiles from altitude.
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
varying float wave;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wave = sin(wp.x * 0.08 + TIME * 1.2) * 0.035
		+ cos(wp.z * 0.06 - TIME * 0.9) * 0.025;
	VERTEX.y += wave;
}
void fragment() {
	float ripple = sin((UV.x + UV.y) * 40.0 + TIME * 1.5) * 0.03;
	ALBEDO = mix(vec3(0.025, 0.26, 0.38), vec3(0.08, 0.56, 0.66), 0.5 + ripple);
	ROUGHNESS = 0.08;
	METALLIC = 0.12;
	ALPHA = 1.0;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	_surface_cache.water = material
	return material


static func water_plane(w: float, d: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d)
	# Keep faces ~10 units so swells read as continuous water, not diamond tiles.
	# Cap at 96 so the 16 km horizon sea stays cheap.
	pm.subdivide_width = clampi(int(w / 10.0), 16, 96)
	pm.subdivide_depth = clampi(int(d / 10.0), 16, 96)
	mi.mesh = pm
	mi.material_override = water()
	return mi

static func box(w: float, h: float, d: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	mi.mesh = bm
	if material:
		mi.material_override = material
	return mi

static func cyl(top: float, bot: float, h: float, sides: int, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bot
	cm.height = h
	cm.radial_segments = sides
	mi.mesh = cm
	if material:
		mi.material_override = material
	return mi

static func sphere(r: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	if material:
		mi.material_override = material
	return mi

static func plane(w: float, d: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d)
	mi.mesh = pm
	if material:
		mi.material_override = material
	return mi
