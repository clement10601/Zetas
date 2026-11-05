## 玩家外觀：衣著逐件可換（上衣、下裳、外罩、腰封、護腕、鞋靴；套裝一鍵換一整組）、配件（頭飾、髮飾、肩飾、背飾、腰飾）與容貌。
## 選項與解鎖條件在 content/wardrobe.json；每個選項的分層立繪在 art/wardrobe/，位移在 content/wardrobe_layers.json
## （由 tools/inkpaint/wardrobe.py 畫出來）。compose() 照固定順序把圖層疊成一張全身立繪，跟原本的 player.disciple 同尺寸。
## 外觀存在 state.game_data["look"]，只管長相，不加數值。衣著、配件都要先拿到（物品欄裡有）才能穿，見 is_unlocked。這是「時裝」：裝備（scripts/equipment.gd）有品階數值，
## 穿在身上也有樣子；有裝備的欄位（衣袍、腰封、護腕、鞋靴、頭冠、佩飾）時裝選「隨裝備」（EQUIP）就顯示裝備，
## 選別的就蓋在裝備上面。resolve() 把「隨裝備」換成裝備的樣子，沒穿裝備就是預設那件。
extends RefCounted

const Conditions = preload("res://addons/zeworld/conditions.gd")

const CATALOG_PATH := "res://content/wardrobe.json"
const LAYERS_PATH := "res://content/wardrobe_layers.json"

## 疊圖順序（由後往前）：[圖層名, 決定這層的欄位]。要跟 tools/inkpaint/wardrobe.py 的 ORDER 一致。
## 衣物一件一層（上衣、外罩各分後袖／身／前袖），所以每件都能單獨換。
const ORDER := [
	["back", "back"], ["hair_back", "hair"], ["hair_acc_back", "hair_acc"], ["sleeve_back", "top"],
	["coat_sleeve_back", "coat"], ["gear", ""], ["bottom", "bottom"], ["shoes", "shoes"], ["top", "top"],
	["coat", "coat"], ["belt", "belt"], ["waist", "waist"], ["hair_under", "hair"], ["face", "face"],
	["hair_over", "hair"], ["eyes", "eyes"], ["brows", "brows"], ["hair_acc", "hair_acc"], ["head", "head"],
	["sleeve_front", "top"], ["cuffs", "cuffs"], ["coat_sleeve", "coat"], ["shoulder", "shoulder"],
]

## 會飄的圖層（背飾飄帶、後髮、髮帶長尾）：遊戲裡另疊一張放在身體後面，給 ink_halo 著色器單獨擺動，
## 跑、跳、御劍時才飄得起來。都在 ORDER 最前面（最後面那層），拆開疊順序不變。
const FLOW_LAYERS := ["back", "hair_back", "hair_acc_back"]
## 飄動層左右多留的空白（貼圖像素），飄帶往後甩出去才不會被切掉
const FLOW_PAD := 140

## 時裝「隨裝備」：這一欄顯示身上的裝備
const EQUIP := "equip"
const EQUIP_SLOTS := ["top", "belt", "cuffs", "shoes", "head", "waist"]
const EQUIP_OPTION := {"id": EQUIP, "name": "隨裝備", "desc": "顯示身上這一欄裝備的樣子；換成別的就是時裝，蓋在裝備上面，數值照算裝備的。"}

## 頭像裁切範圍（全身圖上頭肩的位置；外觀會加長飄帶、披風，不能照不透明範圍裁）
const PORTRAIT_RECT := Rect2(104, 0, 172, 172)

static var _catalog: Dictionary = {}
static var _layers: Dictionary = {}
static var _images: Dictionary = {}      # 圖層 key -> Image
static var _textures: Dictionary = {}    # 外觀簽名 -> ImageTexture


static func catalog() -> Dictionary:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	return _catalog


static func layers() -> Dictionary:
	if _layers.is_empty():
		_layers = JSON.parse_string(FileAccess.get_file_as_string(LAYERS_PATH))
	return _layers


static func slots() -> Array:
	return catalog()["slots"]


