## 玩家外觀：容貌（臉型、眼、眉、髮型、髮色）與衣櫃（衣著、頭飾、背飾、腰飾）。
## 選項與解鎖條件在 content/wardrobe.json；每個選項的分層立繪在 art/wardrobe/，位移在 content/wardrobe_layers.json
## （由 tools/inkpaint/wardrobe.py 畫出來）。compose() 照固定順序把圖層疊成一張全身立繪，跟原本的 player.disciple 同尺寸。
## 外觀存在 state.game_data["look"]，只管長相，不加數值。
extends RefCounted

const Conditions = preload("res://addons/zeworld/conditions.gd")

const CATALOG_PATH := "res://content/wardrobe.json"
const LAYERS_PATH := "res://content/wardrobe_layers.json"

## 疊圖順序（由後往前）：[圖層名, 決定這層的欄位]。要跟 tools/inkpaint/wardrobe.py 的 ORDER 一致。
const ORDER := [
	["back", "back"], ["hair_back", "hair"], ["sleeve_back", "outfit"], ["gear", ""], ["body", "outfit"],
	["waist", "waist"], ["hair_under", "hair"], ["face", "face"], ["hair_over", "hair"], ["eyes", "eyes"],
	["brows", "brows"], ["head", "head"], ["sleeve_front", "outfit"],
]

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
	return catalog()["options"].get(slot, [])


static func option(slot: String, id: String) -> Dictionary:
	for o in options(slot):
		if o["id"] == id:
			return o
	return {}


static func default_look() -> Dictionary:
	return catalog()["default"].duplicate()


## 補齊缺的欄位、換掉不認得的選項（舊存檔、改過清單的存檔都能讀）。
static func normalize(look) -> Dictionary:
	var out := default_look()
	if look is Dictionary:
		for slot in out:
			var id = look.get(slot)
			if id is String and not option(slot, id).is_empty():
				out[slot] = id
	return out


static func is_unlocked(slot: String, id: String, state) -> bool:
	var o := option(slot, id)
	if o.is_empty():
		return false
	return Conditions.all_true(o.get("unlock", []), state)


## 外觀裡還沒解鎖的欄位換回預設（試穿過、或條件後來不成立時用）。
static func only_unlocked(look: Dictionary, state) -> Dictionary:
	var out := look.duplicate()
	var d := default_look()
	for slot in out:
		if not is_unlocked(slot, out[slot], state):
			out[slot] = d[slot]
	return out


static func layer_keys(look: Dictionary) -> Array:
	var keys := []
	for entry in ORDER:
		var layer_name: String = entry[0]
		var field: String = entry[1]
		match field:
			"":
				keys.append(layer_name)
			"hair":
				keys.append("%s/%s/%s" % [layer_name, look["hair"], look["hair_color"]])
			"brows":
				keys.append("brows/%s/%s" % [look["brows"], look["hair_color"]])
			"outfit":
				keys.append("%s/%s" % [layer_name, look["outfit"]])
			_:
				if look.get(field, "") != "":
					keys.append("%s/%s" % [field, look[field]])
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
static func compose(look: Dictionary) -> Texture2D:
	look = normalize(look)
	var keys := layer_keys(look)
	var sig := "|".join(keys)
	if _textures.has(sig):
		return _textures[sig]
	var size: Array = layers()["size"]
	var canvas := Image.create(int(size[0]), int(size[1]), false, Image.FORMAT_RGBA8)
	for key in keys:
		var img := _image(key)
		if img == null:
			continue
		var info: Dictionary = layers()["layers"][key]
		canvas.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(int(info["x"]), int(info["y"])))
	var tex := ImageTexture.create_from_image(canvas)
	_textures[sig] = tex
	return tex
