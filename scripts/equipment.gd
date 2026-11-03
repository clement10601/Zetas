## 裝備：衣袍、腰封、護腕、鞋靴、頭冠、佩飾。有品階、有數值；時裝（scripts/wardrobe.gd）只換外觀、蓋在裝備上。
## 品階跟兵器一致（凡器、法器、靈器、法寶、仙器／魔器），數值乘 1 + grade_bonus×品階，跟兵器傷害同一條曲線。
## 資料在 content/equipment.json；身上穿的存在 state.game_data["equip"]（欄位 -> 裝備 id）。
## 擁有＝背包裡有這個物品名（掉落、差事、事件給的物品名等於裝備名就算入手）。全是純函式，數值集中在 json 調。
extends RefCounted

const PATH := "res://content/equipment.json"
const WEAPONS_PATH := "res://content/weapons.json"

static var _data: Dictionary = {}
static var _grades: Array = []


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_grades = JSON.parse_string(FileAccess.get_file_as_string(WEAPONS_PATH)).get("grades", [])
	return _data


static func slots() -> Array:
	return data()["slots"]


static func slot_ids() -> Array:
	return slots().map(func(s): return s["id"])


static func slot_name(slot: String) -> String:
	for s in slots():
		if s["id"] == slot:
			return s["name"]
	return slot


static func item(id: String) -> Dictionary:
	if not id.begins_with("equip."):
		return {}
	return data().get(id, {})


static func all_ids() -> Array:
	return data().keys().filter(func(k): return str(k).begins_with("equip."))


## 物品名對到裝備 id（沒有就空字串）
static func by_name(name: String) -> String:
	for id in all_ids():
		if data()[id]["name"] == name:
			return id
	return ""


static func owns(state, id: String) -> bool:
	return not item(id).is_empty() and state.items.has(item(id)["name"])


## 這一欄背包裡有的裝備，品階由低到高
static func owned_in_slot(state, slot: String) -> Array:
	var out := all_ids().filter(func(id): return data()[id]["slot"] == slot and owns(state, id))
	out.sort_custom(func(a, b): return int(data()[a]["grade"]) < int(data()[b]["grade"]))
	return out


static func grade_of(id: String) -> int:
	return int(item(id).get("grade", 0))


## 品階名：跟兵器同一張表；第 5 階魔緣的叫魔器
static func grade_name(id: String) -> String:
	data()
	var it := item(id)
	if it.is_empty():
		return ""
	var line: String = it.get("line", "")
	if line != "" and data()["line_names"].has(line):
		return data()["line_names"][line]
	return str(_grades[clampi(int(it["grade"]), 0, _grades.size() - 1)])


static func grade_color(id: String) -> Color:
	var it := item(id)
	if it.is_empty():
		return Color(data()["grade_colors"][0])
	if it.has("line") and data()["line_colors"].has(it["line"]):
		return Color(data()["line_colors"][it["line"]])
	return Color(data()["grade_colors"][clampi(int(it["grade"]), 0, data()["grade_colors"].size() - 1)])


static func multiplier(grade: int) -> float:
	return 1.0 + float(data().get("grade_bonus", 0.25)) * grade


## 一件裝備的數值：欄位底數＋詞條，全部乘品階倍率
static func stats(id: String) -> Dictionary:
	var it := item(id)
	var out := {}
	if it.is_empty() or it.get("plain", false):
		return out
	var m := multiplier(int(it["grade"]))
	var base: Dictionary = data()["base"].get(it["slot"], {})
	for k in base:
		out[k] = float(out.get(k, 0.0)) + float(base[k]) * m
	for k in it.get("affixes", []):
		out[k] = float(out.get(k, 0.0)) + float(data()["affix_values"][k]) * m
	for k in out:
		if not data()["stats"][k]["pct"]:
			out[k] = roundi(out[k])
	return out


## 身上全部裝備加總（有上限：護體、身法、回氣）
static func totals(equip: Dictionary) -> Dictionary:
	var out := {"hp": 0, "mp": 0, "guard": 0.0, "speed": 0.0, "regen": 0.0}
	for slot in equip:
		var s := stats(str(equip[slot]))
		for k in s:
			out[k] = out[k] + s[k]
	for k in data()["caps"]:
		out[k] = minf(float(out[k]), float(data()["caps"][k]))
	return out


## 「氣血 +8、護體 5%」
static func stat_text(s: Dictionary) -> String:
	var parts := []
	for k in ["hp", "mp", "guard", "speed", "regen"]:
		if not s.has(k) or is_zero_approx(float(s[k])):
			continue
		var info: Dictionary = data()["stats"][k]
		parts.append("%s +%d%s" % [info["name"], roundi(float(s[k]) * 100.0) if info["pct"] else int(s[k]), "%" if info["pct"] else ""])
	return "、".join(parts)


## 「天青法衣（法器）　護體 +5%、護體 +4%」這種說明，衣櫃與紀錄用
static func describe(id: String) -> String:
	var it := item(id)
	if it.is_empty():
		return ""
	return "%s（%s）　%s" % [it["name"], grade_name(id), stat_text(stats(id))]


## 裝備穿在身上的樣子：欄位 -> wardrobe 選項 id
static func look_of(equip: Dictionary) -> Dictionary:
	var out := {}
	for slot in equip:
		var it := item(str(equip[slot]))
		if not it.is_empty():
			out[slot] = it["look"]
	return out


## 周身光效看身上最高品階的那件（時裝蓋不掉、也假裝不出來）；line 是仙／魔。
static func aura(equip: Dictionary) -> Dictionary:
	var best := {"grade": 0, "line": ""}
	for slot in equip:
		var it := item(str(equip[slot]))
		if it.is_empty():
			continue
		var g := int(it["grade"])
		if g > int(best["grade"]) or (g == int(best["grade"]) and best["line"] == "" and it.get("line", "") != ""):
			best = {"grade": g, "line": it.get("line", "")}
	return best


## 只留背包裡還有、欄位對得上的
static func normalize(equip, state) -> Dictionary:
	var out := {}
	if equip is Dictionary:
		for slot in equip:
			var id := str(equip[slot])
			if item(id).get("slot", "") == slot and owns(state, id):
				out[slot] = id
	return out
