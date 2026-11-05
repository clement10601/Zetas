## 行囊：Y 鍵（手把 R3）打開。左邊是全身預覽，右邊分五頁：物品（背包裡的東西與兵器，裝備、兵器、時裝可以直接穿上／換下）、
## 裝備（衣袍、腰封、護腕、鞋靴、頭冠、佩飾，有品階數值）、衣著（套裝、上衣、下裳、外罩、腰封、護腕、鞋靴）、
## 配件（頭飾、髮飾、肩飾、背飾、腰飾）、容貌。↑↓ 選（走到頁尾自動翻頁），←→ 換選項或穿上，改了立刻穿上並存檔。
## 裝備和時裝都只能換已經拿到的（物品欄裡有）；沒拿到的不列出來，下方寫還有哪些、去哪裡拿。容貌不用取得。Esc／Y 關閉。
extends Control

const Wardrobe = preload("res://scripts/wardrobe.gd")
const InkUI = preload("res://scripts/ink_ui.gd")
const Equipment = preload("res://scripts/equipment.gd")
const PAGES := ["物品", "裝備", "衣著", "配件", "容貌"]
const BAG_LINES := 12              # 物品頁一次列幾行

signal changed(look: Dictionary)   # 穿上的外觀變了（只會是已解鎖的組合）
signal equip_changed(equip: Dictionary)   # 換了裝備（只會是背包裡有的）
signal bag_used(entry: Dictionary)   # 物品頁按了穿上／換下（main 做完再 sync 回來）
signal closed

var state                          # WorldState：判斷解鎖
var look: Dictionary = {}          # 身上的外觀（只會有已經拿到的）
var worn: Dictionary = {}          # 實際穿著、已存檔的外觀（跟 look 一樣，留著給舊呼叫）
var equip: Dictionary = {}         # 身上的裝備：欄位 -> 裝備 id
var row := 0
var bag: Array = []                # 物品欄（main.bag_entries()）
var bag_index := 0
var in_bag := false                # 游標在物品頁
var bag_box: VBoxContainer
var bag_labels: Array = []
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
	var title := _label("行囊", 22, InkUI.CINNABAR)
	col.add_child(title)
	tabs = _label("", 16, InkUI.INK_SOFT)
	col.add_child(tabs)
	bag_box = VBoxContainer.new()
	bag_box.add_theme_constant_override("separation", 2)
	col.add_child(bag_box)
	for i in BAG_LINES:
		var l := _label("", 16, InkUI.INK)
		bag_box.add_child(l)
		bag_labels.append(l)
	for s in Equipment.slots():
		_add_row(col, "eq." + s["id"], s["name"], "裝備")
	_add_row(col, "set", "套裝", "衣著")
	for s in Wardrobe.slots():
		_add_row(col, s["id"], s["name"], s["group"])
	note = _label("", 15, InkUI.INK)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(480, 96)
	col.add_child(note)
	col.add_child(_label("↑↓ 選（到底翻頁）　←→ 換／穿上　只能換已經拿到的　時裝蓋在裝備上　Esc／Y 關閉", 14, InkUI.INK_SOFT))


