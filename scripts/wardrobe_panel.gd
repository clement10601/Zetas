## 裝備與衣櫃：Y 鍵（手把 R3）打開。左邊是全身預覽，右邊分四頁：裝備（衣袍、腰封、護腕、鞋靴、頭冠、佩飾，
## 有品階數值，只能換背包裡有的）、衣著（套裝、上衣、下裳、外罩、腰封、護腕、鞋靴）、
## 配件（頭飾、髮飾、肩飾、背飾、腰飾）、容貌。↑↓ 選欄（走到頁尾自動翻頁），←→ 換選項，改了立刻穿上並存檔。
## 「套裝」一鍵換上一整組衣著，之後每件還能自己換。還沒解鎖的選項也能挑來試穿，預覽會顯示，
## 下方寫取得方式；關掉時沒解鎖的欄位換回原本穿的。Esc／Y 關閉。
extends Control

const Wardrobe = preload("res://scripts/wardrobe.gd")
const InkUI = preload("res://scripts/ink_ui.gd")
const Equipment = preload("res://scripts/equipment.gd")
const PAGES := ["裝備", "衣著", "配件", "容貌"]

signal changed(look: Dictionary)   # 穿上的外觀變了（只會是已解鎖的組合）
signal equip_changed(equip: Dictionary)   # 換了裝備（只會是背包裡有的）
signal closed

var state                          # WorldState：判斷解鎖
var look: Dictionary = {}          # 預覽中的外觀（可能含試穿中、未解鎖的選項）
var worn: Dictionary = {}          # 實際穿著、已存檔的外觀
var equip: Dictionary = {}         # 身上的裝備：欄位 -> 裝備 id
var row := 0
var rows: Array = []               # 每欄的 {slot, group, value: Label, name: Label, box: Control}；slot "set" 是套裝欄
var tabs: Label
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
	var title := _label("裝備與衣櫃", 22, InkUI.CINNABAR)
	col.add_child(title)
	tabs = _label("", 16, InkUI.INK_SOFT)
	col.add_child(tabs)
	for s in Equipment.slots():
		_add_row(col, "eq." + s["id"], s["name"], "裝備")
	_add_row(col, "set", "套裝", "衣著")
	for s in Wardrobe.slots():
		_add_row(col, s["id"], s["name"], s["group"])
	note = _label("", 15, InkUI.INK)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(480, 96)
	col.add_child(note)
	col.add_child(_label("↑↓ 選欄（到底翻頁）　←→ 換　時裝蓋在裝備上，數值照算裝備的　Esc／Y 關閉", 14, InkUI.INK_SOFT))


func _add_row(col: Container, slot: String, title: String, group: String) -> void:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	var name_l := _label(title, 17, InkUI.INK)
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
	rows.append({"slot": slot, "group": group, "value": value, "name": name_l, "box": r})


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "PaperLabel"
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func open(p_state, current: Dictionary, p_equip: Dictionary = {}) -> void:
	state = p_state
	equip = p_equip.duplicate()
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


## 預覽上看到的樣子：「隨裝備」換成身上裝備的樣子
func shown() -> Dictionary:
	return Wardrobe.resolve(look, Equipment.look_of(equip))


## 目前這欄換到下一個（delta=1）或上一個選項。已解鎖就直接穿上。
func cycle(delta: int) -> void:
	var slot := current_slot()
	if slot.begins_with("eq."):
		_cycle_equip(slot.substr(3), delta)
		return
	if slot == "set":
		_cycle_set(delta)
		return
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


## 裝備欄：在背包裡有的這欄裝備之間換（含「不穿」），立刻穿上。
func _cycle_equip(slot: String, delta: int) -> void:
	var opts: Array = [""] + Equipment.owned_in_slot(state, slot)
	var idx := maxi(0, opts.find(equip.get(slot, "")))
	var id: String = opts[posmod(idx + delta, opts.size())]
	if id == "":
		equip.erase(slot)
	else:
		equip[slot] = id
	equip_changed.emit(equip.duplicate())
	_refresh()


