## 按鍵設定：所有遊戲動作都走 Godot 的 InputMap，預設兩組鍵盤配置同時有效，也支援手把。
##   方向鍵組（右手方向、左手動作，楓之谷／九日式）：←→↑↓ 移動，Z 跳、X 攻擊、C 閃避、V 御劍
##   WASD 組（左手方向、右手動作，空洞騎士鍵盤式）：WASD 移動，K 跳、J 攻擊、L 閃避、I 御劍
##   兩組都能用的：空白 跳、Shift 閃避、E 交談／傳送（↑、W 也可以）
## 每個動作三格鍵位（方向鍵組／WASD 組／其他），玩家可以在按鍵設定畫面改，存在 user://keys.json。
## 改鍵時同一個鍵只會留在一個動作上（↑／W 同時是「上」和「交談」例外）。
extends RefCounted

const SLOTS := 3
const SLOT_NAMES := ["方向鍵組", "WASD 組", "其他"]
const DEADZONE := 0.4

## keys：三格實體鍵碼（0＝空）。pad：手把按鈕。axis：[軸, 方向]，給類比搖桿。
## fixed：不給改（只顯示）。
const ACTIONS := [
	{"id": "move_left", "name": "左", "keys": [KEY_LEFT, KEY_A, 0],
		"pad": [JOY_BUTTON_DPAD_LEFT], "axis": [JOY_AXIS_LEFT_X, -1.0]},
	{"id": "move_right", "name": "右", "keys": [KEY_RIGHT, KEY_D, 0],
		"pad": [JOY_BUTTON_DPAD_RIGHT], "axis": [JOY_AXIS_LEFT_X, 1.0]},
	{"id": "move_up", "name": "上（爬繩梯、往上看）", "keys": [KEY_UP, KEY_W, 0],
		"pad": [JOY_BUTTON_DPAD_UP], "axis": [JOY_AXIS_LEFT_Y, -1.0]},
	{"id": "move_down", "name": "下（爬繩梯、下平台）", "keys": [KEY_DOWN, KEY_S, 0],
		"pad": [JOY_BUTTON_DPAD_DOWN], "axis": [JOY_AXIS_LEFT_Y, 1.0]},
	{"id": "jump", "name": "跳", "keys": [KEY_Z, KEY_K, KEY_SPACE], "pad": [JOY_BUTTON_A]},
	{"id": "attack", "name": "攻擊", "keys": [KEY_X, KEY_J, 0], "pad": [JOY_BUTTON_X]},
	{"id": "dash", "name": "閃避", "keys": [KEY_C, KEY_L, KEY_SHIFT],
		"pad": [JOY_BUTTON_B, JOY_BUTTON_RIGHT_SHOULDER]},
	{"id": "fly", "name": "御劍（空中）", "keys": [KEY_V, KEY_I, 0], "pad": [JOY_BUTTON_Y]},
	{"id": "art", "name": "術法（主修功法的招牌術法）", "keys": [KEY_F, KEY_U, 0], "pad": []},
	{"id": "gear", "name": "兵器・功法", "keys": [KEY_G, KEY_O, 0], "pad": []},
	{"id": "interact", "name": "交談・傳送・拿取", "keys": [KEY_UP, KEY_W, KEY_E], "pad": [JOY_BUTTON_DPAD_UP]},
	{"id": "meditate", "name": "打坐", "keys": [KEY_M, 0, 0], "pad": [JOY_BUTTON_LEFT_SHOULDER]},
	{"id": "breakthrough", "name": "突破", "keys": [KEY_B, 0, 0], "pad": [JOY_BUTTON_LEFT_STICK]},
	{"id": "map", "name": "地圖", "keys": [KEY_T, 0, 0], "pad": [JOY_BUTTON_BACK]},
	{"id": "wardrobe", "name": "衣櫃・容貌", "keys": [KEY_Y, 0, 0], "pad": [JOY_BUTTON_RIGHT_STICK]},
	{"id": "music", "name": "配樂開關", "keys": [KEY_N, 0, 0], "pad": []},
	{"id": "settings", "name": "按鍵設定", "keys": [KEY_ESCAPE, KEY_F10, 0], "pad": [JOY_BUTTON_START]},
]

## 可以共用同一個鍵的動作（楓之谷式：站在 NPC 旁邊按 ↑ 就是交談）。
const SHARED := [["move_up", "interact"]]

const NAMES := {
	KEY_LEFT: "←", KEY_RIGHT: "→", KEY_UP: "↑", KEY_DOWN: "↓",
	KEY_SPACE: "空白", KEY_SHIFT: "Shift", KEY_CTRL: "Ctrl", KEY_ALT: "Alt",
	KEY_ENTER: "Enter", KEY_KP_ENTER: "Enter", KEY_ESCAPE: "Esc", KEY_TAB: "Tab",
	KEY_BACKSPACE: "Backspace", KEY_CAPSLOCK: "CapsLock",
}

static var bindings := {}   # id -> [三格鍵碼]
static var _initialized := false