func _add_row(col: Container, slot: String, title: String, group: String) -> void:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	var name_l := _label(title, 17, InkUI.INK)
	name_l.custom_minimum_size = Vector2(70, 0)
	r.add_child(name_l)
	var prev := Button.new()
	prev.text = "←"
	prev.focus_mode = Control.FOCUS_NONE
	prev.pressed.connect(_click.bind(rows.size(), -1))
	r.add_child(prev)
	var value := _label("", 17, InkUI.INK)
	value.custom_minimum_size = Vector2(250, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.add_child(value)
	var nxt := Button.new()
	nxt.text = "→"
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


func open(p_state, current: Dictionary, p_equip: Dictionary = {}, p_bag: Array = []) -> void:
	state = p_state
	row = 0
	bag_index = 0
	in_bag = true
	visible = true
	sync(current, p_equip, p_bag)


## 外面（物品頁的動作）改了身上的東西：重讀一次
func sync(current: Dictionary, p_equip: Dictionary, p_bag: Array) -> void:
	equip = p_equip.duplicate()
	worn = Wardrobe.normalize(current)
	look = worn.duplicate()
	bag = p_bag
	bag_index = clampi(bag_index, 0, maxi(0, bag.size() - 1))
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func current_slot() -> String:
	return "bag" if in_bag else rows[row]["slot"]


## 物品頁一行一行走完接裝備頁，容貌頁最後一欄再往下回到物品頁
func move_row(delta: int) -> void:
	var n := maxi(1, bag.size())
	var i := posmod((bag_index if in_bag else n + row) + delta, n + rows.size())
	in_bag = i < n
	if in_bag:
		bag_index = i
	else:
		row = i - n
	_refresh()


func current_entry() -> Dictionary:
	return bag[bag_index] if in_bag and bag_index < bag.size() else {}


## 預覽上看到的樣子：「隨裝備」換成身上裝備的樣子
func shown() -> Dictionary:
	return Wardrobe.resolve(look, Equipment.look_of(equip))


## 目前這欄換到下一個（delta=1）或上一個選項。已解鎖就直接穿上。
func cycle(delta: int) -> void:
	var slot := current_slot()
	if slot == "bag":
		if current_entry().get("action", "") != "":
			bag_used.emit(current_entry())
		return
	if slot.begins_with("eq."):
		_cycle_equip(slot.substr(3), delta)
		return
	if slot == "set":
		_cycle_set(delta)
		return
	var opts := Wardrobe.owned_options(slot, state)
	if opts.is_empty():
		return
	var idx := -1 if delta > 0 else 0
	for i in opts.size():
		if opts[i]["id"] == look[slot]:
			idx = i
	look[slot] = opts[posmod(idx + delta, opts.size())]["id"]
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


## 套裝欄：在每件都拿到的套裝之間換，整組衣著一起穿上。
func _cycle_set(delta: int) -> void:
	var all := Wardrobe.sets().filter(func(s): return Wardrobe.set_unlocked(s["id"], state))
	if all.is_empty():
		return
	var cur := Wardrobe.matching_set(shown())
	var idx := -1
	for i in all.size():
		if all[i]["id"] == cur:
			idx = i
	if idx < 0 and delta < 0:
		idx = 0
	var s: Dictionary = all[posmod(idx + delta, all.size())]
	for slot in s["pieces"]:
		look[slot] = s["pieces"][slot]
		worn[slot] = look[slot]
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
	var group: String = "物品" if in_bag else rows[row]["group"]
	var names := []
	for g in PAGES:
		names.append("【%s】" % g if g == group else g)
	tabs.text = "　".join(names)
	bag_box.visible = in_bag
	_refresh_bag()
	for i in rows.size():
		var slot: String = rows[i]["slot"]
		var here := not in_bag and i == row
		rows[i]["box"].visible = not in_bag and rows[i]["group"] == group
		var text := ""
		var color := InkUI.CINNABAR if here else InkUI.INK
		if slot.begins_with("eq."):
			var eid: String = equip.get(slot.substr(3), "")
			text = "%s・%s" % [Equipment.item(eid)["name"], Equipment.grade_name(eid)] if eid != "" else "不穿"
			color = Equipment.grade_color(eid) if eid != "" else InkUI.INK_SOFT
		elif slot == "set":
			text = Wardrobe.set_by_id(Wardrobe.matching_set(shown())).get("name", "自己搭配")
		else:
			text = Wardrobe.option(slot, look[slot]).get("name", "")
			if look[slot] == Wardrobe.EQUIP and equip.has(slot):
				text += "（%s）" % Equipment.item(equip[slot])["name"]
		rows[i]["value"].text = ("》 " + text + " 《") if here else text
		rows[i]["value"].add_theme_color_override("font_color", color)
		rows[i]["name"].add_theme_color_override("font_color", InkUI.CINNABAR if here else InkUI.INK)
	var slot := current_slot()
	var lines := []
	if slot == "bag":
		var e := current_entry()
		if e.is_empty():
			lines.append("行囊是空的。打怪、做差事、找藏寶都會撿到東西。")
		else:
			lines.append("%s　%s%s" % [e["name"], e["kind"], "（身上）" if e.get("worn", false) else ""])
			lines.append(str(e.get("note", "")))
			match e.get("action", ""):
				"equip", "fashion":
					lines.append("←→ " + ("換下" if e.get("worn", false) else "穿上"))
				"weapon":
					lines.append("拿在手上" if e.get("worn", false) else "←→ 換上這把")
				"use":
					lines.append("←→ 服用")
	elif slot.begins_with("eq."):
		var eid: String = equip.get(slot.substr(3), "")
		if eid == "":
			lines.append("這一欄沒穿裝備。←→ 換已經拿到的（%d 件）。" % Equipment.owned_in_slot(state, slot.substr(3)).size())
		else:
			lines.append(Equipment.describe(eid))
			lines.append(Equipment.item(eid).get("note", ""))
		var total := Equipment.stat_text(Equipment.totals(equip))
		lines.append("全身合計：" + (total if total != "" else "無"))
		var aura := Equipment.aura(equip)
		if int(aura["grade"]) > 0:
			lines.append("周身：" + str(Equipment.data()["aura"][int(aura["grade"])]))
	elif slot == "set":
		var s := Wardrobe.set_by_id(Wardrobe.matching_set(shown()))
		lines.append(s.get("desc", "上衣、下裳、外罩、腰封、護腕、鞋靴都可以自己挑；←→ 換一整套。"))
		var missing := Wardrobe.sets().filter(func(st): return not Wardrobe.set_unlocked(st["id"], state)).map(func(st): return st["name"])
		if not missing.is_empty():
			lines.append("還沒湊齊：" + "、".join(missing) + "。每件都拿到才能一鍵換整套。")
	else:
		var o := Wardrobe.option(slot, look[slot])
		if o.get("desc", "") != "":
			lines.append(o["desc"])
		var missing := Wardrobe.options(slot).filter(func(x): return not Wardrobe.is_unlocked(slot, x["id"], state))
		if not missing.is_empty():
			var hints := missing.slice(0, 3).map(func(x): return "%s（%s）" % [x["name"], x.get("source", "？")])
			lines.append("還沒取得 %d 件：%s%s" % [missing.size(), "、".join(hints), "……" if missing.size() > 3 else ""])
	note.text = "\n".join(lines)


## 物品頁：游標附近的 BAG_LINES 行，分類寫在前面，身上的標「・身上」
func _refresh_bag() -> void:
	var start := clampi(bag_index - BAG_LINES / 2, 0, maxi(0, bag.size() - BAG_LINES))
	for i in BAG_LINES:
		var l: Label = bag_labels[i]
		var k := start + i
		if bag.is_empty() and i == 0:
			l.text = "》 （空） 《" if in_bag else "（空）"
			l.add_theme_color_override("font_color", InkUI.INK_SOFT)
			continue
		if k >= bag.size():
			l.text = ""
			continue
		var e: Dictionary = bag[k]
		var text := "%s｜%s%s%s" % [e["kind"], e["name"], " ×%d" % e["count"] if int(e["count"]) > 1 else "", "・身上" if e.get("worn", false) else ""]
		l.text = ("》 " + text + " 《") if k == bag_index and in_bag else text
		var color := InkUI.INK
		if e["kind"] == "裝備":
			color = Equipment.grade_color(e["ref"])
		if k == bag_index:
			color = InkUI.CINNABAR
		l.add_theme_color_override("font_color", color)


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
