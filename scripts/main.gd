## 遊戲主控：橫軸地圖、玩家、角色，並把 ZeWorld 內容包與導演接到畫面上。
## 地圖有單向平台與繩梯（chunks.json 的 platforms／ropes），操作見 scripts/player.gd。
## 地圖兩端有傳送點，站上去按 ↑ 走到相鄰地區（regions.json 的 exits）；也可以按 T 開地圖直接去。
## 移動要花時辰。地區裡的常駐 NPC（regions.json 的 residents）靠近按 ↑ 或 E 說話。
## 身法（輕身術、踏葉、御風、土遁、御劍）隨境界與修為領悟；有些平台要身法才上得去，
## 上面的寶物（chunks.json 的 caches）按 ↑ 拿。區塊的 walls：cliff 是可以踏葉的石壁，thin 是土遁穿得過的薄牆。
## J 攻擊，敵人近身會傷人，血量歸零就重傷倒地（事件以失敗結算）。M 打坐增加修為、回滿血，
## 修為圓滿後按 B 突破境界。
## 除錯鍵用來快速製造觸發條件：F1 放走白狐、F2 過一天、F3 換時辰、F4 突破境界、
## F6 請導演生成一個新事件、F5 存檔、F9 讀檔。
## 導演服務沒開時一切照常，只是不會有新事件與即時台詞。
extends Node2D

const WorldState = preload("res://addons/zeworld/world_state.gd")
const PackPool = preload("res://addons/zeworld/pack_pool.gd")
const TriggerJudge = preload("res://addons/zeworld/trigger_judge.gd")
const PackRunner = preload("res://addons/zeworld/pack_runner.gd")
const DirectorClient = preload("res://addons/zeworld/director_client.gd")
const AssetLibrary = preload("res://addons/zeworld/asset_library.gd")
const Player = preload("res://scripts/player.gd")
const Cultivation = preload("res://scripts/cultivation.gd")
const Playlog = preload("res://scripts/playlog.gd")

const FLOOR_Y := 560.0
const START_REGION := "region.qingyun_foothills"
## 地區要求的最低境界（tier index）；黑風嶺築基以上才准去
const REGION_MIN_TIER := {"region.heifeng_ridge": 1}
## 補貨排程：每個地區、目前境界至少備著幾個沒玩過的事件
const RESTOCK_TARGET := 3
const HEART_DEMON_HINT := "突破到%s時的心魔幻境。心魔是玩家的鏡像，拿玩家經歷裡最難面對的事（history 裡的選擇、NPC 的記憶、karma 傾向）來質問玩家，每個玩家的心魔都該不同。地圖只用心魔幻境區塊（地圖標籤 illusion），心魔用模板 boss.heart_demon_mirror。tier_range 從%s到%s，不要設定 meta.region。突破那一刻就要觸發：遊戲會自己加 tier_up 條件，trigger.all 不要再加任何條件（例如上一關的旗標），否則條件不成立心魔就永遠錯過。通過時設旗標 %s_heart_demon_cleared。"
const ENCOUNTER_HINT := "今日奇遇：發生在玩家目前所在地區的小小偶遇，幾分鐘就能玩完，可以呼應玩家最近的經歷。今天就要能觸發：觸發條件只用這個地區區塊有的地圖標籤，可加時辰，不要用天數或其他事件才會立的旗標。獎勵要小。"
const ATTACK_RANGE := 90.0
## 敵人走在地面上：玩家腳離地面超過這個高度就打不到、也不會被打到
const MELEE_HEIGHT := 90.0
const PORTAL_INSET := 50.0        # 傳送點離地圖邊緣多遠
const INTERACT_RANGE := 40.0
const ATTACK_COOLDOWN := 0.35
const ENEMY_REACH := 44.0
const ENEMY_HIT_INTERVAL := 1.0
## 一句話停留不到「預估閱讀時間 × 這個比例」就翻頁，算跳過（中文約每秒 8 字）
const SKIP_FACTOR := 0.3
const READ_CHARS_PER_SEC := 8.0
const HOSTILE_SPEED := 70.0
const SAVE_ID := "save.001"

## 測試時設成空字串可停用存檔／導演生成資料夾；use_director 設 false 可完全不連導演。
var save_path := "user://save.json"
var generated_dir := "user://generated"
var use_director := true
## 素材清單；沒有圖的角色與場景畫色塊
var assets_path := "res://content/assets.json"
var art
## 遊玩紀錄；測試時設空字串停用
var playlog_path := "user://playlog.jsonl"
var playlog
var pack_stats: Dictionary = {}   # 目前事件的 {started, lines, skipped, rewritten}
var line_shown_at := 0
var line_length := 0
## 每天有奇遇的機率（測試可設 1.0）
var encounter_chance := 0.5
var heart_demon_pending := ""     # 已請導演準備心魔、還沒回來的境界
var encounter_pending := false
var director

var state
var pool: Array = []
var chunks: Dictionary = {}
var loot: Dictionary = {}
var regions: Dictionary = {}
var runner = null

var level: Node2D
var player: CharacterBody2D
var points: Dictionary = {}       # point id -> x
var map_width := 0.0
var chunk_x: Dictionary = {}      # chunk id -> 地圖上的起點 x
var portals: Array = []           # 落腳地圖兩端的傳送點 {x, to, view}
var residents: Dictionary = {}    # 常駐 NPC id -> {view, info, said}
var caches: Dictionary = {}       # 這張地圖上還沒拿的寶物 id -> {view, info}
var prompt_label: Label           # 「↑ 前往……」「↑ 交談」提示
var actor_views: Dictionary = {}  # actor id -> Node2D
var actor_hp: Dictionary = {}
var actor_power: Dictionary = {}  # actor id -> power，傷害與擊殺修為用
var enemy_cooldown: Dictionary = {}  # actor id -> 距離下一擊的秒數
var attack_cooldown := 0.0
var log_lines: Array = []

