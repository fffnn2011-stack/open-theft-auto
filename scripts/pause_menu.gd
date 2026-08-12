class_name PauseMenu
extends CanvasLayer
## Escape / pad-Start pause menu — resume, rebindable controls, or exit to
## desktop.
##
## The CONTROLS screen is a single scrollable list of every action in
## InputConfig.ACTIONS, grouped by InputConfig.GROUP_ORDER, each row showing
## a clickable keyboard/mouse chip and a clickable controller chip (click to
## capture a new binding — see _start_capture). A DualSense-style diagram
## (class GamepadDiagram, below) sits above the list as a READ-ONLY reference
## map of the whole controller scheme; assignment only happens in the list.
##
## Mirrors the kiosk terminals / Phone for styling and input conventions:
## opened by game.gd (which owns the "when is it allowed" gate), closes itself
## via _unhandled_input the same way Phone/StockTerminal do, so an Escape that
## opens the menu can't also close it again on the very same frame.

signal resumed
signal exit_requested

const TEXT := Color("e8e6e0")
const DIM := Color("8c9bab")
const FAINT := Color(0.55, 0.57, 0.6)
const GOLD := Color("c2a05a")
const DANGER := Color("c8534a")
const PANEL_BG := Color(0.075, 0.085, 0.10, 1.0)
const EDGE := Color(0.42, 0.62, 0.55, 0.5)
const CHIP_BG := Color(0.16, 0.17, 0.20)
const CHIP_BORDER := Color(0.40, 0.43, 0.48)
const CAPTURE_COLOR := Color("6fd4c6")

var _root: Control
var _pause_view: Control
var _controls_view: Control
var _list_view: Control
var _diagram: GamepadDiagram

var _open := false
var _view := "pause"          # pause | controls

var _capturing := false
var _capture_action := ""
var _capture_device := ""
var _capture_btn: Button
var _capture_tween: Tween

var _kb_chips := {}           # action name -> Button
var _pad_chips := {}          # action name -> Button


func _ready() -> void:
	layer = 30
	_build()
	_root.visible = false
	InputConfig.changed.connect(func() -> void:
		if _open and _view == "controls":
			_refresh_controls())


func is_open() -> bool:
	return _open


## Opened by game.gd on Escape / pad Start while actually playing.
func open() -> void:
	if _open:
		return
	_cancel_capture()
	_open = true
	_root.visible = true
	_show_pause_root()


func _close_resume() -> void:
	if not _open:
		return
	_cancel_capture()
	_open = false
	_root.visible = false
	resumed.emit()


func _exit_game() -> void:
	SaveGame.save_now()
	get_tree().quit()


# =====================================================================
# Navigation
# =====================================================================
func _show_pause_root() -> void:
	_view = "pause"
	_controls_view.visible = false
	_pause_view.visible = true
	UiNav.apply.call_deferred(_pause_view)


func _open_controls() -> void:
	_view = "controls"
	_pause_view.visible = false
	_controls_view.visible = true
	_refresh_controls()
	UiNav.apply.call_deferred(_controls_view)


func _back() -> void:
	if _capturing:
		_cancel_capture()
	elif _view == "controls":
		_show_pause_root()
	else:
		_close_resume()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if _capturing:
		_try_capture(event)
		return
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
		_back()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_back()
		get_viewport().set_input_as_handled()


# =====================================================================
# Rebind capture
# =====================================================================
func _start_capture(action: String, device: String, btn: Button) -> void:
	if _capturing:
		_cancel_capture()
	_capturing = true
	_capture_action = action
	_capture_device = device
	_capture_btn = btn
	btn.text = "PRESS A KEY..." if device == "kb" else "PRESS A BUTTON..."
	btn.add_theme_color_override("font_color", CAPTURE_COLOR)
	_capture_tween = create_tween().set_loops()
	_capture_tween.tween_property(btn, "modulate:a", 0.35, 0.45)
	_capture_tween.tween_property(btn, "modulate:a", 1.0, 0.45)


