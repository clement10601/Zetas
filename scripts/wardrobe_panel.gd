## 衣櫃與容貌：Y 鍵（手把 R3）打開。左邊是全身預覽，右邊一欄一欄（衣著、頭飾……髮色、臉型）。
## ↑↓ 選欄，←→ 換選項，改了立刻穿上並存檔。還沒解鎖的選項也能挑來試穿，預覽會顯示，
## 下方寫取得方式；關掉時沒解鎖的欄位換回原本穿的。Esc／Y 關閉。
extends Control

const Wardrobe = preload("res://scripts/wardrobe.gd")
const InkUI = preload("res://scripts/ink_ui.gd")

signal changed(look: Dictionary)   # 穿上的外觀變了（只會是已解鎖的組合）
signal closed

var state                          # WorldState：判斷解鎖
var look: Dictionary = {}          # 預覽中的外觀（可能含試穿中、未解鎖的選項）
var worn: Dictionary = {}          # 實際穿著、已存檔的外觀
var row := 0
var rows: Array = []               # 每欄的 {slot, value: Label, row: Control}
var preview: TextureRect
var note: Label


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
	box.position = Vector2(170, 40)
	box.custom_minimum_size = Vector2(940, 600)
	add_child(box)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	box.add_child(cols)
	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(330, 440)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cols.add_child(preview)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(col)
	var title := _label("衣櫃與容貌", 22, InkUI.CINNABAR)
	col.add_child(title)
	var group := ""
	for s in Wardrobe.slots():
		if s["group"] != group:
			group = s["group"]
			col.add_child(_label("— %s —" % group, 15, InkUI.INK_SOFT))
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var name_l := _label(s["name"], 17, InkUI.INK)
		name_l.custom_minimum_size = Vector2(70, 0)
		r.add_child(name_l)
		var prev := Button.new()
		prev.text = "◀"
		prev.focus_mode = Control.FOCUS_NONE
		prev.pressed.connect(_click.bind(rows.size(), -1))
		r.add_child(prev)
		var value := _label("", 17, InkUI.INK)
		value.custom_minimum_size = Vector2(250, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		r.add_child(value)
		var nxt := Button.new()
		nxt.text = "▶"
		nxt.focus_mode = Control.FOCUS_NONE
		nxt.pressed.connect(_click.bind(rows.size(), 1))
		r.add_child(nxt)
		col.add_child(r)
		rows.append({"slot": s["id"], "value": value, "name": name_l})
	note = _label("", 15, InkUI.INK)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(480, 96)
	col.add_child(note)
	col.add_child(_label("↑↓ 選欄　←→ 換　未解鎖的可以試穿，關掉時換回　Esc／Y 關閉", 14, InkUI.INK_SOFT))


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "PaperLabel"
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func open(p_state, current: Dictionary) -> void:
	state = p_state
	worn = Wardrobe.normalize(current)
	look = worn.duplicate()
	row = 0
	visible = true
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func current_slot() -> String:
	return rows[row]["slot"]


func move_row(delta: int) -> void:
	row = posmod(row + delta, rows.size())
	_refresh()


## 目前這欄換到下一個（delta=1）或上一個選項。已解鎖就直接穿上。
func cycle(delta: int) -> void:
	var slot := current_slot()
	var opts := Wardrobe.options(slot)
	var idx := 0
	for i in opts.size():
		if opts[i]["id"] == look[slot]:
			idx = i
	look[slot] = opts[posmod(idx + delta, opts.size())]["id"]
	if Wardrobe.is_unlocked(slot, look[slot], state):
		worn[slot] = look[slot]
		changed.emit(worn.duplicate())
	_refresh()


func _click(r: int, delta: int) -> void:
	row = r
	cycle(delta)


func _refresh() -> void:
	preview.texture = Wardrobe.compose(look)
	for i in rows.size():
		var slot: String = rows[i]["slot"]
		var o := Wardrobe.option(slot, look[slot])
		var unlocked := Wardrobe.is_unlocked(slot, look[slot], state)
		var text: String = o.get("name", "")
		if not unlocked:
			text += "（試穿）"
		rows[i]["value"].text = ("》 " + text + " 《") if i == row else text
		rows[i]["value"].add_theme_color_override("font_color", InkUI.CINNABAR if i == row else (InkUI.INK if unlocked else InkUI.INK_SOFT))
		rows[i]["name"].add_theme_color_override("font_color", InkUI.CINNABAR if i == row else InkUI.INK)
	var slot := current_slot()
	var o := Wardrobe.option(slot, look[slot])
	var lines := []
	if o.get("desc", "") != "":
		lines.append(o["desc"])
	if not Wardrobe.is_unlocked(slot, look[slot], state):
		lines.append("尚未取得：" + o.get("source", "？") + "。現在只是試穿，關掉衣櫃會換回原本的。")
	note.text = "\n".join(lines)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) or \
		(event is InputEventJoypadButton and event.pressed)
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	handle(event)


## 一個按下去的鍵（測試也直接呼叫）。
func handle(event: InputEvent) -> void:
	var kc: int = event.physical_keycode if event is InputEventKey else 0
	if event.is_action_pressed("settings") or event.is_action_pressed("wardrobe") or kc == KEY_ESCAPE \
			or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B):
		close()
	elif event.is_action_pressed("move_up"):
		move_row(-1)
	elif event.is_action_pressed("move_down"):
		move_row(1)
	elif event.is_action_pressed("move_left"):
		cycle(-1)
	elif event.is_action_pressed("move_right"):
		cycle(1)