var hud_status: Label
var hud_objective: Label
var hud_log: Label
var dialogue_panel: PanelContainer
var dialogue_label: Label
var current_choices: Array = []
var travel_options: Array = []    # 地圖開著時可去的地區 id
var lingering := false            # 事件結束時最後一句先留在畫面上，按空白才關
var fits: Dictionary = {}         # 決策模型給的貼合度 {內容包 id: 0–4}，觸發時和 priority 一起排序
var _ranked_key := ""             # 上次送評分的候選組合，沒變就不重送


func _ready() -> void:
	playlog = Playlog.new(playlog_path)
	load_content()
	director = DirectorClient.new()
	add_child(director)
	_read_director_config()
	director.pack_generated.connect(_on_pack_generated)
	director.pack_failed.connect(_on_pack_failed)
	director.ranking_ready.connect(func(scores: Dictionary): fits.merge(scores, true))
	director.line_rewritten.connect(func(node_id, text):
		if runner != null:
			runner.apply_rewrite(node_id, text))
	_build_hud()
	player = Player.new()
	add_child(player)
	if save_path != "" and state.load_file(save_path):
		add_log("讀取存檔：第 %d 天。" % state.day)
	if not regions.has(state.region):
		state.region = START_REGION
	if not state.game_data.has("hp"):
		state.game_data["hp"] = Cultivation.max_hp(state.tier_index)
	update_movement_skills()
	go_home()
	add_log("%s。T 地圖、F1 放走白狐、F2 過一天、F3 換時辰、F4 突破境界、F6 新事件。" % region_name())
	playlog.write("session_start", {"version": ProjectSettings.get_setting("application/config/version", ""),
		"director": use_director, "day": state.day, "region": state.region, "tier": state.tier_name()})
	request_followups()
	restock()
	prepare_heart_demon()
	check_triggers({"type": "enter_map"})


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and playlog != null:
		if runner != null:
			playlog.write("pack_end", _pack_end_row("quit"))
		playlog.write("session_end", {"day": state.day, "tier": state.tier_name()})


## 測試版：執行檔旁的 director_url.txt 指定導演位址、director_code.txt 放存取碼
## （環境變數 ZEWORLD_DIRECTOR_URL、ZEWORLD_DIRECTOR_CODE 優先）。
func _read_director_config() -> void:
	if OS.has_feature("editor"):
		return
	var dir := OS.get_executable_path().get_base_dir()
	var url := _read_text(dir.path_join("director_url.txt"))
	if OS.get_environment("ZEWORLD_DIRECTOR_URL") == "" and url.begins_with("http"):
		director.base_url = url
	var code := _read_text(dir.path_join("director_code.txt"))
	if OS.get_environment("ZEWORLD_DIRECTOR_CODE") == "" and code != "":
		director.access_code = code


static func _read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path).strip_edges() if FileAccess.file_exists(path) else ""


func load_content() -> void:
	state = WorldState.new(PackPool.load_ruleset("res://content/ruleset.json"))
	state.save_id = SAVE_ID
	pool = PackPool.load_dir("res://content/packs")
	if generated_dir != "":
		pool += PackPool.for_save(PackPool.load_dir(generated_dir), SAVE_ID)
	chunks = _read_json("res://content/chunks.json")
	loot = _read_json("res://content/loot.json")
	art = AssetLibrary.from_file(assets_path)
	regions = _read_json("res://content/regions.json")
	regions.erase("_comment")