static func options(slot: String) -> Array:
	var opts: Array = catalog()["options"].get(slot, [])
	if EQUIP_SLOTS.has(slot):
		return [EQUIP_OPTION] + opts
	return opts


static func option(slot: String, id: String) -> Dictionary:
	for o in options(slot):
		if o["id"] == id:
			return o
	return {}


## 新角色：有裝備的欄位都「隨裝備」（入門裝備長得就是預設那套）
static func default_look() -> Dictionary:
	var d: Dictionary = catalog()["default"].duplicate()
	for slot in EQUIP_SLOTS:
		d[slot] = EQUIP
	return d


## 「隨裝備」換成裝備的樣子（equip_look：欄位 -> 選項 id，見 Equipment.look_of）；沒穿那一欄就是 content 的預設那件。
static func resolve(look: Dictionary, equip_look: Dictionary = {}) -> Dictionary:
	var out := look.duplicate()
	for slot in EQUIP_SLOTS:
		if out.get(slot, EQUIP) == EQUIP:
			out[slot] = equip_look.get(slot, catalog()["default"][slot])
	return out


## 套裝：一鍵換上一整組衣著（pieces），之後每件還能自己換。
static func sets() -> Array:
	return catalog().get("sets", [])


static func set_by_id(id: String) -> Dictionary:
	for s in sets():
		if s["id"] == id:
			return s
	return {}


## 這身衣著正好是哪一套（每件都對上）；混搭的回傳空字串。
static func matching_set(look: Dictionary) -> String:
	for s in sets():
		var all := true
		for slot in s["pieces"]:
			if look.get(slot, "") != s["pieces"][slot]:
				all = false
				break
		if all:
			return s["id"]
	return ""


## 套裝的每件都解鎖了沒。
static func set_unlocked(id: String, state) -> bool:
	var s := set_by_id(id)
	for slot in s.get("pieces", {}):
		if not is_unlocked(slot, s["pieces"][slot], state):
			return false
	return not s.is_empty()


## 補齊缺的欄位、換掉不認得的選項（舊存檔、改過清單的存檔都能讀）。
## 舊存檔只有一個 outfit（整套）：換成那一套的各件。
static func normalize(look) -> Dictionary:
	var out := default_look()
	if look is Dictionary and look.has("outfit") and not look.has("top"):
		look = look.duplicate()
		look.merge(set_by_id(str(look["outfit"])).get("pieces", {}), true)
	if look is Dictionary:
		for slot in out:
			var id = look.get(slot)
			if id is String and not option(slot, id).is_empty():
				out[slot] = id
	return out


## 這件能不能穿：容貌看條件；衣著、配件要物品欄裡有（「不穿」「隨裝備」永遠可以）。
static func is_unlocked(slot: String, id: String, state) -> bool:
	var o := option(slot, id)
	if o.is_empty():
		return false
	if is_appearance(slot):
		return conditions_met(slot, id, state)
	if id == "" or id == EQUIP:
		return true
	if _by_has_item(o):
		return conditions_met(slot, id, state)
	return int(state.items.get(item_name(slot, id), 0)) > 0


static func conditions_met(slot: String, id: String, state) -> bool:
	return Conditions.all_true(option(slot, id).get("unlock", []), state)


## 容貌（髮型、臉型……）是身體，不是物品，不用取得
static func is_appearance(slot: String) -> bool:
	for s in slots():
		if s["id"] == slot:
			return s.get("group", "") == "容貌"
	return false


## unlock 寫 has_item 的：跟著那件物品走（仙裳、魔袍那種一件物品帶一整組樣子）
static func _by_has_item(o: Dictionary) -> bool:
	var u: Array = o.get("unlock", [])
	return not u.is_empty() and u.all(func(c): return c.get("type", "") == "has_item")


## 這件時裝在物品欄裡叫什麼（「不穿」沒有）
static func item_name(slot: String, id: String) -> String:
	var o := option(slot, id)
	if o.is_empty() or id == "" or id == EQUIP or is_appearance(slot):
		return ""
	if _by_has_item(o):
		return str(o["unlock"][0]["item"])
	return str(o.get("item", o["name"]))