func _cancel_capture() -> void:
	if not _capturing:
		return
	_capturing = false
	if _capture_tween != null and _capture_tween.is_valid():
		_capture_tween.kill()
	if _capture_btn != null and is_instance_valid(_capture_btn):
		_capture_btn.modulate.a = 1.0
	_capture_btn = null
	_refresh_controls()


func _try_capture(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_cancel_capture()
			get_viewport().set_input_as_handled()
			return
		if _capture_device == "kb":
			var ek := InputEventKey.new()
			ek.physical_keycode = event.physical_keycode
			InputConfig.rebind(_capture_action, "kb", ek)
			_finish_capture()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and _capture_device == "kb":
		var em := InputEventMouseButton.new()
		em.button_index = event.button_index
		InputConfig.rebind(_capture_action, "kb", em)
		_finish_capture()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.pressed and _capture_device == "pad":
		var ej := InputEventJoypadButton.new()
		ej.button_index = event.button_index
		InputConfig.rebind(_capture_action, "pad", ej)
		_finish_capture()
		get_viewport().set_input_as_handled()


func _finish_capture() -> void:
	_capturing = false
	if _capture_tween != null and _capture_tween.is_valid():
		_capture_tween.kill()
	if _capture_btn != null and is_instance_valid(_capture_btn):
		_capture_btn.modulate.a = 1.0
	_capture_btn = null
	_refresh_controls()


# =====================================================================
# Build — pause root
# =====================================================================
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.55)
	_root.add_child(backdrop)

	_pause_view = _build_pause_root()
	_root.add_child(_pause_view)

	_controls_view = _build_controls_view()
	_controls_view.visible = false
	_root.add_child(_controls_view)


func _build_pause_root() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(360, 0)
	panel.add_child(col)

	var title := _lbl("PAUSED", 34, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	col.add_child(_rule())

	var resume_btn := _menu_button("RESUME", TEXT)
	resume_btn.pressed.connect(_close_resume)
	col.add_child(resume_btn)

	var controls_btn := _menu_button("CONTROLS", TEXT)
	controls_btn.pressed.connect(_open_controls)
	col.add_child(controls_btn)

	col.add_child(_rule())
	var exit_btn := _menu_button("EXIT GAME", DANGER)
	exit_btn.pressed.connect(_exit_game)
	col.add_child(exit_btn)

	return center


# =====================================================================
# Build — controls screen
# =====================================================================
const ACTION_COL_W := 340.0
const BIND_COL_W := 210.0
const ROW_SEP := 20.0

func _build_controls_view() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(940, 0)
	panel.add_child(col)

	var title := _lbl("CONTROLS", 28, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	# Read-only DualSense reference diagram — labels pull live bindings, but
	# clicking does nothing; all (re)assignment happens in the list below.
	_diagram = GamepadDiagram.new()
	var diagram_wrap := CenterContainer.new()
	diagram_wrap.add_child(_diagram)
	col.add_child(diagram_wrap)

	col.add_child(_rule())
	col.add_child(_row_header())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 230)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_list_view = _build_action_list()
	scroll.add_child(_list_view)

	col.add_child(_rule())
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 16)
	var reset_btn := _menu_button("RESET TO DEFAULTS", DANGER)
	reset_btn.custom_minimum_size = Vector2(260, 40)
	reset_btn.pressed.connect(_on_reset_defaults)
	bottom.add_child(reset_btn)
	var back_btn := _menu_button("BACK", DIM)
	back_btn.custom_minimum_size = Vector2(180, 40)
	back_btn.pressed.connect(_show_pause_root)
	bottom.add_child(back_btn)
	col.add_child(bottom)

	return root