func _read_json(path: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


# ---------- 地圖 ----------

## 依序拼接區塊，建地面與背景，記錄地點座標，並更新 state.map_tags。
func build_map(chunk_list: Array, spawn_point: String) -> void:
	if level:
		level.queue_free()
	for id in actor_views.keys():
		_remove_actor_view(id)
	level = Node2D.new()
	add_child(level)
	move_child(level, 0)
	points.clear()
	chunk_x.clear()
	portals = []
	residents.clear()
	caches.clear()
	var tags: Array = []
	var ropes: Array = []
	var x := 0.0
	var ordered := chunk_list.duplicate()
	ordered.sort_custom(func(a, b): return a["order"] < b["order"])
	for entry in ordered:
		var info: Dictionary = chunks.get(entry["chunk"], {})
		if info.is_empty():
			push_error("Zetas: unknown chunk %s" % entry["chunk"])
			continue
		var width: float = info["width"]
		var tex: Texture2D = art.texture(entry["chunk"])
		var bg: Control
		if tex:
			bg = TextureRect.new()
			bg.texture = tex
			bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			bg.stretch_mode = TextureRect.STRETCH_SCALE
		else:
			bg = ColorRect.new()
			bg.color = Color(info["color"])
		bg.position = Vector2(x, FLOOR_Y - 600)
		bg.size = Vector2(width, 600)
		level.add_child(bg)
		var name_label := Label.new()
		name_label.text = info["name"]
		name_label.position = Vector2(x + 24, FLOOR_Y - 580)
		name_label.modulate = Color(1, 1, 1, 0.5)
		level.add_child(name_label)
		chunk_x[entry["chunk"]] = x
		for p in info.get("points", {}):
			points[p] = x + float(info["points"][p])
		for plat in info.get("platforms", []):
			_add_platform(x + float(plat["x"]), FLOOR_Y - float(plat["h"]), float(plat["w"]), plat.get("skill", ""))
		for c in info.get("caches", []):
			if not found_caches().has(c["id"]):
				_add_cache(c, x)
		var last: bool = entry == ordered[-1]
		for w in info.get("walls", []):
			# 薄牆後面是暗室，只放在地圖盡頭；事件把這個區塊接在中間時不擋路
			if w.get("kind", "cliff") == "cliff" or last:
				_add_wall(x + float(w["x"]), float(w["w"]), float(w.get("bottom", 0)), float(w["top"]), w.get("kind", "cliff"))
		for r in info.get("ropes", []):
			var rope := {"x": x + float(r["x"]), "top": FLOOR_Y - float(r["top"]),
				"bottom": FLOOR_Y - float(r.get("bottom", 0)), "kind": r.get("kind", "rope")}
			_add_rope_view(rope)
			ropes.append(rope)
		for t in info.get("tags", []):
			if t not in tags:
				tags.append(t)
		x += width
	var ground := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(x + 400, 40)
	shape.position = Vector2(x / 2, FLOOR_Y + 20)
	ground.add_child(shape)
	var ground_rect := ColorRect.new()
	ground_rect.color = Color("#1c1a17")
	ground_rect.position = Vector2(-200, FLOOR_Y)
	ground_rect.size = Vector2(x + 400, 160)
	ground.add_child(ground_rect)
	for wall_x in [-10.0, x + 10.0]:
		var wall := CollisionShape2D.new()
		wall.shape = RectangleShape2D.new()
		wall.shape.size = Vector2(20, 1200)
		wall.position = Vector2(wall_x, FLOOR_Y - 600)
		ground.add_child(wall)
	level.add_child(ground)
	map_width = x
	state.map_tags = tags
	player.ropes = ropes
	player.floor_y = FLOOR_Y
	player.set_camera_limits(0.0, x, FLOOR_Y - 640.0, FLOOR_Y + 160.0)
	place_player(spawn_point)


## 單向平台：從下面跳得上去，站在上面按 ↓＋跳 下來。邊緣一條墨線（art-direction.md）。
## skill 不是空的：要那個身法才上得去，邊緣用淡青色提示。
func _add_platform(left: float, top: float, width: float, skill := "") -> void:
	var body := StaticBody2D.new()
	body.collision_layer = Player.PLATFORM_LAYER
	body.collision_mask = 0
	body.add_to_group("platform")
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(width, 12)
	shape.position = Vector2(left + width / 2, top + 6)
	shape.one_way_collision = true
	body.add_child(shape)
	var slab := ColorRect.new()
	slab.color = Color("#2a2620", 0.85)
	slab.position = Vector2(left, top)
	slab.size = Vector2(width, 14)
	body.add_child(slab)
	var edge := ColorRect.new()
	edge.color = Color("#9fc4c9") if skill != "" else Color("#0e0d0b")
	edge.position = Vector2(left, top)
	edge.size = Vector2(width, 3)
	body.add_child(edge)
	level.add_child(body)


func _add_wall(left: float, width: float, bottom: float, top: float, kind: String) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = Player.THIN_WALL_LAYER if kind == "thin" else Player.GROUND_LAYER
	body.collision_mask = 0
	body.add_to_group("wall")
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(width, top - bottom)
	shape.position = Vector2(left + width / 2, FLOOR_Y - (top + bottom) / 2)
	body.add_child(shape)
	var rect := ColorRect.new()
	rect.color = Color("#7a5a3a") if kind == "thin" else Color("#24221e")
	rect.position = Vector2(left, FLOOR_Y - top)
	rect.size = Vector2(width, top - bottom)
	body.add_child(rect)
	level.add_child(body)


## 寶物：一個小匣子，靠近按 ↑ 拿，每份存檔只拿一次。
func _add_cache(c: Dictionary, chunk_left: float) -> void:
	var view := Node2D.new()
	view.position = Vector2(chunk_left + float(c["x"]), FLOOR_Y - float(c.get("h", 0)))
	var box := ColorRect.new()
	box.color = Color("#b8862b")
	box.position = Vector2(-12, -16)
	box.size = Vector2(24, 16)
	view.add_child(box)
	level.add_child(view)
	caches[c["id"]] = {"view": view, "info": c}


func found_caches() -> Array:
	return state.game_data.get("found", [])


func nearby_cache() -> String:
	for id in caches:
		var pos: Vector2 = caches[id]["view"].position
		if absf(pos.x - player.position.x) < INTERACT_RANGE and absf(pos.y - player.feet()) < 8.0:
			return id
	return ""


func open_cache(id: String) -> void:
	var info: Dictionary = caches[id]["info"]
	var items: Array = loot.get(info["loot"], {}).get(info.get("tier", "common"), [])
	for item in items:
		state.add_item(item)
	state.game_data["found"] = found_caches() + [id]
	caches[id]["view"].queue_free()
	caches.erase(id)
	add_log("找到%s：%s" % [info.get("name", "藏寶"), "、".join(items)])
	playlog.write("cache", {"cache": id, "region": state.region})
	autosave()


## 修為或境界到了就領悟身法，並交給玩家角色。讀檔時也會重算。
func update_movement_skills() -> void:
	var known: Array = state.game_data.get("movement", [])
	for skill in Cultivation.MOVEMENT_SKILLS:
		if not known.has(skill) and Cultivation.knows_movement(skill, state.tier_index, cultivation(), state.flags):
			known = known + [skill]
			var rule: Dictionary = Cultivation.MOVEMENT_SKILLS[skill]
			add_log("領悟身法：%s（%s）。" % [rule["name"], rule["note"]])
			playlog.write("movement_skill", {"skill": skill, "tier": state.tier_name()})
	state.game_data["movement"] = known
	for skill in Cultivation.MOVEMENT_SKILLS:
		player.set(skill, known.has(skill))
	if not player.climbing:
		player.collision_mask = player.base_mask()


func _add_rope_view(rope: Dictionary) -> void:
	var view := Node2D.new()
	view.add_to_group("rope")
	var length: float = rope["bottom"] - rope["top"]
	if rope["kind"] == "ladder":
		for side in [-10.0, 8.0]:
			var rail := ColorRect.new()
			rail.color = Color("#6b4f35")
			rail.position = Vector2(rope["x"] + side, rope["top"])
			rail.size = Vector2(3, length)
			view.add_child(rail)
		for y in range(int(rope["top"]) + 10, int(rope["bottom"]), 18):
			var rung := ColorRect.new()
			rung.color = Color("#6b4f35")
			rung.position = Vector2(rope["x"] - 10, y)
			rung.size = Vector2(21, 3)
			view.add_child(rung)
	else:
		var line := ColorRect.new()
		line.color = Color("#4f7a3a") if rope["kind"] == "vine" else Color("#8a6d4a")
		line.position = Vector2(rope["x"] - 2, rope["top"])
		line.size = Vector2(4, length)
		view.add_child(line)
	level.add_child(view)


## 回到目前地區的落腳地圖。
func go_home() -> void:
	var info: Dictionary = regions.get(state.region, {})
	var list := []
	for i in info.get("home", []).size():
		list.append({"chunk": info["home"][i], "order": i})
	build_map(list, info.get("spawn", ""))
	_build_portals()
	_spawn_residents()


## 落腳地圖兩端的傳送點，通往 exits 裡相鄰的地區。
func _build_portals() -> void:
	var exits: Dictionary = regions.get(state.region, {}).get("exits", {})
	for side in exits:
		var to: String = exits[side]
		var px := PORTAL_INSET if side == "left" else map_width - PORTAL_INSET
		var view := Node2D.new()
		view.position = Vector2(px, FLOOR_Y)
		var glow := ColorRect.new()
		glow.color = Color("#cfe3f0", 0.35)
		glow.position = Vector2(-18, -84)
		glow.size = Vector2(36, 84)
		view.add_child(glow)
		var label := Label.new()
		var locked: bool = state.tier_index < int(REGION_MIN_TIER.get(to, 0))
		label.text = "%s %s%s" % ["←" if side == "left" else "→", region_name(to),
			"（需%s）" % state.ruleset["tiers"][REGION_MIN_TIER[to]] if locked else ""]
		# 右端的字往左排，免得被畫面邊緣切掉
		label.size = Vector2(200, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side == "left" else HORIZONTAL_ALIGNMENT_RIGHT
		label.position = Vector2(-18 if side == "left" else -182, -112)
		view.add_child(label)
		level.add_child(view)
		portals.append({"x": px, "to": to, "view": view})


## 地區的常駐 NPC，事件進行中先退場（事件可能自己會叫同一個人出來）。
func _spawn_residents() -> void:
	_clear_residents()
	if runner != null:
		return
	for r in regions.get(state.region, {}).get("residents", []):
		if not chunk_x.has(r["chunk"]):
			continue
		var view := _make_actor_view(r, false)
		view.position = Vector2(chunk_x[r["chunk"]] + float(r["x"]), FLOOR_Y)
		level.add_child(view)
		residents[r["id"]] = {"view": view, "info": r, "said": 0}


func _clear_residents() -> void:
	for id in residents:
		residents[id]["view"].queue_free()
	residents.clear()


func nearby_portal() -> Dictionary:
	for p in portals:
		if absf(p["x"] - player.position.x) < INTERACT_RANGE and player.feet() > FLOOR_Y - 8.0:
			return p
	return {}


func nearby_resident() -> String:
	for id in residents:
		var view: Node2D = residents[id]["view"]
		if absf(view.position.x - player.position.x) < INTERACT_RANGE * 1.5 and player.feet() > FLOOR_Y - MELEE_HEIGHT:
			return id
	return ""


## ↑／E：傳送點優先，再來是身邊的 NPC。回傳有沒有做事。
func interact() -> bool:
	if dialogue_panel.visible or player.climbing:
		return false
	var portal := nearby_portal()
	if not portal.is_empty():
		if runner != null:
			add_log("事情還沒了結，走不開。")
			return true
		travel_to(portal["to"], true)
		return true
	var cache := nearby_cache()
	if cache != "":
		open_cache(cache)
		return true
	var id := nearby_resident()
	if id != "":
		talk_to(id)
		return true
	return false


## 常駐 NPC 一次說一句，輪著說。空白鍵關掉。
func talk_to(id: String) -> void:
	var r: Dictionary = residents[id]
	var lines: Array = r["info"].get("lines", [])
	if lines.is_empty():
		return
	var line: String = lines[r["said"] % lines.size()]
	r["said"] += 1
	dialogue_label.text = "%s：%s\n  （空白鍵繼續）" % [r["info"]["name"], line]
	dialogue_panel.visible = true
	player.frozen = true
	lingering = true
	playlog.write("talk", {"npc": r["info"].get("memory_key", id), "region": state.region})


func region_name(id: String = "") -> String:
	return regions.get(id if id != "" else state.region, {}).get("name", "")


## 前往另一個地區：花掉 travel_hours 個時辰，換落腳地圖，請導演補貨，再看有沒有事件。
## by_portal：走傳送點過去的，出現在新地圖通往原地區的那一端。
func travel_to(id: String, by_portal := false) -> bool:
	if runner != null or not regions.has(id) or id == state.region:
		return false
	if state.tier_index < int(REGION_MIN_TIER.get(id, 0)):
		add_log("師門規矩：%s需%s以上方可前往。" % [region_name(id), state.ruleset["tiers"][REGION_MIN_TIER[id]]])
		return false
	var new_day := advance_time(int(regions[id].get("travel_hours", 1)))
	var from: String = state.region
	state.region = id
	go_home()
	if by_portal:
		for p in portals:
			if p["to"] == from:
				player.position = Vector2(p["x"] + (PORTAL_INSET if p["x"] < map_width / 2 else -PORTAL_INSET), FLOOR_Y - 40)
				player.velocity = Vector2.ZERO
				player.snap_camera()
	add_log("你來到%s。（第 %d 天・%s）" % [region_name(), state.day, state.time_of_day])
	playlog.write("travel", {"to": id, "day": state.day})
	if new_day:
		day_started()
	restock()
	autosave()
	check_triggers({"type": "enter_map"})
	return true


## 時辰往前走 steps 格，過了夜就是隔天。回傳是否換了一天。
func advance_time(steps: int) -> bool:
	var day_before: int = state.day
	var times: Array = state.ruleset["times_of_day"]
	for i in steps:
		var next: int = (times.find(state.time_of_day) + 1) % times.size()
		if next == 0:
			state.day += 1
		state.time_of_day = times[next]
	return state.day != day_before


func open_travel_menu() -> void:
	if runner != null or dialogue_panel.visible:
		return
	travel_options = regions.keys().filter(func(id): return id != state.region)
	var text := "前往何處？（目前在%s）" % region_name()
	for i in travel_options.size():
		var id: String = travel_options[i]
		var note := "（需%s）" % state.ruleset["tiers"][REGION_MIN_TIER[id]] if state.tier_index < int(REGION_MIN_TIER.get(id, 0)) else ""
		text += "\n  %d. %s・%d 個時辰%s" % [i + 1, region_name(id), int(regions[id].get("travel_hours", 1)), note]
	text += "\n  （Esc 取消）"
	dialogue_label.text = text
	dialogue_panel.visible = true
	player.frozen = true


func close_travel_menu() -> void:
	travel_options = []
	_hide_dialogue()


func choose_travel(i: int) -> void:
	if i < travel_options.size():
		var id: String = travel_options[i]
		close_travel_menu()
		travel_to(id)


func place_player(point: String) -> void:
	player.position = Vector2(points.get(point, 100.0), FLOOR_Y - 40)
	player.velocity = Vector2.ZERO
	player.snap_camera()


# ---------- 觸發與內容包 ----------

func check_triggers(event: Dictionary) -> void:
	if runner != null:
		return
	var pack := TriggerJudge.pick(pool, state, event, fits)
	if not pack.is_empty():
		start_pack(pack)


func start_pack(pack: Dictionary) -> void:
	add_log("【%s】%s" % [pack["meta"]["title"], pack["meta"]["summary"]])
	pack_stats = {"started": Time.get_ticks_msec(), "lines": 0, "skipped": 0, "rewritten": 0}
	playlog.write("pack_start", {"pack": pack["id"], "title": pack["meta"]["title"], "author": pack["meta"].get("author", ""),
		"request_tag": pack["meta"].get("request_tag", ""), "region": state.region, "day": state.day, "tier": state.tier_name()})
	_clear_residents()
	runner = PackRunner.new(pack, state)
	runner.actor_spawned.connect(_on_actor_spawned)
	runner.actor_despawned.connect(_remove_actor_view)
	runner.line_shown.connect(_on_line_shown)
	runner.line_updated.connect(_on_line_updated)
	runner.dialogue_ended.connect(_on_dialogue_ended)
	runner.objective_changed.connect(func(t): hud_objective.text = "目標：" + t)
	runner.reward_requested.connect(_on_reward)
	runner.presentation_requested.connect(_on_presentation)
	runner.finished.connect(_on_pack_finished)
	if pack.has("map"):
		build_map(pack["map"]["chunks"], pack["map"]["spawn"])
	runner.start()


func _pack_end_row(result: String) -> Dictionary:
	var row := {"pack": runner.pack["id"], "result": result,
		"seconds": snappedf((Time.get_ticks_msec() - int(pack_stats.get("started", 0))) / 1000.0, 0.1)}
	for k in ["lines", "skipped", "rewritten"]:
		row[k] = int(pack_stats.get(k, 0))
	return row


func _on_pack_finished(result: String) -> void:
	playlog.write("pack_end", _pack_end_row(result))
	var title: String = runner.pack["meta"]["title"]
	var had_map: bool = runner.pack.has("map")
	add_log("【%s】結束：%s" % [title, {"complete": "完成", "fail": "失敗", "abandon": "放棄"}[result]])
	for f in state.followups:
		if f["from_pack"] == runner.pack["id"]:
			add_log("（交給導演的後續：%s）" % f["hint"])
	runner = null
	hud_objective.text = ""
	if dialogue_panel.visible and current_choices.is_empty():
		lingering = true
	else:
		_hide_dialogue()
	update_movement_skills()  # 事件可能用旗標傳授身法
	if had_map:
		go_home()
	else:
		_spawn_residents()
	_refresh_status()
	request_followups()
	restock()
	autosave()


# ---------- 導演 ----------

## 把還沒送出的後續劇情請求交給導演。導演沒開就失敗退回，下次再送。
func request_followups() -> void:
	if not use_director:
		return
	for f in state.pending_followups():
		f["status"] = "requested"
		director.request_pack(state, f)


## 目前地區、境界可用的事件不夠時請導演補（送出中的請求也算存貨），並替現有候選事件重新評分。
func restock() -> void:
	if use_director:
		director.restock(state, PackPool.for_save(pool, SAVE_ID), RESTOCK_TARGET)
		rerank()


## 請導演的決策模型替這裡可能上場的事件評分。候選組合、天數、時辰沒變就不重送。
## 沒接決策模型時導演回 503，fits 維持空的，排序就是 priority。
func rerank() -> void:
	var mine := PackPool.for_save(pool, SAVE_ID)
	var cands := PackPool.stock(mine, state, state.region) + PackPool.stock(mine, state, "")
	if cands.size() < 2:
		return
	var ids := cands.map(func(p): return p["id"])
	ids.sort()
	var key := "%d|%s|%s|%s" % [state.day, state.time_of_day, state.region, ",".join(ids)]
	if key == _ranked_key:
		return
	_ranked_key = key
	director.request_ranking(state, cands, {"region": state.region, "time_of_day": state.time_of_day, "day": state.day})


## 新的一天：清掉過期的導演事件、送出後續劇情、擲今天的奇遇。
func day_started() -> void:
	for p in PackPool.expired(pool, state):
		pool.erase(p)
		if generated_dir != "":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(generated_dir.path_join(p["id"] + ".json")))
	request_followups()
	if use_director and not encounter_pending and randf() < encounter_chance:
		encounter_pending = true
		director.request_pack(state, {}, ENCOUNTER_HINT, state.region, {"tag": "encounter", "expires_after_days": 1})


## 請導演依玩家經歷準備下一個境界的心魔：修為快圓滿時才請，省得白花生成。
## 池子裡已有該境界的突破事件（例如手寫的築基心魔）就不請。
func prepare_heart_demon() -> void:
	var tiers: Array = state.ruleset["tiers"]
	if not use_director or state.tier_index + 1 >= tiers.size():
		return
	if cultivation() < Cultivation.HEART_DEMON_PREP * Cultivation.need(state.tier_index):
		return
	var next: String = tiers[state.tier_index + 1]
	if heart_demon_pending == next or has_breakthrough_pack(next):
		return
	heart_demon_pending = next
	var gate := [{"type": "tier_up", "to": next}]
	director.request_pack(state, {}, HEART_DEMON_HINT % [next, state.tier_name(), next, next], "",
		{"tag": "heart_demon", "gate": gate})


func has_breakthrough_pack(tier: String) -> bool:
	for p in pool:
		if state.seen_packs.has(p["id"]):
			continue
		for c in p["trigger"]["all"]:
			if c.get("type") == "tier_up" and c.get("to") == tier:
				return true
	return false


func request_fresh_event() -> void:
	if use_director:
		add_log("（請導演構思新事件……）")
		director.request_pack(state, {}, "", state.region)


func _on_pack_generated(pack: Dictionary, followup: Dictionary) -> void:
	for p in pool:
		if p["id"] == pack["id"]:
			return
	pool.append(pack)
	state.note_arrival(pack["id"])
	if generated_dir != "":
		PackPool.save_pack(pack, generated_dir)
	match pack["meta"].get("request_tag", ""):
		"heart_demon":
			heart_demon_pending = ""
		"encounter":
			encounter_pending = false
	if not followup.is_empty():
		for f in state.followups:
			if f.get("flag") == followup.get("flag"):
				f["status"] = "ready"
				f["pack"] = pack["id"]
	add_log("（導演備好了新事件：%s）" % pack["meta"]["title"])
	playlog.write("director_pack", {"pack": pack["id"], "request_tag": pack["meta"].get("request_tag", ""),
		"followup": not followup.is_empty(), "region": pack["meta"].get("region", "")})
	if use_director:
		rerank()
	autosave()
	if pack["meta"].get("request_tag", "") == "encounter":
		check_triggers({"type": "enter_map"})


func _on_pack_failed(followup: Dictionary, reason: String) -> void:
	playlog.write("director_fail", {"reason": reason, "followup": not followup.is_empty()})
	for f in state.followups:
		if f.get("flag") == followup.get("flag") and f.get("status") == "requested":
			f["status"] = ""
	if followup.is_empty():
		# 失敗訊號不帶請求種類：把主動請求都放掉，下次時機到了再請
		heart_demon_pending = ""
		encounter_pending = false
		add_log("（導演沒有回應：%s）" % reason)


func autosave() -> void:
	if save_path != "":
		state.save_file(save_path)


func load_game() -> void:
	if runner == null and save_path != "" and state.load_file(save_path):
		if not regions.has(state.region):
			state.region = START_REGION
		update_movement_skills()
		go_home()
		add_log("讀取存檔：第 %d 天，%s。" % [state.day, region_name()])


func _on_actor_spawned(actor: Dictionary) -> void:
	var hostile: bool = actor["disposition"] == "hostile"
	var view := _make_actor_view(actor, hostile)
	view.position = Vector2(points.get(actor.get("spawn_at", ""), player.position.x + 200), FLOOR_Y)
	view.set_meta("hostile", hostile)
	level.add_child(view)
	var power := float(actor.get("power", 1.0))
	actor_views[actor["id"]] = view
	actor_power[actor["id"]] = power
	actor_hp[actor["id"]] = Cultivation.enemy_hp(power, pack_tier())
	enemy_cooldown[actor["id"]] = ENEMY_HIT_INTERVAL


## 角色的樣子：有圖畫圖，沒圖畫色塊，頭上掛名字。原點在腳底。
func _make_actor_view(actor: Dictionary, hostile: bool) -> Node2D:
	var view := Node2D.new()
	var size := Vector2(32, 60) * (1.3 if actor["template"].begins_with("boss.") else 1.0)
	# 同模板的不同角色依 memory_key（沒有就用名字）固定分到同一張變體
	var key: String = actor.get("memory_key", actor["name"])
	var tex: Texture2D = art.texture(actor["template"], key, "mob.generic" if hostile else "npc.generic")
	if tex:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.centered = false
		var height := float(art.info(actor["template"]).get("height", 120))
		sprite.scale = Vector2.ONE * height / tex.get_height()
		sprite.position = Vector2(-tex.get_width() * sprite.scale.x / 2, -height)
		sprite.flip_h = hostile  # 立繪面朝右；敵人預設面向玩家來的方向
		size = Vector2(tex.get_width() * sprite.scale.x, height)
		view.add_child(sprite)
	else:
		var body := ColorRect.new()
		body.color = Color("#c0392b") if hostile else Color("#7fb3d5")
		body.size = size
		body.position = Vector2(-size.x / 2, -size.y)
		view.add_child(body)
	var label := Label.new()
	label.text = "%s・%s" % [actor.get("title", ""), actor["name"]] if actor.has("title") else actor["name"]
	label.position = Vector2(-size.x, -size.y - 28)
	view.add_child(label)
	return view


func _remove_actor_view(id: String) -> void:
	if actor_views.has(id):
		actor_views[id].queue_free()
		actor_views.erase(id)


func _on_reward(effect: Dictionary) -> void:
	if effect["type"] == "give_loot":
		var items: Array = loot.get(effect["loot_table"], {}).get(effect["tier"], [])
		for item in items:
			state.add_item(item)
		add_log("獲得：" + "、".join(items))
	elif effect["type"] == "grant_exp":
		gain_cultivation(int(Cultivation.EXP_REWARD.get(effect["amount"], 0)))


func _on_presentation(effect: Dictionary) -> void:
	if effect["type"] == "teleport":
		place_player(effect["point"])


# ---------- 對話 ----------

func _on_line_shown(id: String, line: Dictionary) -> void:
	pack_stats["lines"] = int(pack_stats.get("lines", 0)) + 1
	line_shown_at = Time.get_ticks_msec()
	line_length = line["text"].length()
	_show_line(line)
	if line["live_rewrite"] and use_director:
		director.request_rewrite(id, line["text"], runner.pack, state)


func _on_line_updated(_id: String, line: Dictionary) -> void:
	pack_stats["rewritten"] = int(pack_stats.get("rewritten", 0)) + 1
	_show_line(line)


func _show_line(line: Dictionary) -> void:
	var speaker: String = {"narrator": "", "player": "你"}.get(line["speaker"], line["speaker_name"])
	var text: String = ("%s：%s" % [speaker, line["text"]]) if speaker != "" else line["text"]
	current_choices = line["choices"]
	for i in current_choices.size():
		text += "\n  %d. %s" % [i + 1, current_choices[i]["text"]]
	if current_choices.is_empty():
		text += "\n  （空白鍵繼續）"
	dialogue_label.text = text
	dialogue_panel.visible = true
	player.frozen = true


func _on_dialogue_ended() -> void:
	_hide_dialogue()


func _hide_dialogue() -> void:
	lingering = false
	current_choices = []
	dialogue_panel.visible = false
	player.frozen = false


func advance_dialogue() -> void:
	if lingering:
		_hide_dialogue()
	elif runner != null and runner.current_node != "":
		_note_skip()
		runner.advance()


## i 是畫面上的選項順序（從 0 開始）。
## 翻頁前看這句停留多久，太短算跳過
func _note_skip() -> void:
	var read_ms := line_length / READ_CHARS_PER_SEC * 1000.0
	if Time.get_ticks_msec() - line_shown_at < read_ms * SKIP_FACTOR:
		pack_stats["skipped"] = int(pack_stats.get("skipped", 0)) + 1


func choose_visible(i: int) -> void:
	if runner != null and i < current_choices.size():
		runner.choose(current_choices[i]["index"])


# ---------- 修為 ----------

func cultivation() -> int:
	return int(state.game_data.get("exp", 0))


func hp() -> int:
	return int(state.game_data.get("hp", Cultivation.max_hp(state.tier_index)))


func gain_cultivation(amount: int) -> void:
	var need := Cultivation.need(state.tier_index)
	var was_full := cultivation() >= need
	state.game_data["exp"] = cultivation() + amount
	add_log("修為 +%d（%d／%d）" % [amount, cultivation(), need])
	if cultivation() >= need and not was_full and state.tier_index + 1 < state.ruleset["tiers"].size():
		add_log("修為圓滿，可以嘗試突破（B）。")
	update_movement_skills()
	prepare_heart_demon()


## 打坐一個時辰：增加修為、回滿血。宗門靈氣足，進境較快。
func meditate() -> void:
	if runner != null:
		return
	var gain: int = Cultivation.MEDITATE_EXP_IN_SECT if state.region == "region.qingyun_sect" else Cultivation.MEDITATE_EXP
	var new_day := advance_time(1)
	state.game_data["hp"] = Cultivation.max_hp(state.tier_index)
	add_log("打坐一個時辰。（第 %d 天・%s）" % [state.day, state.time_of_day])
	gain_cultivation(gain)
	if new_day:
		day_started()
		restock()
	check_triggers({"type": "time_changed"})


## 修為圓滿才能突破；突破吃掉門檻的修為，血量回滿。
func try_breakthrough() -> bool:
	var need := Cultivation.need(state.tier_index)
	if runner != null or state.tier_index + 1 >= state.ruleset["tiers"].size():
		return false
	if cultivation() < need:
		add_log("修為未到（%d／%d），強行突破只會走火入魔。" % [cultivation(), need])
		return false
	state.game_data["exp"] = cultivation() - need
	breakthrough()
	return true


# ---------- 戰鬥 ----------

## 內容包的最低境界，敵人強度跟著它走
func pack_tier() -> int:
	if runner == null:
		return 0
	return maxi(0, state.tier_index_of(runner.pack["meta"]["tier_range"]["min"]))


func attack() -> void:
	if attack_cooldown > 0.0:
		return
	attack_cooldown = ATTACK_COOLDOWN
	for id in actor_views.keys():
		var view: Node2D = actor_views[id]
		if view.get_meta("hostile") and absf(view.position.x - player.position.x) <= ATTACK_RANGE and player_near_ground():
			damage_actor(id, Cultivation.player_damage(state.tier_index))


func player_near_ground() -> bool:
	return player.feet() > FLOOR_Y - MELEE_HEIGHT


func damage_actor(id: String, amount: int) -> void:
	if not actor_views.has(id):
		return
	actor_hp[id] -= amount
	add_log("擊中 %s（剩 %d）" % [actor_label(id), maxi(0, actor_hp[id])])
	if actor_hp[id] <= 0:
		_remove_actor_view(id)
		gain_cultivation(Cultivation.kill_exp(float(actor_power.get(id, 1.0))))
		if runner != null:
			runner.notify({"type": "actor_defeated", "actor": id})


func actor_label(id: String) -> String:
	if runner != null:
		for a in runner.pack.get("actors", []):
			if a["id"] == id:
				return a["name"]
	return id


func damage_player(amount: int) -> void:
	state.game_data["hp"] = maxi(0, hp() - amount)
	if hp() == 0:
		player_down()


## 重傷倒地：事件以失敗結算，醒來時血回一半、過了一個時辰。
func player_down() -> void:
	add_log("你重傷倒地，人事不知……")
	playlog.write("player_down", {"pack": runner.pack["id"] if runner != null else "", "region": state.region})
	for id in enemy_cooldown:
		enemy_cooldown[id] = ENEMY_HIT_INTERVAL
	if runner != null:
		runner.abort("fail")
	state.game_data["hp"] = Cultivation.max_hp(state.tier_index) / 2
	if advance_time(1):
		day_started()
	add_log("醒來時已是%s。" % state.time_of_day)
	_refresh_status()


func _process(delta: float) -> void:
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	_update_prompt()
	if runner == null:
		return
	for p in points:
		if not runner.reached_points.has(p) and absf(points[p] - player.position.x) < 32.0:
			runner.notify({"type": "reach_point", "point": p})
			if runner == null:
				return
	if dialogue_panel.visible:
		return
	for id in actor_views.keys():
		var view: Node2D = actor_views[id]
		if not view.get_meta("hostile"):
			continue
		var dx := player.position.x - view.position.x
		if absf(dx) > 40.0:
			view.position.x += signf(dx) * HOSTILE_SPEED * delta
		if absf(dx) <= ENEMY_REACH and player_near_ground():
			enemy_cooldown[id] = float(enemy_cooldown.get(id, ENEMY_HIT_INTERVAL)) - delta
			if enemy_cooldown[id] <= 0.0:
				enemy_cooldown[id] = ENEMY_HIT_INTERVAL
				damage_player(Cultivation.enemy_damage(float(actor_power.get(id, 1.0)), pack_tier()))
				if runner == null:
					return


## 站在傳送點或 NPC 旁邊時，畫面下方提示可以按 ↑。
func _update_prompt() -> void:
	var text := ""
	if not dialogue_panel.visible and not player.climbing:
		var portal := nearby_portal()
		if not portal.is_empty():
			text = "↑ 前往%s" % region_name(portal["to"])
		elif nearby_cache() != "":
			text = "↑ 拿取"
		elif nearby_resident() != "":
			text = "↑ 交談"
	prompt_label.text = text
	prompt_label.visible = text != ""


# ---------- 除錯：製造觸發條件 ----------

func spare_fox() -> void:
	state.set_flag("spared_white_fox", true)
	add_log("你放走了山崖下受傷的白狐。（第 %d 天）" % state.day)


func pass_day() -> void:
	state.day += 1
	add_log("過了一天，現在是第 %d 天。" % state.day)
	day_started()
	restock()
	check_triggers({"type": "time_changed"})


func next_time() -> void:
	var times: Array = state.ruleset["times_of_day"]
	state.time_of_day = times[(times.find(state.time_of_day) + 1) % times.size()]
	add_log("時辰：" + state.time_of_day)
	check_triggers({"type": "time_changed"})


func breakthrough() -> void:
	if state.tier_index + 1 >= state.ruleset["tiers"].size():
		return
	state.tier_index += 1
	state.game_data["hp"] = Cultivation.max_hp(state.tier_index)
	playlog.write("breakthrough", {"tier": state.tier_name(), "day": state.day})
	add_log("突破至" + state.tier_name() + "！")
	update_movement_skills()
	check_triggers({"type": "tier_up", "to": state.tier_name()})
	prepare_heart_demon()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if not travel_options.is_empty():
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_4:
			choose_travel(event.physical_keycode - KEY_1)
		elif event.physical_keycode in [KEY_ESCAPE, KEY_T]:
			close_travel_menu()
		_refresh_status()
		return
	match event.physical_keycode:
		KEY_T:
			open_travel_menu()
		KEY_UP, KEY_W, KEY_E:
			interact()
		KEY_SPACE, KEY_ENTER:
			advance_dialogue()
		KEY_1, KEY_2, KEY_3, KEY_4:
			choose_visible(event.physical_keycode - KEY_1)
		KEY_J:
			if not dialogue_panel.visible:
				attack()
		KEY_M:
			if not dialogue_panel.visible:
				meditate()
		KEY_B:
			if not dialogue_panel.visible:
				try_breakthrough()
		KEY_F1:
			spare_fox()
		KEY_F2:
			pass_day()
		KEY_F3:
			next_time()
		KEY_F4:
			breakthrough()
		KEY_F5:
			autosave()
			add_log("已存檔。")
		KEY_F6:
			request_fresh_event()
		KEY_F9:
			load_game()
	_refresh_status()


# ---------- HUD ----------

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	hud_status = Label.new()
	hud_status.position = Vector2(16, 12)
	hud.add_child(hud_status)
	hud_objective = Label.new()
	hud_objective.position = Vector2(760, 12)
	hud.add_child(hud_objective)
	hud_log = Label.new()
	hud_log.position = Vector2(16, 44)
	hud_log.modulate = Color(1, 1, 1, 0.8)
	hud.add_child(hud_log)
	dialogue_panel = PanelContainer.new()
	dialogue_panel.position = Vector2(140, 520)
	dialogue_panel.custom_minimum_size = Vector2(1000, 170)
	dialogue_panel.visible = false
	dialogue_label = Label.new()
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_panel.add_child(dialogue_label)
	hud.add_child(dialogue_panel)
	var help := Label.new()
	help.text = "←→ 移動　Alt/C/空白 跳　↑↓ 爬繩梯　↓+跳 下平台　↑/E 傳送點・交談　J 攻擊　1-4 選擇　T 地圖　M 打坐　B 突破"
	help.position = Vector2(16, 690)
	help.modulate = Color(1, 1, 1, 0.5)
	hud.add_child(help)
	prompt_label = Label.new()
	prompt_label.visible = false
	prompt_label.size = Vector2(400, 0)
	prompt_label.position = Vector2(440, 650)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(prompt_label)
	_refresh_status()


func _refresh_status() -> void:
	if state == null or hud_status == null:
		return
	var karma := []
	for axis in state.karma:
		karma.append("%s %d" % [axis, state.karma[axis]])
	hud_status.text = "%s　第 %d 天・%s　境界：%s　修為 %d／%d　氣血 %d／%d　%s" % [
		region_name(), state.day, state.time_of_day, state.tier_name(),
		cultivation(), Cultivation.need(state.tier_index), hp(), Cultivation.max_hp(state.tier_index), "　".join(karma)]


func add_log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 8:
		log_lines.pop_front()
	if hud_log:
		hud_log.text = "\n".join(log_lines)
	_refresh_status()
