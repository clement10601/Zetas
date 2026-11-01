## 按鍵設定畫面：Esc（或 F10、手把 Start）打開。每個動作三格鍵位（方向鍵組／WASD 組／其他），
## 點一格再按新的鍵就換掉；Backspace 清空這格，Esc 取消。同一個鍵只會留在一個動作上。
## 手把按鍵固定（顯示在最右欄）。改完立刻生效，存在 keys_path。
extends Control

const Keys = preload("res://scripts/keys.gd")
const InkUI = preload("res://scripts/ink_ui.gd")

signal changed
signal closed

const PAD_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_DPAD_UP: "十字↑", JOY_BUTTON_DPAD_DOWN: "十字↓",
	JOY_BUTTON_DPAD_LEFT: "十字←", JOY_BUTTON_DPAD_RIGHT: "十字→",
}

var keys_path := ""
var capturing: Array = []          # [動作 id, 格]，等玩家按新鍵
var buttons := {}                  # "id:slot" -> Button
var status: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", InkUI.paper_box())
	box.position = Vector2(190, 28)
	box.custom_minimum_size = Vector2(900, 0)
	add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	box.add_child(col)
	var title := Label.new()
	title.theme_type_variation = "PaperLabel"
	title.text = "按鍵設定　（兩組鍵盤配置同時有效，也可以接手把）"
	col.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 3)
	col.add_child(grid)
	for head in ["動作"] + Keys.SLOT_NAMES + ["手把"]:
		grid.add_child(_label(head, true))
	for a in Keys.ACTIONS:
		grid.add_child(_label(a["name"]))
		for slot in Keys.SLOTS:
			var b := Button.new()
			b.custom_minimum_size = Vector2(120, 0)
			b.focus_mode = Control.FOCUS_ALL
			b.add_theme_font_size_override("font_size", 15)
			b.pressed.connect(_start_capture.bind(a["id"], slot))
			# Esc 一定能打開這個畫面，不給改
			b.disabled = a["id"] == "settings" and slot == 0
			buttons["%s:%d" % [a["id"], slot]] = b
			grid.add_child(b)
		grid.add_child(_label(" ".join(a.get("pad", []).map(func(p): return PAD_NAMES.get(p, str(p))))))
	status = _label("")
	col.add_child(status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var reset := Button.new()
	reset.text = "恢復預設"
	reset.pressed.connect(func():
		Keys.reset(keys_path)
		capturing = []
		_refresh("已恢復預設按鍵。")
		changed.emit())
	row.add_child(reset)
	var close_btn := Button.new()
	close_btn.text = "關閉（Esc）"
	close_btn.pressed.connect(close)
	row.add_child(close_btn)


func _label(text: String, head := false) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "PaperLabel"
	l.add_theme_font_size_override("font_size", 17 if head else 15)
	if head:
		l.add_theme_color_override("font_color", InkUI.CINNABAR)
	return l


func open() -> void:
	capturing = []
	visible = true
	_refresh("點一格，再按下新的鍵。Backspace 清空這格。")
	buttons["jump:0"].grab_focus()


func close() -> void:
	capturing = []
	visible = false
	closed.emit()


func _start_capture(id: String, slot: int) -> void:
	capturing = [id, slot]
	_refresh("請按下要給「%s」的新按鍵……（Esc 取消、Backspace 清空）" % Keys.action(id)["name"])
	buttons["%s:%d" % [id, slot]].text = "？"


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = event.physical_keycode
		if not capturing.is_empty():
			get_viewport().set_input_as_handled()
			assign(kc)
		elif kc == KEY_ESCAPE or event.is_action_pressed("settings"):
			get_viewport().set_input_as_handled()
			close()
	elif event is InputEventJoypadButton and event.pressed and capturing.is_empty():
		if event.button_index in [JOY_BUTTON_START, JOY_BUTTON_B]:
			get_viewport().set_input_as_handled()
			close()


## 正在等新鍵時按下 kc（測試也直接呼叫）。
func assign(kc: int) -> void:
	if capturing.is_empty():
		return
	var id: String = capturing[0]
	var slot: int = capturing[1]
	capturing = []
	if kc == KEY_ESCAPE:
		_refresh("沒有變更。")
		return
	if kc == KEY_BACKSPACE:
		Keys.rebind(id, slot, 0, keys_path)
		_refresh("已清空。")
		changed.emit()
		return
	var taken: Array = Keys.rebind(id, slot, kc, keys_path)
	var note := "「%s」改成 %s。" % [Keys.action(id)["name"], Keys.key_name(kc)]
	if not taken.is_empty():
		note += "（這個鍵原本是「%s」的，已從那裡拿掉）" % "、".join(taken)
	_refresh(note)
	changed.emit()


func _refresh(message: String) -> void:
	status.text = message
	for a in Keys.ACTIONS:
		for slot in Keys.SLOTS:
			buttons["%s:%d" % [a["id"], slot]].text = Keys.key_name(Keys.bindings[a["id"]][slot])