## 套裝欄：換到下一套，整組衣著一起換；解鎖的件直接穿上，沒解鎖的只試穿。
func _cycle_set(delta: int) -> void:
	var all := Wardrobe.sets()
	var cur := Wardrobe.matching_set(shown())
	var idx := -1
	for i in all.size():
		if all[i]["id"] == cur:
			idx = i
	if idx < 0 and delta < 0:
		idx = 0
	var s: Dictionary = all[posmod(idx + delta, all.size())]
	var any_worn := false
	for slot in s["pieces"]:
		look[slot] = s["pieces"][slot]
		if Wardrobe.is_unlocked(slot, look[slot], state):
			worn[slot] = look[slot]
			any_worn = true
	if any_worn:
		changed.emit(worn.duplicate())
	_refresh()


## 預覽也照裝備品階上光暈（跟場景裡同一個著色器）
func _preview_aura() -> void:
	if preview.material == null:
		preview.material = InkUI.halo_material("player").duplicate()
	var a := Equipment.aura(equip)
	var g := int(a["grade"])
	var Player = preload("res://scripts/player.gd")
	preview.material.set_shader_parameter("halo_color", Player.MO_HALO if g >= 4 and a["line"] == "mo" else Player.AURA_HALO[g])
	preview.material.set_shader_parameter("radius", Player.AURA_RADIUS[g])


func _click(r: int, delta: int) -> void:
	row = r
	cycle(delta)


func _refresh() -> void:
	preview.texture = Wardrobe.compose(shown())
	_preview_aura()
	var group: String = rows[row]["group"]
	var names := []
	for g in PAGES:
		names.append("【%s】" % g if g == group else g)
	tabs.text = "　".join(names)
	for i in rows.size():
		var slot: String = rows[i]["slot"]
		rows[i]["box"].visible = rows[i]["group"] == group
		var text := ""
		var unlocked := true
		var color := InkUI.INK
		if slot.begins_with("eq."):
			var eid: String = equip.get(slot.substr(3), "")
			text = "%s・%s" % [Equipment.item(eid)["name"], Equipment.grade_name(eid)] if eid != "" else "不穿"
			color = Equipment.grade_color(eid) if eid != "" else InkUI.INK_SOFT
		elif slot == "set":
			var sid := Wardrobe.matching_set(shown())
			text = Wardrobe.set_by_id(sid).get("name", "自己搭配")
			unlocked = sid == "" or Wardrobe.set_unlocked(sid, state)
		else:
			text = Wardrobe.option(slot, look[slot]).get("name", "")
			if look[slot] == Wardrobe.EQUIP and equip.has(slot):
				text += "（%s）" % Equipment.item(equip[slot])["name"]
			unlocked = Wardrobe.is_unlocked(slot, look[slot], state)
		if not unlocked:
			text += "（試穿）"
		rows[i]["value"].text = ("》 " + text + " 《") if i == row else text
		if slot.begins_with("eq."):
			rows[i]["value"].add_theme_color_override("font_color", color)
		else:
			rows[i]["value"].add_theme_color_override("font_color", InkUI.CINNABAR if i == row else (InkUI.INK if unlocked else InkUI.INK_SOFT))
		rows[i]["name"].add_theme_color_override("font_color", InkUI.CINNABAR if i == row else InkUI.INK)
	var slot := current_slot()
	var lines := []
	if slot.begins_with("eq."):
		var eid: String = equip.get(slot.substr(3), "")
		if eid == "":
			lines.append("這一欄沒穿裝備。←→ 換背包裡有的（%d 件）。" % Equipment.owned_in_slot(state, slot.substr(3)).size())
		else:
			lines.append(Equipment.describe(eid))
			lines.append(Equipment.item(eid).get("note", ""))
		var total := Equipment.stat_text(Equipment.totals(equip))
		lines.append("全身合計：" + (total if total != "" else "無"))
		var aura := Equipment.aura(equip)
		if int(aura["grade"]) > 0:
			lines.append("周身：" + str(Equipment.data()["aura"][int(aura["grade"])]))
	elif slot == "set":
		var sid := Wardrobe.matching_set(shown())
		var s := Wardrobe.set_by_id(sid)
		lines.append(s.get("desc", "上衣、下裳、外罩、腰封、護腕、鞋靴都可以自己挑；←→ 換一整套。"))
		for p in s.get("pieces", {}):
			if not Wardrobe.is_unlocked(p, s["pieces"][p], state):
				lines.append("尚未取得：" + Wardrobe.option(p, s["pieces"][p]).get("source", "？") + "。沒取得的件只是試穿，關掉衣櫃會換回。")
				break
	else:
		var o := Wardrobe.option(slot, look[slot])
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