## 建立（或重建）InputMap。path 空字串＝不讀檔（測試用）。
static func setup(path := "") -> void:
	bindings.clear()
	for a in ACTIONS:
		bindings[a["id"]] = (a["keys"] as Array).duplicate()
	if path != "" and FileAccess.file_exists(path):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(path))
		if saved is Dictionary:
			for id in saved:
				if bindings.has(id) and saved[id] is Array and saved[id].size() == SLOTS:
					bindings[id] = saved[id].map(func(k): return int(k))
	_apply()
	_initialized = true


static func ensure() -> void:
	if not _initialized:
		setup()


static func save(path: String) -> void:
	if path == "":
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(bindings))


static func reset(path := "") -> void:
	bindings.clear()
	for a in ACTIONS:
		bindings[a["id"]] = (a["keys"] as Array).duplicate()
	_apply()
	save(path)


static func action(id: String) -> Dictionary:
	for a in ACTIONS:
		if a["id"] == id:
			return a
	return {}


static func _apply() -> void:
	for a in ACTIONS:
		var id: String = a["id"]
		if InputMap.has_action(id):
			InputMap.erase_action(id)
		InputMap.add_action(id, DEADZONE)
		for kc in bindings[id]:
			if kc != 0:
				var ev := InputEventKey.new()
				ev.physical_keycode = kc
				InputMap.action_add_event(id, ev)
		for b in a.get("pad", []):
			var pb := InputEventJoypadButton.new()
			pb.button_index = b
			InputMap.action_add_event(id, pb)
		if a.has("axis"):
			var m := InputEventJoypadMotion.new()
			m.axis = a["axis"][0]
			m.axis_value = a["axis"][1]
			InputMap.action_add_event(id, m)


static func _shared(a: String, b: String) -> bool:
	for pair in SHARED:
		if a in pair and b in pair:
			return true
	return false


## 把 kc 放到 id 的第 slot 格。回傳被搶走這個鍵的動作名稱（沒有就是空陣列）。
static func rebind(id: String, slot: int, kc: int, path := "") -> Array:
	var taken: Array = []
	for other in bindings:
		if kc == 0 or other == id or _shared(id, other):
			continue
		var keys: Array = bindings[other]
		for i in SLOTS:
			if keys[i] == kc:
				keys[i] = 0
				taken.append(action(other)["name"])
	# 同一個動作的其他格也不要重複
	for i in SLOTS:
		if kc != 0 and i != slot and bindings[id][i] == kc:
			bindings[id][i] = 0
	bindings[id][slot] = kc
	_apply()
	save(path)
	return taken


static func key_name(kc: int) -> String:
	if kc == 0:
		return "—"
	if NAMES.has(kc):
		return NAMES[kc]
	return OS.get_keycode_string(kc)


## 這個動作所有的鍵，用「/」串起來，例如「Z/K/空白」。
static func label(id: String) -> String:
	ensure()
	var names: Array = []
	for kc in bindings.get(id, []):
		if kc != 0 and not names.has(key_name(kc)):
			names.append(key_name(kc))
	return "/".join(names) if not names.is_empty() else "（未設定）"


## 畫面提示用的短版：最多兩個鍵，先方向鍵組、再「其他」、再 WASD 組，例如 ↑/E、Z/空白、X/J。
static func hint(id: String) -> String:
	ensure()
	var keys: Array = bindings.get(id, [0, 0, 0])
	var names: Array = []
	for i in [0, 2, 1]:
		if keys[i] != 0 and names.size() < 2 and not names.has(key_name(keys[i])):
			names.append(key_name(keys[i]))
	return "/".join(names) if not names.is_empty() else "（未設定）"


## 一行操作說明（畫面最下面那條）。
static func help_line() -> String:
	ensure()
	return "  ".join([
		"%s 移動" % _pair("move_left", "move_right"),
		"%s 跳" % label("jump"),
		"%s 攻擊" % label("attack"),
		"%s 閃避" % label("dash"),
		"%s 術法" % label("art"),
		"%s 兵器・功法" % label("gear"),
		"%s 交談・傳送" % hint("interact"),
		"%s+跳 下平台" % hint("move_down"),
		"1-4 選擇",
		"%s 地圖" % hint("map"),
		"%s 打坐" % hint("meditate"),
		"%s 突破" % hint("breakthrough"),
		"%s 衣櫃" % hint("wardrobe"),
		"%s 按鍵設定" % hint("settings"),
	])


## 左右兩個動作按格配成一對，例如「←→/AD」。
static func _pair(a: String, b: String) -> String:
	var names: Array = []
	for i in SLOTS:
		var l: int = bindings[a][i]
		var r: int = bindings[b][i]
		if l != 0 and r != 0:
			names.append(key_name(l) + key_name(r))
	return "/".join(names) if not names.is_empty() else label(a) + "・" + label(b)


## 第一個有設定的鍵，例如「↑」。
static func first(id: String) -> String:
	ensure()
	for kc in bindings.get(id, []):
		if kc != 0:
			return key_name(kc)
	return "—"