func _row_header() -> Control:
	var wrap := CenterContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEP)
	var a := _section_label("ACTION")
	a.custom_minimum_size = Vector2(ACTION_COL_W, 0)
	row.add_child(a)
	var k := _section_label("KEYBOARD / MOUSE")
	k.custom_minimum_size = Vector2(BIND_COL_W, 0)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(k)
	var p := _section_label("CONTROLLER")
	p.custom_minimum_size = Vector2(BIND_COL_W, 0)
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(p)
	wrap.add_child(row)
	return wrap


## One comprehensive scrollable list of every action, grouped by
## InputConfig.GROUP_ORDER, with a trailing read-only legend for the analog /
## hardcoded controls that have no ACTIONS entry (see InputConfig.FIXED_CONTROLS).
## Nothing is hidden behind a device tab — sprint and everything else the
## player can do is a single visible row.
func _build_action_list() -> Control:
	var wrap := CenterContainer.new()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(ACTION_COL_W + BIND_COL_W * 2 + ROW_SEP * 2, 0)
	_kb_chips.clear()
	_pad_chips.clear()
	for group in InputConfig.GROUP_ORDER:
		var actions: Array = InputConfig.actions_in_group(group)
		if actions.is_empty():
			continue
		col.add_child(_section_label(group))
		for a in actions:
			col.add_child(_action_row(a.name, a.label))
	col.add_child(_section_label("FIXED CONTROLS (NOT REBINDABLE)"))
	for f in InputConfig.FIXED_CONTROLS:
		col.add_child(_fixed_row(f.label, f.glyph))
	wrap.add_child(col)
	return wrap


func _action_row(action_name: String, label: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEP)

	var lbl := _lbl(label, 15, TEXT)
	lbl.custom_minimum_size = Vector2(ACTION_COL_W, 40)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var kb_chip := _make_chip("")
	kb_chip.custom_minimum_size = Vector2(BIND_COL_W, 40)
	kb_chip.pressed.connect(_on_kb_chip_pressed.bind(action_name, kb_chip))
	_kb_chips[action_name] = kb_chip
	row.add_child(kb_chip)

	var pad_chip := _make_chip("")
	pad_chip.custom_minimum_size = Vector2(BIND_COL_W, 40)
	pad_chip.pressed.connect(_on_pad_chip_pressed.bind(action_name, pad_chip))
	_pad_chips[action_name] = pad_chip
	row.add_child(pad_chip)

	return row


## A non-clickable row (plain labels, not buttons) for an analog / hardcoded
## control that has no InputConfig action — nothing to capture, so it can't
## be part of gamepad focus navigation the way a real rebind chip is.
func _fixed_row(label: String, glyph: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEP)

	var lbl := _lbl(label, 15, FAINT)
	lbl.custom_minimum_size = Vector2(ACTION_COL_W, 32)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var dash := _lbl("—", 15, FAINT)
	dash.custom_minimum_size = Vector2(BIND_COL_W, 32)
	dash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(dash)

	var glyph_lbl := _lbl(glyph, 15, FAINT)
	glyph_lbl.custom_minimum_size = Vector2(BIND_COL_W, 32)
	glyph_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(glyph_lbl)

	return row


func _on_kb_chip_pressed(action: String, chip: Button) -> void:
	_start_capture(action, "kb", chip)


func _on_pad_chip_pressed(action: String, chip: Button) -> void:
	_start_capture(action, "pad", chip)


func _on_reset_defaults() -> void:
	_cancel_capture()
	InputConfig.reset_defaults()
	_refresh_controls()


func _refresh_controls() -> void:
	for action_name in _kb_chips:
		if _capturing and _capture_device == "kb" and _capture_action == action_name:
			continue
		var chip: Button = _kb_chips[action_name]
		chip.text = InputConfig.binding_text(action_name, "kb")
	for action_name in _pad_chips:
		if _capturing and _capture_device == "pad" and _capture_action == action_name:
			continue
		var chip: Button = _pad_chips[action_name]
		chip.text = InputConfig.binding_text(action_name, "pad")
	_diagram.refresh()
	UiNav.apply.call_deferred(_controls_view)