## 條件（境界、旗標）一成立就發進物品欄的時裝
static func granted_by_conditions(slot: String, id: String) -> bool:
	var o := option(slot, id)
	return not is_appearance(slot) and not o.get("unlock", []).is_empty() and not _by_has_item(o)


## 物品名 -> [欄位, 選項 id]（不是時裝就空陣列）；只認時裝自己的名字，裝備名由 equipment.gd 管
static func by_item(name: String) -> Array:
	for slot in catalog()["options"]:
		if is_appearance(slot):
			continue
		for o in catalog()["options"][slot]:
			if o["id"] != "" and not _by_has_item(o) and str(o.get("item", o["name"])) == name:
				return [slot, o["id"]]
	return []


## 開局就有的時裝物品名
static func starter_items() -> Array:
	return catalog().get("starter", []).map(func(ref): return item_name(str(ref).get_slice("/", 0), str(ref).get_slice("/", 1)))


## 這一欄能穿的選項（含「不穿」「隨裝備」），照清單順序
static func owned_options(slot: String, state) -> Array:
	return options(slot).filter(func(o): return is_unlocked(slot, o["id"], state))


## 外觀裡沒有（還沒拿到、或條件後來不成立）的欄位換回預設；預設那件也沒有就不穿。
static func only_unlocked(look: Dictionary, state) -> Dictionary:
	var out := look.duplicate()
	var d := default_look()
	for slot in out:
		if not is_unlocked(slot, out[slot], state):
			out[slot] = d[slot]
			if not is_unlocked(slot, out[slot], state) and not option(slot, "").is_empty():
				out[slot] = ""
	return out


static func layer_keys(look: Dictionary) -> Array:
	var keys := []
	for entry in ORDER:
		var layer_name: String = entry[0]
		var field: String = entry[1]
		var val: String = look.get(field, "") if field != "" else ""
		if val == EQUIP:
			val = catalog()["default"][field]
		match field:
			"":
				keys.append(layer_name)
			"hair":
				keys.append("%s/%s/%s" % [layer_name, look["hair"], look["hair_color"]])
			"brows":
				keys.append("brows/%s/%s" % [look["brows"], look["hair_color"]])
			_:
				if val == "":
					continue
				if field == "hair_acc":
					keys.append("%s/%s/%s" % [layer_name, val, look["hair"]])
				elif field == "cuffs":
					var top: String = look["top"] if look["top"] != EQUIP else catalog()["default"]["top"]
					keys.append("cuffs/%s/%s" % [val, option("top", top).get("sleeve", "wide")])
				else:
					keys.append("%s/%s" % [layer_name, val])
	return keys


static func _image(key: String) -> Image:
	if _images.has(key):
		return _images[key]
	var img: Image = null
	var info: Dictionary = layers()["layers"].get(key, {})
	if not info.is_empty():
		var tex: Texture2D = load("res://art/" + info["file"])
		if tex != null:
			img = tex.get_image()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
	_images[key] = img
	return img


## 疊好的全身立繪。同一套外觀只疊一次。
## part："all" 整張（頭像、心魔鏡像）；"body" 不含飄動層；"flow" 只有飄動層，左右各多 FLOW_PAD 空白。
static func compose(look: Dictionary, part := "all") -> Texture2D:
	look = normalize(look)
	var keys := layer_keys(look)
	if part != "all":
		keys = keys.filter(func(k): return FLOW_LAYERS.has(str(k).get_slice("/", 0)) == (part == "flow"))
	var sig := part + ":" + "|".join(keys)
	if _textures.has(sig):
		return _textures[sig]
	var size: Array = layers()["size"]
	var pad := FLOW_PAD if part == "flow" else 0
	var canvas := Image.create(int(size[0]) + 2 * pad, int(size[1]), false, Image.FORMAT_RGBA8)
	for key in keys:
		var img := _image(key)
		if img == null:
			continue
		var info: Dictionary = layers()["layers"][key]
		canvas.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(int(info["x"]) + pad, int(info["y"])))
	var tex := ImageTexture.create_from_image(canvas)
	_textures[sig] = tex
	return tex


static func slot_title(slot: String) -> String:
	for s in slots():
		if s["id"] == slot:
			return s["name"]
	return slot