# =====================================================================
# Shared widget helpers (styled to match the kiosk terminals / Phone)
# =====================================================================
func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(26)
	return sb


func _section_label(text: String) -> Label:
	var l := _lbl(text.to_upper(), 13, FAINT)
	l.add_theme_constant_override("line_spacing", 4)
	return l


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = EDGE
	r.custom_minimum_size = Vector2(0, 1)
	return r


func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _menu_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_size_override("font_size", 17)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.14, 0.15, 0.17)
	normal.border_color = color
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.21, 0.23, 0.26)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", TEXT)
	return b


## A keyboard "keycap" chip — a Button styled with a subtle 3D bevel (lighter
## top edge, soft drop shadow) so a row of bindings reads like a row of keys.
func _make_chip(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160, 40)
	b.add_theme_font_size_override("font_size", 15)

	var normal := StyleBoxFlat.new()
	normal.bg_color = CHIP_BG
	normal.border_color = CHIP_BORDER
	normal.set_border_width_all(2)
	normal.border_width_top = 3
	normal.set_corner_radius_all(6)
	normal.shadow_color = Color(0, 0, 0, 0.4)
	normal.shadow_size = 3
	normal.shadow_offset = Vector2(0, 2)

	var hover := normal.duplicate()
	hover.bg_color = Color(0.22, 0.24, 0.28)

	var pressed_sb := normal.duplicate()
	pressed_sb.bg_color = Color(0.10, 0.11, 0.13)
	pressed_sb.border_width_top = 1
	pressed_sb.shadow_size = 1

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed_sb)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_pressed_color", GOLD)
	return b


# =====================================================================
# Controller diagram — read-only DualSense (PS5) reference map.
# Silhouette and control layout match a DualSense: wide touchpad, offset
# sticks, cross d-pad, diamond face buttons, shoulder/trigger stacks.
# Labels reverse-look-up live pad bindings via InputConfig.
# =====================================================================
class GamepadDiagram extends Control:
	const SIZE := Vector2(960, 300)
	const BODY_FILL := Color(0.11, 0.12, 0.15)
	const BODY_MID := Color(0.16, 0.17, 0.21)
	const BODY_EDGE := Color(0.72, 0.76, 0.80, 0.92)
	const BODY_EDGE_SOFT := Color(0.45, 0.50, 0.55, 0.55)
	const STICK_FILL := Color(0.18, 0.19, 0.23)
	const STICK_RIM := Color(0.55, 0.58, 0.62)
	const PAD_FILL := Color(0.20, 0.21, 0.25)
	const LINE_COLOR := Color(0.55, 0.72, 0.68, 0.55)
	const FIXED_COLOR := Color(0.62, 0.64, 0.68)
	const LIVE_COLOR := Color("6fd4c6")
	const ACCENT := Color(0.55, 0.85, 0.95, 0.9)

	const CX := 480.0
	const CY := 28.0

	# DualSense-like right half (from top-center, clockwise around the grip).
	# Dense points → smooth outer curve instead of a blocky polygon.
	const BODY_RIGHT := [
		Vector2(0, 4), Vector2(38, 2), Vector2(78, 4), Vector2(118, 12),
		Vector2(148, 28), Vector2(168, 48), Vector2(178, 72), Vector2(182, 98),
		Vector2(186, 122), Vector2(198, 148), Vector2(212, 168), Vector2(218, 188),
		Vector2(210, 208), Vector2(188, 220), Vector2(158, 226), Vector2(128, 222),
		Vector2(98, 210), Vector2(72, 196), Vector2(48, 184), Vector2(28, 176),
		Vector2(12, 172), Vector2(0, 170),
	]

	# Control anchors (diagram space) — DualSense proportions.
	const P_L2 := Vector2(292, 8)
	const P_L1 := Vector2(292, 28)
	const P_R2 := Vector2(668, 8)
	const P_R1 := Vector2(668, 28)
	const P_CREATE := Vector2(372, 78)       # Create / Share
	const P_OPTIONS := Vector2(588, 78)
	const P_TOUCH := Vector2(480, 88)
	const P_PS := Vector2(480, 128)          # PS button under touchpad
	const P_MUTE := Vector2(480, 148)
	const P_DPAD := Vector2(348, 128)
	const P_FACE := Vector2(612, 120)        # center of face cluster
	const P_LSTICK := Vector2(400, 188)
	const P_RSTICK := Vector2(560, 188)
	const P_PADDLE_L := Vector2(310, 210)
	const P_PADDLE_R := Vector2(650, 210)

	var _left_entries := []
	var _right_entries := []
	var _lines := []
	var _live_entries := []


	func _ready() -> void:
		custom_minimum_size = SIZE
		_left_entries = [
			{"fixed": "Brake / Reverse", "glyph": "L2", "point": P_L2},
			{"pad_button": JOY_BUTTON_LEFT_SHOULDER, "glyph": "L1", "point": P_L1},
			{"pad_button": JOY_BUTTON_BACK, "glyph": "CREATE", "point": P_CREATE},
			{"pad_button": JOY_BUTTON_DPAD_UP, "glyph": "D-PAD ↑", "point": P_DPAD + Vector2(0, -16)},
			{"pad_button": JOY_BUTTON_DPAD_DOWN, "glyph": "D-PAD ↓", "point": P_DPAD + Vector2(0, 16)},
			{"fixed": "Weapon Prev / Next", "glyph": "D-PAD ← →", "point": P_DPAD},
			{"fixed": "Move / Steer", "glyph": "L STICK", "point": P_LSTICK},
			{"pad_button": JOY_BUTTON_PADDLE1, "glyph": "PADDLE L", "point": P_PADDLE_L},
		]
		_right_entries = [
			{"fixed": "Accelerate", "glyph": "R2", "point": P_R2},
			{"pad_button": JOY_BUTTON_RIGHT_SHOULDER, "glyph": "R1", "point": P_R1},
			{"fixed": "Pause Menu", "glyph": "OPTIONS", "point": P_OPTIONS},
			{"pad_button": JOY_BUTTON_Y, "glyph": "△", "point": P_FACE + Vector2(0, -22)},
			{"pad_button": JOY_BUTTON_B, "glyph": "○", "point": P_FACE + Vector2(22, 0)},
			{"pad_button": JOY_BUTTON_X, "glyph": "□", "point": P_FACE + Vector2(-22, 0)},
			{"fixed": "Sprint / Boost (fallback)", "glyph": "✕", "point": P_FACE + Vector2(0, 22)},
			{"fixed": "Camera Look", "glyph": "R STICK", "point": P_RSTICK},
			{"pad_button": JOY_BUTTON_PADDLE2, "glyph": "PADDLE R", "point": P_PADDLE_R},
		]
		_build_widgets()
		refresh()


	func _build_widgets() -> void:
		var y := 4.0
		for e in _left_entries:
			_add_entry(e, Vector2(6, y), "left")
			y += 28.0
		y = 4.0
		for e in _right_entries:
			_add_entry(e, Vector2(730, y), "right")
			y += 28.0


	func _add_entry(e: Dictionary, pos: Vector2, side: String) -> void:
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.custom_minimum_size = Vector2(220, 24)
		lbl.position = pos
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if side == "left" else HORIZONTAL_ALIGNMENT_LEFT
		if e.has("fixed"):
			lbl.text = "%s  %s" % [e.glyph, e.fixed]
			lbl.add_theme_color_override("font_color", FIXED_COLOR)
		else:
			lbl.add_theme_color_override("font_color", LIVE_COLOR)
			e["_label"] = lbl
			_live_entries.append(e)
		add_child(lbl)
		var line_start := (pos + Vector2(220, 12)) if side == "left" else (pos + Vector2(0, 12))
		_lines.append({"a": line_start, "b": e.point})


	func refresh() -> void:
		for e in _live_entries:
			var action: String = InputConfig.action_bound_to_pad_button(e.pad_button)
			var text: String
			if action == "":
				text = "(unassigned)"
			elif action == "interact" or action == "handbrake":
				text = "Interact / Handbrake"
			else:
				text = InputConfig.label_for(action)
			var lbl: Label = e._label
			lbl.text = "%s  %s" % [e.glyph, text]
		queue_redraw()


	func _draw() -> void:
		# Leader lines with endpoint dots (reference-card style).
		for l in _lines:
			draw_line(l.a, l.b, LINE_COLOR, 1.25, true)
			draw_circle(l.b, 2.4, ACCENT)

		_draw_dualsense_body()
		_draw_shoulders()
		_draw_touchpad()
		_draw_system_buttons()
		_draw_dpad()
		_draw_face_buttons()
		_draw_sticks()
		_draw_speaker()


	## Closed DualSense silhouette: smooth outer curve, soft inner shade.
	func _draw_dualsense_body() -> void:
		var origin := Vector2(CX, CY)
		var outer := PackedVector2Array()
		for p in BODY_RIGHT:
			outer.append(origin + p)
		for i in range(BODY_RIGHT.size() - 2, 0, -1):
			var p: Vector2 = BODY_RIGHT[i]
			outer.append(origin + Vector2(-p.x, p.y))
		# Soft under-glow plate.
		var shadow := PackedVector2Array()
		for p in outer:
			shadow.append(p + Vector2(0, 3))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.28))
		draw_colored_polygon(outer, BODY_FILL)
		# Inner face plate (slightly inset) for depth.
		var inner := PackedVector2Array()
		for p in outer:
			var mid := Vector2(CX, CY + 100)
			inner.append(p.lerp(mid, 0.08))
		draw_colored_polygon(inner, BODY_MID)
		var closed := outer.duplicate()
		closed.append(outer[0])
		draw_polyline(closed, BODY_EDGE, 2.0, true)
		# Subtle top edge highlight.
		draw_line(origin + Vector2(-70, 6), origin + Vector2(70, 6),
			Color(1, 1, 1, 0.08), 2.0, true)


	func _draw_shoulders() -> void:
		# L2 / R2 — taller trigger capsules above the body.
		_shoulder_capsule(P_L2, true)
		_shoulder_capsule(P_R2, true)
		# L1 / R1 — flatter bumpers.
		_shoulder_capsule(P_L1, false)
		_shoulder_capsule(P_R1, false)


	func _shoulder_capsule(p: Vector2, trigger: bool) -> void:
		var w := 72.0 if trigger else 68.0
		var h := 18.0 if trigger else 14.0
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.17, 0.18, 0.22)
		sb.border_color = BODY_EDGE
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(int(h * 0.5))
		draw_style_box(sb, Rect2(p - Vector2(w * 0.5, h * 0.5), Vector2(w, h)))
		if trigger:
			# Inner trigger groove.
			draw_line(p + Vector2(-18, 0), p + Vector2(18, 0), BODY_EDGE_SOFT, 1.2, true)


	func _draw_touchpad() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = PAD_FILL
		sb.border_color = BODY_EDGE
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(10)
		# DualSense touchpad is wide and relatively short.
		draw_style_box(sb, Rect2(P_TOUCH - Vector2(86, 28), Vector2(172, 56)))
		# Soft glass sheen.
		draw_line(P_TOUCH + Vector2(-70, -14), P_TOUCH + Vector2(40, -14),
			Color(1, 1, 1, 0.10), 2.0, true)
		# Light bar under the pad.
		draw_line(P_TOUCH + Vector2(-50, 30), P_TOUCH + Vector2(50, 30),
			Color(0.35, 0.75, 0.95, 0.55), 2.5, true)


	func _draw_system_buttons() -> void:
		# Create (left) / Options (right) — small pill buttons.
		_sys_pill(P_CREATE)
		_sys_pill(P_OPTIONS)
		# PS button.
		draw_circle(P_PS, 9, STICK_FILL)
		draw_arc(P_PS, 9, 0, TAU, 20, STICK_RIM, 1.3, true)
		_glyph(P_PS, "PS", FIXED_COLOR, 10)
		# Mute mic button under PS.
		draw_circle(P_MUTE, 5, STICK_FILL)
		draw_arc(P_MUTE, 5, 0, TAU, 14, STICK_RIM, 1.1, true)


	func _sys_pill(p: Vector2) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = STICK_FILL
		sb.border_color = STICK_RIM
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		draw_style_box(sb, Rect2(p - Vector2(14, 7), Vector2(28, 14)))


	func _draw_dpad() -> void:
		# Continuous cross (DualSense d-pad is one piece).
		var c := P_DPAD
		var arm := 15.0
		var thick := 12.0
		var col := STICK_FILL
		var rim := STICK_RIM
		# Vertical bar
		draw_rect(Rect2(c.x - thick * 0.5, c.y - arm - thick * 0.5, thick, arm * 2 + thick), col)
		draw_rect(Rect2(c.x - thick * 0.5, c.y - arm - thick * 0.5, thick, arm * 2 + thick), rim, false, 1.3)
		# Horizontal bar
		draw_rect(Rect2(c.x - arm - thick * 0.5, c.y - thick * 0.5, arm * 2 + thick, thick), col)
		draw_rect(Rect2(c.x - arm - thick * 0.5, c.y - thick * 0.5, arm * 2 + thick, thick), rim, false, 1.3)
		# Direction nubs
		_glyph(c + Vector2(0, -arm + 2), "▲", FIXED_COLOR, 9)
		_glyph(c + Vector2(0, arm - 1), "▼", FIXED_COLOR, 9)
		_glyph(c + Vector2(-arm + 2, 1), "◀", FIXED_COLOR, 9)
		_glyph(c + Vector2(arm - 2, 1), "▶", FIXED_COLOR, 9)


	func _draw_face_buttons() -> void:
		var c := P_FACE
		var o := 22.0
		var pts := [
			{"p": c + Vector2(0, -o), "g": "△", "col": Color("6eb0f0")},
			{"p": c + Vector2(o, 0), "g": "○", "col": Color("f07890")},
			{"p": c + Vector2(-o, 0), "g": "□", "col": Color("e8c070")},
			{"p": c + Vector2(0, o), "g": "✕", "col": Color("70e0a8")},
		]
		for b in pts:
			draw_circle(b.p, 13, STICK_FILL)
			draw_arc(b.p, 13, 0, TAU, 24, STICK_RIM, 1.4, true)
			_glyph(b.p, b.g, b.col, 15)


	func _draw_sticks() -> void:
		for p in [P_LSTICK, P_RSTICK]:
			# Outer well
			draw_circle(p, 28, Color(0.09, 0.10, 0.12))
			draw_arc(p, 28, 0, TAU, 32, BODY_EDGE_SOFT, 1.5, true)
			# Cap
			draw_circle(p, 22, STICK_FILL)
			draw_arc(p, 22, 0, TAU, 28, STICK_RIM, 1.6, true)
			# Concavity ring
			draw_arc(p, 12, 0, TAU, 20, Color(0.30, 0.32, 0.36), 1.2, true)
			draw_circle(p, 4, Color(0.28, 0.30, 0.34))


	func _draw_speaker() -> void:
		# DualSense speaker grille between the sticks.
		var base := Vector2(CX, CY + 198)
		for row in range(3):
			for col in range(6):
				var p := base + Vector2((col - 2.5) * 5.0, (row - 1) * 4.0)
				draw_circle(p, 1.1, BODY_EDGE_SOFT)


	func _glyph(p: Vector2, s: String, color: Color, size: int = 16) -> void:
		var font := ThemeDB.fallback_font
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(font, p + Vector2(-w * 0.5, size * 0.35), s,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
