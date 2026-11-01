## 遊戲主控：橫軸地圖、玩家、角色，並把 ZeWorld 內容包與導演接到畫面上。
## 地圖有單向平台與繩梯（chunks.json 的 platforms／ropes），操作見 scripts/player.gd。
## 地圖兩端有傳送點，站上去按 ↑（交談鍵）走到相鄰地區（regions.json 的 exits）；也可以按 T 開地圖直接去。
## 移動要花時辰。地區裡的常駐 NPC（regions.json 的 residents）靠近按 ↑ 或 E 說話。
## 身法（輕身術、踏葉、御風、土遁、御劍）隨境界與修為領悟；有些平台要身法才上得去，
## 上面的寶物（chunks.json 的 caches）按 ↑ 拿。區塊的 walls：cliff 是可以踏葉的石壁，thin 是土遁穿得過的薄牆。
## 攻擊鍵（X/J）攻擊，敵人近身會傷人，血量歸零就重傷倒地（事件以失敗結算）。M 打坐增加修為、回滿血，
## 修為圓滿後按 B 突破境界。
## 除錯鍵用來快速製造觸發條件：F1 放走白狐、F2 過一天、F3 換時辰、F4 突破境界、
## F6 請導演生成一個新事件、F5 存檔、F9 讀檔。N 開關配樂。
## 配樂與音效見 scripts/audio.gd、content/audio.json。
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
const ParallaxPainting = preload("res://scripts/parallax_painting.gd")
const Scenery = preload("res://scripts/scenery.gd")
const InkUI = preload("res://scripts/ink_ui.gd")
const ActorView = preload("res://scripts/actor_view.gd")
const InkFx = preload("res://scripts/ink_fx.gd")
const GameAudio = preload("res://scripts/audio.gd")
const Keys = preload("res://scripts/keys.gd")
const KeyPanel = preload("res://scripts/key_panel.gd")

const FLOOR_Y := 560.0
## 鏡頭下緣在地面下多少：留一條地面給操作說明，其餘都給畫面
const CAMERA_BOTTOM := 110.0
## 鏡頭可以看到地圖兩端外面多少（蓋墨霧）
const EDGE_MARGIN := 110.0
## 天頂離地多高：再往上就撞到
const CEILING_HEIGHT := 650.0
const START_REGION := "region.qingyun_foothills"
## 地區要求的最低境界（tier index）；黑風嶺築基以上才准去
const REGION_MIN_TIER := {"region.heifeng_ridge": 1}
## 補貨排程：每個地區、目前境界至少備著幾個沒玩過的事件
const RESTOCK_TARGET := 3
const HEART_DEMON_HINT := "突破到%s時的心魔幻境。心魔是玩家的鏡像，拿玩家經歷裡最難面對的事（history 裡的選擇、NPC 的記憶、karma 傾向）來質問玩家，每個玩家的心魔都該不同。地圖只用心魔幻境區塊（地圖標籤 illusion），心魔用模板 boss.heart_demon_mirror。tier_range 從%s到%s，不要設定 meta.region。通過時設旗標 %s_heart_demon_cleared。"
const ENCOUNTER_HINT := "今日奇遇：發生在玩家目前所在地區的小小偶遇，幾分鐘就能玩完，可以呼應玩家最近的經歷。今天就要能觸發：觸發條件只用這個地區區塊有的地圖標籤，可加時辰，不要用天數或其他事件才會立的旗標。獎勵要小。"
const ATTACK_RANGE := 90.0
## 敵人在這個距離內，配樂的鼓聲層進來
const DANGER_RANGE := 700.0
## 事件裡的敵人都離開後，戰鬥曲再多留幾秒才換回去
const COMBAT_MUSIC_HOLD := 4.0
## 敵人走在地面上：玩家腳離地面超過這個高度就打不到、也不會被打到
const MELEE_HEIGHT := 90.0
const PROMPT_HEIGHT := 110.0       # 互動提示在角色腳上方多高
const PORTAL_INSET := 50.0        # 傳送點離地圖邊緣多遠
const INTERACT_RANGE := 40.0
const ATTACK_COOLDOWN := 0.35
const ENEMY_REACH := 44.0
const ENEMY_STRIKE_REACH := 60.0  # 前搖結束時玩家還在這個距離內才算打中（看到紅字往後閃就躲得掉）
const ENEMY_HIT_INTERVAL := 1.0
## 打擊感（docs/design/reference-study.md C1、C2）
const HITSTOP := 0.06             # 命中時整個遊戲停一下（秒，真實時間）
const HITSTOP_KILL := 0.1
const ENEMY_KNOCKBACK := 16.0     # 加上 actor_view.hit 的 14，敵人被打退約 30
const PLAYER_RECOIL := 8.0        # 出劍命中時玩家被反推
const PLAYER_INVULN := 0.8        # 受傷後無敵、閃爍
## 一句話停留不到「預估閱讀時間 × 這個比例」就翻頁，算跳過（中文約每秒 8 字）
const SKIP_FACTOR := 0.3
const READ_CHARS_PER_SEC := 8.0
const HOSTILE_SPEED := 70.0
const SAVE_ID := "save.001"
## 相鄰區塊接縫處地面顏色漸變的寬度（每邊）；背景畫的接縫由 ParallaxPainting 交疊淡入
const SEAM_BLEND := 150
## 背景整體壓暗一點，角色與可互動物件（平台、繩梯）才跳得出來（reference-study.md A1）
const BACKDROP_DIM := Color(0.87, 0.86, 0.84)

## 測試時設成空字串可停用存檔／導演生成資料夾；use_director 設 false 可完全不連導演。
const WEB_CODE_PATH := "user://director_code.txt"
var _awaiting_code := false       # 網頁版還沒輸入存取碼：先不送導演請求，免得被擋
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
## 配樂與音效；測試時 audio_settings_path 設空字串，不寫設定檔
var audio
var audio_settings_path := "user://audio.cfg"
## 自訂按鍵；測試時設空字串，不讀寫檔案（scripts/keys.gd）
var keys_path := "user://keys.json"
var help_label: Label
var key_panel                      # 按鍵設定畫面（scripts/key_panel.gd）
var menu_text := ""                # 有編號選項的對話框原文，menu_cursor 那一行加上「◆」
var menu_cursor := 0
var _combat_hold := 0.0           # 戰鬥曲還要留幾秒
var _heart_demon_event := false   # 目前（或剛結束）的事件是心魔

var state
var pool: Array = []
var chunks: Dictionary = {}
var sky_colors: Dictionary = {}     # 區塊圖透明的天後面要補的天色（content/sky.json）
var loot: Dictionary = {}
var regions: Dictionary = {}
var runner = null

var level: Node2D
var player: CharacterBody2D
var points: Dictionary = {}       # point id -> x
var map_width := 0.0
var chunk_x: Dictionary = {}      # chunk id -> 地圖上的起點 x
var chunk_spans: Array = []       # [{x0, x1, tags}]：氛圍粒子依玩家所在的區塊切換
var _ambience_span := -1
var portals: Array = []           # 落腳地圖兩端的傳送點 {x, to, view}
var residents: Dictionary = {}    # 常駐 NPC id -> {view, info, said}
var caches: Dictionary = {}       # 這張地圖上還沒拿的寶物 id -> {view, info}
var prompt_label: Label           # 「↑ 前往……」「↑ 交談」提示
var actor_views: Dictionary = {}  # actor id -> Node2D
var actor_hp: Dictionary = {}
var actor_power: Dictionary = {}  # actor id -> power，傷害與擊殺修為用
var actor_max_hp: Dictionary = {}
var actor_boss: Dictionary = {}   # Boss 的 actor id -> 是否已發狠
var actor_tier: Dictionary = {}   # 野怪的 actor id -> 強度境界（事件裡的敵人跟著 pack_tier）
var wild: Dictionary = {}         # 落腳地圖上的野怪 id -> regions.json 的 wild 條目
var wild_drop_chance := 0.5       # 野怪掉普通物品的機率（測試設成 1）
var errands: Dictionary = {}      # content/errands.json：宗門差事榜
var board_view: Node2D = null     # 差事榜（只在 errands.board 的地區）
var errand_options: Array = []    # 差事榜開著時的選項 [{kind: accept|abandon, errand}]
var _map_gen := 0                 # 地圖重建或玩家倒地就加一，敵人迴圈看到變了就停
var enemy_cooldown: Dictionary = {}  # actor id -> 收招破綻還剩幾秒（這段時間不動、不出招）
var enemy_windup: Dictionary = {}    # actor id -> 前搖還剩幾秒（只有正在蓄力的敵人）
var player_invuln := 0.0
var camera_zones: Array = []      # 這張地圖的戰場鏡頭 {x0, x1, zoom, lock_y?}（chunks.json 的 camera）
var hitstop_enabled := true
var attack_cooldown := 0.0
var log_lines: Array = []

var hud_status: Label
var hud_detail: Label
var hp_bar: ProgressBar
var exp_bar: ProgressBar
var log_panel: PanelContainer
var log_tween: Tween
var objective_panel: PanelContainer
var dialogue_name: Label
var dialogue_name_box: PanelContainer
var portrait: TextureRect
var portrait_frame: PanelContainer
var tint: CanvasModulate
var vignette: TextureRect
var hud_layer: CanvasLayer
var fx_layer: CanvasLayer        # 暗角、紙紋、突破染色：在世界之上、介面之下
var ambience: CPUParticles2D
var _ground_tone: Dictionary = {} # 區塊 id -> 地面染色
var hud_objective: Label
var hud_log: Label
var dialogue_panel: PanelContainer
var dialogue_label: Label
var current_choices: Array = []
var travel_options: Array = []    # 地圖開著時可去的地區 id
var lingering := false            # 事件結束時最後一句先留在畫面上，按空白才關
var home_after_dialogue := false  # 事件地圖結束時最後一句還沒關：關掉後才回落腳地圖
var fits: Dictionary = {}         # 決策模型給的貼合度 {內容包 id: 0–4}，觸發時和 priority 一起排序
var _ranked_key := ""             # 上次送評分的候選組合，沒變就不重送


func _ready() -> void:
	InkUI.install()
	tint = CanvasModulate.new()
	add_child(tint)
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
	Keys.setup(keys_path)
	_build_hud()
	audio = GameAudio.new()
	audio.settings_path = audio_settings_path
	add_child(audio)
	player = Player.new()
	add_child(player)
	player.set_look(art.texture("player.disciple"), float(art.info("player.disciple").get("height", 88)))
	player.sound.connect(func(n): audio.play(n))
	if save_path != "" and state.load_file(save_path):
		add_log("讀取存檔：第 %d 天。" % state.day)
	if not regions.has(state.region):
		state.region = START_REGION
	if not state.game_data.has("hp"):
		state.game_data["hp"] = Cultivation.max_hp(state.tier_index)
	update_movement_skills()
	go_home()
	add_log(("%s。" + Keys.hint("map") + " 地圖、" + Keys.hint("settings") + " 按鍵設定、F1 放走白狐、F2 過一天、F3 換時辰、F4 突破境界、F6 新事件。") % region_name())
	playlog.write("session_start", {"version": ProjectSettings.get_setting("application/config/version", ""),
		"director": use_director, "day": state.day, "region": state.region, "tier": state.tier_name()})
	if not _awaiting_code:
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
## 網頁版：導演網址用專案設定 zetas/web_director_url（網址加 ?director= 可改），
## 存取碼從網址 ?code= 帶入或第一次開啟時輸入，存在 user://director_code.txt（瀏覽器 IndexedDB）。
func _read_director_config() -> void:
	if OS.has_feature("editor"):
		return
	if OS.has_feature("web"):
		_read_web_director_config()
		return
	var dir := OS.get_executable_path().get_base_dir()
	var url := _read_text(dir.path_join("director_url.txt"))
	if OS.get_environment("ZEWORLD_DIRECTOR_URL") == "" and url.begins_with("http"):
		director.base_url = url
	var code := _read_text(dir.path_join("director_code.txt"))
	if OS.get_environment("ZEWORLD_DIRECTOR_CODE") == "" and code != "":
		director.access_code = code


func _read_web_director_config() -> void:
	var url := _web_param("director")
	if url == "":
		url = str(ProjectSettings.get_setting("zetas/web_director_url", ""))
	if url.begins_with("http"):
		director.base_url = url
	var code := _web_param("code")
	if code != "":
		_write_text(WEB_CODE_PATH, code)
		JavaScriptBridge.eval("history.replaceState(null, '', location.pathname)")
	else:
		code = _read_text(WEB_CODE_PATH)
	if code != "":
		director.access_code = code
	else:
		_awaiting_code = true
		_ask_access_code.call_deferred()


static func _web_param(name: String) -> String:
	var v = JavaScriptBridge.eval("new URLSearchParams(location.search).get('%s') || ''" % name)
	return str(v).strip_edges() if v != null else ""


static func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)


## 網頁版第一次開啟：請玩家輸入存取碼。留空就只玩手寫事件，下次開啟會再問。
func _ask_access_code() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(340, 260)
	panel.custom_minimum_size = Vector2(600, 0)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var label := Label.new()
	label.text = "輸入存取碼就能連上 AI 導演，生成只屬於你的事件。\n沒有存取碼也能玩，直接按 Enter。"
	box.add_child(label)
	var field := LineEdit.new()
	field.placeholder_text = "存取碼"
	box.add_child(field)
	get_tree().paused = true
	field.text_submitted.connect(func(text: String):
		var code := text.strip_edges()
		if code != "":
			_write_text(WEB_CODE_PATH, code)
			director.access_code = code
			add_log("已連上 AI 導演。")
		else:
			use_director = false  # 沒有存取碼：只玩手寫事件，不送注定 401 的請求
		get_tree().paused = false
		_awaiting_code = false
		layer.queue_free()
		if code != "":
			request_followups()
			restock()
			prepare_heart_demon())
	field.grab_focus.call_deferred()


static func _read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path).strip_edges() if FileAccess.file_exists(path) else ""


func load_content() -> void:
	state = WorldState.new(PackPool.load_ruleset("res://content/ruleset.json"))
	state.save_id = SAVE_ID
	pool = PackPool.load_dir("res://content/packs")
	if generated_dir != "":
		pool += PackPool.for_save(PackPool.load_dir(generated_dir), SAVE_ID)
	chunks = _read_json("res://content/chunks.json")
	sky_colors = _read_json("res://content/sky.json")
	loot = _read_json("res://content/loot.json")
	art = AssetLibrary.from_file(assets_path)
	regions = _read_json("res://content/regions.json")
	regions.erase("_comment")
	errands = _read_json("res://content/errands.json")


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
	wild.clear()
	_map_gen += 1
	level = Node2D.new()
	add_child(level)
	move_child(level, 0)
	points.clear()
	chunk_x.clear()
	chunk_spans = []
	_ambience_span = -1
	camera_zones = []
	portals = []
	residents.clear()
	caches.clear()
	var tags: Array = []
	var ropes: Array = []
	var backgrounds: Array = []
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
			# 背景畫走得比地面慢（視差），接縫和前一張交疊淡入
			bg = ParallaxPainting.new()
			bg.setup(tex, x, width, FLOOR_Y, entry == ordered[0], entry == ordered[-1], sky_color(entry["chunk"]), info.get("tags", []))
		else:
			bg = ColorRect.new()
			bg.color = Color(info["color"])
			bg.position = Vector2(x, FLOOR_Y - 600)
			bg.size = Vector2(width, 600)
		bg.z_index = -10
		bg.modulate = BACKDROP_DIM
		level.add_child(bg)
		backgrounds.append({"id": entry["chunk"], "x": x, "width": width, "tex": tex, "tags": info.get("tags", [])})
		chunk_x[entry["chunk"]] = x
		chunk_spans.append({"x0": x, "x1": x + width, "tags": info.get("tags", [])})
		if info.has("camera"):
			var cz: Dictionary = info["camera"]
			var zone := {"x0": x + float(cz.get("x0", 0)), "x1": x + float(cz.get("x1", width)), "zoom": float(cz.get("zoom", 0.9))}
			if cz.has("lock_y"):
				zone["lock_y"] = FLOOR_Y - float(cz["lock_y"])
			camera_zones.append(zone)
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
	ground.add_child(_ground_strip(backgrounds, x))
	for wall_x in [-10.0, x + 10.0]:
		var wall := CollisionShape2D.new()
		wall.shape = RectangleShape2D.new()
		wall.shape.size = Vector2(20, 1200)
		wall.position = Vector2(wall_x, FLOOR_Y - 600)
		ground.add_child(wall)
	# 天頂：御劍、二段跳不會飛出畫面
	var ceiling := CollisionShape2D.new()
	ceiling.shape = RectangleShape2D.new()
	ceiling.shape.size = Vector2(x + 400, 20)
	ceiling.position = Vector2(x / 2, FLOOR_Y - CEILING_HEIGHT - 10)
	ground.add_child(ceiling)
	# 地圖兩端外面留一點畫面，蓋一層墨霧，站在盡頭的人和寶物不會被切在畫面邊緣
	for side in [-1, 1]:
		level.add_child(_edge_mist(0.0 if side < 0 else x, side))
	level.add_child(ground)
	map_width = x
	# 落腳地圖會串起不同區塊（林間、石洞、獸穴）：景深層照第一個區塊的樣子，氛圍粒子跟著玩家所在的區塊換
	var look_tags: Array = chunk_spans[0]["tags"] if not chunk_spans.is_empty() else tags
	_set_ambience(look_tags)
	Scenery.add_sky(level, FLOOR_Y, backgrounds.map(func(b): return {"x": b["x"], "width": b["width"], "color": sky_color(b["id"]), "tags": b["tags"]}))
	Scenery.add_layers(level, FLOOR_Y, look_tags, hash(ordered.map(func(e): return e["chunk"])))
	state.map_tags = tags
	player.ropes = ropes
	player.floor_y = FLOOR_Y
	player.set_camera_limits(-EDGE_MARGIN, x + EDGE_MARGIN, FLOOR_Y - 640.0, FLOOR_Y + CAMERA_BOTTOM)
	place_player(spawn_point)
	if audio != null:
		audio.play_music(music_choice(), state.region)


## 地面：一條貼著 prop.ground 的長條，每個區塊依它畫面底部的顏色染色，
## 接縫處顏色漸變（Polygon2D 的頂點色），地面就像古畫坡腳延伸下來，不再是一塊黑泥板。
## 區塊的天色；沒有記錄（洞窟、幻境、程式畫的區塊）用通用的紙色
func sky_color(chunk_id: String) -> Color:
	var c = sky_colors.get(chunk_id)
	# 天和古畫一樣壓暗（BACKDROP_DIM），兩者才接得起來
	if c is String:
		return Color(c) * BACKDROP_DIM
	var tags: Array = chunks.get(chunk_id, {}).get("tags", [])
	if tags.has("illusion"):
		return Color("#2a0a0c")
	if tags.has("cave") or tags.has("den"):
		return Color("#1c1b19")
	return Color(0.86, 0.83, 0.76) * BACKDROP_DIM


func _ground_strip(backgrounds: Array, total: float) -> CanvasItem:
	var tex: Texture2D = art.texture("prop.ground")
	if tex == null:
		var block := ColorRect.new()
		block.color = Color("#1c1a17")
		block.position = Vector2(-200, FLOOR_Y - 3)
		block.size = Vector2(total + 400, 163)
		return block
	var poly := Polygon2D.new()
	poly.texture = tex
	poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var top := FLOOR_Y - 3
	var bottom := top + 163
	var xs := [-200.0]
	var colors := [_chunk_ground_tone(backgrounds[0]) if not backgrounds.is_empty() else Color.WHITE]
	for i in backgrounds.size():
		var b: Dictionary = backgrounds[i]
		var c := _chunk_ground_tone(b)
		if i > 0:
			xs.append(b["x"] + SEAM_BLEND)
			colors.append(c)
		if i < backgrounds.size() - 1:
			xs.append(b["x"] + b["width"] - SEAM_BLEND)
			colors.append(c)
	xs.append(total + 200.0)
	colors.append(colors[-1])
	var points := PackedVector2Array()
	var vcolors := PackedColorArray()
	var uvs := PackedVector2Array()
	for i in xs.size():
		points.append(Vector2(xs[i], top))
		vcolors.append(colors[i])
	for i in range(xs.size() - 1, -1, -1):
		points.append(Vector2(xs[i], bottom))
		vcolors.append(colors[i].darkened(0.25))
	for p in points:
		uvs.append(Vector2(p.x, (p.y - top) * 160.0 / 163.0))
	poly.polygon = points
	poly.uv = uvs
	poly.vertex_colors = vcolors
	return poly


## 區塊的地面色：取畫面底部（地平線上方一帶）的平均色，壓暗一點。沒有圖就用區塊色。
func _chunk_ground_tone(b: Dictionary) -> Color:
	if _ground_tone.has(b["id"]):
		return _ground_tone[b["id"]]
	var c := Color(0.55, 0.52, 0.47)
	var tex: Texture2D = b["tex"]
	if tex != null:
		var img := tex.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			var sum := Color(0, 0, 0)
			var n := 0
			for y in range(img.get_height() - 120, img.get_height() - 30, 6):
				for xi in range(0, img.get_width(), 16):
					sum += img.get_pixel(xi, y)
					n += 1
			if n > 0:
				c = Color(sum.r / n, sum.g / n, sum.b / n) * 0.82
				c.a = 1.0
	_ground_tone[b["id"]] = c
	return c


## 氛圍粒子：依地圖標籤飄落葉、花瓣、洞裡的浮塵、心魔幻境的餘燼。粒子掛在鏡頭上、用世界座標，
## 所以走動時會自然被拋在後面。
## 玩家走進另一個區塊時換氛圍粒子（洞裡是浮塵、山上是落葉）
func _update_ambience() -> void:
	for i in chunk_spans.size():
		var span: Dictionary = chunk_spans[i]
		if player.position.x >= span["x0"] and player.position.x < span["x1"]:
			if i != _ambience_span:
				_ambience_span = i
				_set_ambience(span["tags"])
			return


func _set_ambience(tags: Array) -> void:
	if ambience == null:
		ambience = CPUParticles2D.new()
		ambience.local_coords = false
		ambience.texture = InkUI.soft_dot(12)
		ambience.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		ambience.emission_rect_extents = Vector2(760, 420)
		ambience.amount = 40
		ambience.lifetime = 9.0
		ambience.preprocess = 9.0
		ambience.z_index = 4
		player.camera.add_child(ambience)
	var look := {"color": Color("#cdb87a", 0.55), "gravity": Vector2(-6, 14), "size": [0.35, 0.8], "amount": 34, "spin": 0.0}
	if "illusion" in tags:
		look = {"color": Color("#ff5a3c", 0.75), "gravity": Vector2(4, -22), "size": [0.25, 0.6], "amount": 46, "spin": 0.0}
	elif "cave" in tags:
		look = {"color": Color("#e8dcc0", 0.35), "gravity": Vector2(2, -2), "size": [0.2, 0.45], "amount": 30, "spin": 0.0}
	elif "mountain" in tags:
		look = {"color": Color("#3b2f24", 0.6), "gravity": Vector2(-14, 18), "size": [0.4, 0.9], "amount": 30, "spin": 2.0}
	elif "sect" in tags:
		look = {"color": Color("#f1c9c4", 0.7), "gravity": Vector2(-10, 12), "size": [0.35, 0.7], "amount": 26, "spin": 2.0}
	ambience.color = look["color"]
	ambience.gravity = look["gravity"]
	ambience.scale_amount_min = look["size"][0]
	ambience.scale_amount_max = look["size"][1]
	ambience.amount = look["amount"]
	ambience.angular_velocity_min = -look["spin"] * 40.0
	ambience.angular_velocity_max = look["spin"] * 40.0
	ambience.initial_velocity_min = 4.0
	ambience.initial_velocity_max = 16.0
	ambience.direction = Vector2(-1, 0.3)
	ambience.spread = 60.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	ambience.color_ramp = fade
	ambience.restart()


# ---------- 事件包裝（reference-study.md A6）與境界、正邪的顏色（A3） ----------

## 事件的印文：心魔、奇遇（每日奇遇）、機緣（導演生成的後續）、事件（手寫）。
func event_seal(pack: Dictionary) -> String:
	var meta: Dictionary = pack.get("meta", {})
	if meta.get("request_tag", "") == "heart_demon" or _pack_has_tag(pack, "illusion"):
		return "心魔"
	if meta.get("request_tag", "") == "encounter":
		return "奇遇"
	if meta.get("author", "") == "director" or meta.get("request_tag", "") != "":
		return "機緣"
	return "事件"


## 卷軸標題卡：開始時卷軸展開、朱印蓋下，停一下再收卷；結束時一張小的、印文是了／敗／罷。
func _scroll_card(title: String, seal_text: String, opening: bool) -> void:
	if hud_layer == null or not is_inside_tree():
		return
	var old := hud_layer.get_node_or_null("ScrollCard")
	if old:
		old.free()
	var card := Control.new()
	card.name = "ScrollCard"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	card.position.y = 150.0 if opening else 120.0
	hud_layer.add_child(card)
	var full := 560.0 if opening else 380.0
	var h := 96.0 if opening else 64.0
	var paper := Panel.new()
	var box := InkUI.paper_box()
	box.shadow_size = 6
	paper.add_theme_stylebox_override("panel", box)
	paper.clip_contents = true
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.size = Vector2(0, h)
	card.add_child(paper)
	var label := Label.new()
	label.text = title
	label.theme_type_variation = "PaperLabel"
	label.add_theme_font_size_override("font_size", 30 if opening else 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(full, h)
	paper.add_child(label)
	var rollers: Array = []
	for i in 2:
		var r := Panel.new()
		r.add_theme_stylebox_override("panel", InkUI.roller())
		r.size = Vector2(16, h + 20)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(r)
		rollers.append(r)
	var seal := PanelContainer.new()
	seal.add_theme_stylebox_override("panel", InkUI.seal_box())
	var seal_label := Label.new()
	seal_label.text = "\n".join(seal_text.split("")) if seal_text.length() > 1 else seal_text
	seal_label.theme_type_variation = "NameLabel"
	seal_label.add_theme_font_size_override("font_size", 20 if opening else 18)
	seal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal.add_child(seal_label)
	seal.modulate.a = 0.0
	card.add_child(seal)
	var set_width := func(w: float) -> void:
		paper.size.x = w
		paper.position.x = -w / 2
		label.position.x = (w - full) / 2
		rollers[0].position = Vector2(-w / 2 - 12, -10)
		rollers[1].position = Vector2(w / 2 - 4, -10)
	set_width.call(0.0)
	var tw := card.create_tween()
	tw.tween_method(set_width, 0.0, full, 0.45 if opening else 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# 朱印：從大到小蓋下，印在卷末右下
	tw.tween_callback(func():
		seal.reset_size()
		seal.pivot_offset = seal.size / 2
		seal.position = Vector2(full / 2 - seal.size.x - 26, h - seal.size.y * 0.75)
		seal.scale = Vector2.ONE * 2.2
		seal.rotation = -0.08)
	tw.tween_property(seal, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(seal, "scale", Vector2.ONE, 0.16).set_ease(Tween.EASE_IN)
	tw.tween_interval(1.8 if opening else 1.0)
	tw.tween_property(seal, "modulate:a", 0.0, 0.15)
	tw.tween_method(set_width, full, 0.0, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(card.queue_free)


## 事件 NPC 頭上的小朱印，一眼看出「這是這次事件的人」
func _add_event_mark(view: Node2D, ch: String) -> void:
	var mark := PanelContainer.new()
	var box := InkUI.seal_box()
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 1
	box.content_margin_bottom = 2
	mark.add_theme_stylebox_override("panel", box)
	var l := Label.new()
	l.text = ch
	l.theme_type_variation = "NameLabel"
	l.add_theme_font_size_override("font_size", 13)
	mark.add_child(l)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := 0.0
	for n in view.get_children():
		if n is Label:
			top = n.position.y
	mark.position = Vector2(-11, top - 26)
	mark.add_to_group("event_mark")
	view.add_child(mark)


## 正邪的傾向，-1（偏邪）到 1（偏正）；60 以上就算到頂
func _karma_lean() -> float:
	if state == null:
		return 0.0
	return clampf(float(state.karma.get("正邪", 0)) / 60.0, -1.0, 1.0)


## 突破：以玩家為中心，一圈顏色由紙色漸染開來再退去（2 秒）。偏正青、偏邪朱、居中金。
func _breakthrough_wash() -> void:
	if fx_layer == null or not is_inside_tree() or player == null:
		return
	var lean := _karma_lean()
	var color := InkUI.JADE if lean > 0.15 else (InkUI.CINNABAR if lean < -0.15 else InkUI.GOLD)
	var wash := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(color, 0.55))
	g.set_color(1, Color(color, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	wash.texture = tex
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.size = Vector2(400, 400)
	wash.pivot_offset = wash.size / 2
	var screen := player.get_global_transform_with_canvas().origin
	wash.position = screen - wash.size / 2 + Vector2(0, -40)
	wash.scale = Vector2.ONE * 0.2
	wash.name = "BreakthroughWash"
	fx_layer.add_child(wash)
	var tw := wash.create_tween()
	tw.tween_property(wash, "scale", Vector2.ONE * 6.0, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(wash, "modulate:a", 1.0, 0.3).from(0.0)
	tw.tween_property(wash, "modulate:a", 0.0, 0.8)
	tw.tween_callback(wash.queue_free)


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
	body.add_child(_ink_ledge(left, top, width, skill, hash(Vector2(left, top))))
	level.add_child(body)


static var _wash_tex: Texture2D


## 平台底下那抹淡墨：上緣最濃，往下二次方淡出；左右兩端各留一段漸收，四邊都不會有硬邊
static func _ledge_wash() -> Texture2D:
	if _wash_tex == null:
		var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			var v := pow(1.0 - y / 31.0, 1.4)
			for x in 64:
				var u := x / 63.0
				var side := smoothstep(0.0, 0.18, u) * smoothstep(1.0, 0.82, u)
				img.set_pixel(x, y, Color(0.106, 0.094, 0.078, v * side))
		_wash_tex = ImageTexture.create_from_image(img)
	return _wash_tex


## 平台的樣子：一筆乾濕不均的墨線（站的地方），底下一抹往下淡出的淡墨，像畫裡的石台。
## 筆觸兩端收尖、中段粗細起伏；要身法的平台在墨線上再加一道淡青。
func _ink_ledge(left: float, top: float, width: float, skill: String, seed_value: int) -> Node2D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var node := Node2D.new()
	node.name = "InkLedge"
	node.position = Vector2(left, top)
	var n := maxi(6, int(width / 14.0))
	# 淡墨：以墨線中央為心，往下、往兩端淡出的半橢圓
	var ink := Color("#1b1814")
	var wash := TextureRect.new()
	wash.texture = _ledge_wash()
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.position = Vector2(-6, 0)
	wash.size = Vector2(width + 12, 30 + rng.randf_range(0, 14))
	wash.modulate = Color(1, 1, 1, 0.8)
	node.add_child(wash)
	# 墨線
	var stroke := Polygon2D.new()
	var top_pts := PackedVector2Array()
	var bottom_pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		var taper := clampf(minf(t, 1.0 - t) * width / 28.0, 0.2, 1.0)
		var thick := (8.0 + rng.randf_range(-1.5, 2.5)) * taper
		var x := t * width
		top_pts.append(Vector2(x, rng.randf_range(-0.6, 0.6) - thick * 0.35))
		bottom_pts.append(Vector2(x, thick * 0.65 + rng.randf_range(0, 1.2)))
	bottom_pts.reverse()
	stroke.polygon = top_pts + bottom_pts
	stroke.color = ink
	node.add_child(stroke)
	if skill != "":
		var jade := Line2D.new()
		jade.points = PackedVector2Array([Vector2(6, -3), Vector2(width - 6, -3)])
		jade.width = 2.0
		jade.default_color = Color("#9fc4c9", 0.9)
		node.add_child(jade)
	return node


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
	body.add_child(_tiled("prop.thin_wall" if kind == "thin" else "prop.cliff", Vector2(left, FLOOR_Y - top),
		Vector2(width, top - bottom), Color("#7a5a3a") if kind == "thin" else Color("#24221e")))
	level.add_child(body)


## 寶物：一個小匣子，靠近按 ↑ 拿，每份存檔只拿一次。
func _add_cache(c: Dictionary, chunk_left: float) -> void:
	var view := Node2D.new()
	view.position = Vector2(chunk_left + float(c["x"]), FLOOR_Y - float(c.get("h", 0)))
	var tex: Texture2D = art.texture("prop.cache")
	if tex:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.centered = false
		sprite.position = Vector2(-tex.get_width() / 2.0, -tex.get_height())
		view.add_child(sprite)
	else:
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
	audio.play("reward")
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
	var tex: Texture2D = art.texture("prop." + rope["kind"])
	if tex:
		view.add_child(_tiled("prop." + rope["kind"], Vector2(rope["x"] - tex.get_width() / 2.0, rope["top"]),
			Vector2(tex.get_width(), length), Color.WHITE))
	elif rope["kind"] == "ladder":
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


## 平台、地面、繩梯、牆的貼圖：有圖就重複鋪滿，沒圖退回色塊。
func _tiled(id: String, pos: Vector2, size: Vector2, fallback: Color) -> Control:
	var tex: Texture2D = art.texture(id)
	var view: Control
	if tex:
		view = TextureRect.new()
		view.texture = tex
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_TILE
	else:
		view = ColorRect.new()
		view.color = fallback
	view.position = pos
	view.size = size
	return view


## 回到目前地區的落腳地圖。
func go_home() -> void:
	var info: Dictionary = regions.get(state.region, {})
	var list := []
	for i in info.get("home", []).size():
		list.append({"chunk": info["home"][i], "order": i})
	build_map(list, info.get("spawn", ""))
	_build_portals()
	_spawn_residents()
	refresh_wild()
	_build_board()


## 事件會不會把玩家綁在原地：打怪目標的事件（沒有自己的地圖、階段要打倒 N 隻）不會，
## 進行中照樣能趕路、打坐、打野怪；其他事件進行中野怪退場、傳送點不開。
func blocking() -> bool:
	return runner != null and not is_field_pack(runner.pack)


static func is_field_pack(pack: Dictionary) -> bool:
	if pack.has("map"):
		return false
	for st in pack.get("stages", []):
		for c in st.get("complete_when", []):
			if c.get("type", "") == "killed":
				return true
	return false


## 目標列：打怪目標後面加進度（只算事件開始後打倒的）
func refresh_objective() -> void:
	if runner == null or not runner.running:
		return
	var text: String = runner.objective()
	var st: Dictionary = runner.pack["stages"][runner.stage_index]
	for c in st.get("complete_when", []):
		if c.get("type", "") == "killed":
			var tag: String = c["monster_tag"]
			var n := int(state.kills.get(tag, 0)) - int(runner.kills_at_start.get(tag, 0))
			text += "（%d／%d）" % [mini(n, int(c["count"])), int(c["count"])]
	hud_objective.text = "目標：" + text
	objective_panel.visible = true


# ---------- 宗門差事榜 ----------

func _build_board() -> void:
	board_view = null
	var b: Dictionary = errands.get("board", {})
	if b.get("region", "") != state.region or not chunk_x.has(b.get("chunk", "")):
		return
	board_view = Node2D.new()
	board_view.position = Vector2(chunk_x[b["chunk"]] + float(b["x"]), FLOOR_Y)
	for leg in [-46, 40]:
		var post := ColorRect.new()
		post.color = Color("#4a3426")
		post.position = Vector2(leg, -112)
		post.size = Vector2(6, 112)
		board_view.add_child(post)
	var plank := ColorRect.new()
	plank.color = Color("#6b4a32")
	plank.position = Vector2(-56, -108)
	plank.size = Vector2(112, 62)
	board_view.add_child(plank)
	for i in 3:
		var slip := ColorRect.new()
		slip.color = Color("#efe6cf")
		slip.position = Vector2(-48 + i * 34, -102 + (i % 2) * 4)
		slip.size = Vector2(26, 46)
		board_view.add_child(slip)
	var label := Label.new()
	label.text = "差事榜"
	label.size = Vector2(120, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-60, -138)
	label.add_theme_font_size_override("font_size", 16)
	board_view.add_child(label)
	level.add_child(board_view)


func nearby_board() -> bool:
	return board_view != null and is_instance_valid(board_view) \
		and absf(board_view.position.x - player.position.x) < INTERACT_RANGE * 1.5 and player.feet() > FLOOR_Y - MELEE_HEIGHT


func errand_pack_id(e: Dictionary) -> String:
	return "errand.%s.day%d" % [e["id"], state.day]


## 今天榜上的差事：境界夠的差事依天數輪著挑，最多 per_day 件。接過的（不論成敗）今天不再出現。
func todays_errands() -> Array:
	var ok: Array = errands.get("errands", []).filter(func(e): return state.tier_index >= int(e.get("tier_min", 0)))
	var out := []
	var n := mini(int(errands.get("per_day", 3)), ok.size())
	for i in n:
		var e: Dictionary = ok[(state.day * n + i) % ok.size()]
		if not e in out:
			out.append(e)
	return out.filter(func(e): return not state.seen_packs.has(errand_pack_id(e)))


func open_errand_board() -> void:
	if dialogue_panel.visible:
		return
	errand_options = []
	var text := ""
	if runner != null and runner.pack["meta"].get("request_tag", "") == "errand":
		text = "手上的差事：%s\n%s" % [runner.pack["meta"]["title"], hud_objective.text]
		errand_options.append({"kind": "abandon"})
		text += "\n  1. 放棄這件差事（今天不能再接）"
	elif runner != null:
		text = "手上還有事沒了結，先辦完再來接差事。"
	else:
		var list := todays_errands()
		if list.is_empty():
			text = "今天的差事都接過了，明天再來看看。"
		else:
			text = "差事榜（第 %d 天）：" % state.day
			for e in list:
				errand_options.append({"kind": "accept", "errand": e})
				text += "\n  %d. 【%s】%s：打倒 %d 隻%s（%s）" % [errand_options.size(), e["giver"], e["title"],
					int(e["count"]), _template_name(e["template"]), e.get("where", "")]
	text += "\n  （%s 選、%s 確定、Esc 關閉）" % [Keys.first("move_up") + Keys.first("move_down"), Keys.hint("jump")] if not errand_options.is_empty() else "\n  （Esc 關閉）"
	_set_speaker("差事榜", null)
	_set_menu_text(text)
	dialogue_panel.visible = true
	player.frozen = true
	if errand_options.is_empty():
		errand_options.append({"kind": "none"})


func close_errand_board() -> void:
	errand_options = []
	_hide_dialogue()


func choose_errand(i: int) -> void:
	if i >= errand_options.size():
		return
	var opt: Dictionary = errand_options[i]
	close_errand_board()
	if opt["kind"] == "accept":
		var e: Dictionary = opt["errand"]
		add_log("%s：%s" % [e["giver"], e["text"]])
		start_pack(errand_pack(e))
	elif opt["kind"] == "abandon" and runner != null:
		runner.abort("abandon")


func _template_name(template: String) -> String:
	for r in regions.values():
		for w in r.get("wild", []):
			if w["template"] == template:
				return w["name"]
	return template


## 差事做成一個小事件：一個「打倒 N 隻」的階段，完成給修為與普通掉落
func errand_pack(e: Dictionary) -> Dictionary:
	var tiers: Array = state.ruleset["tiers"]
	var reward: Dictionary = e.get("reward", {})
	var done := [{"type": "grant_exp", "amount": reward.get("exp", "small")}]
	if reward.has("loot"):
		done.append({"type": "give_loot", "loot_table": reward["loot"], "tier": "common"})
	return {
		"id": errand_pack_id(e),
		"meta": {"title": "差事・" + e["title"], "summary": e["text"], "author": "errand_board", "request_tag": "errand",
			"tier_range": {"min": tiers[int(e.get("tier_min", 0))], "max": tiers[tiers.size() - 1]}},
		"actors": [],
		"stages": [{"id": "hunt", "objective": "打倒%d隻%s" % [int(e["count"]), _template_name(e["template"])],
			"complete_when": [{"type": "killed", "monster_tag": e["template"], "count": int(e["count"])}]}],
		"outcomes": {"on_complete": done, "on_fail": [], "on_abandon": []},
	}


# ---------- 野怪 ----------

## 這個地區的野怪強度：跟著地區的境界門檻走（煉氣去黑風嶺會很難打）
func wild_tier() -> int:
	return int(REGION_MIN_TIER.get(state.region, 0))


## 今天打倒過的野怪 id。換了一天就清空，野怪隔天重生。
func wild_defeated() -> Array:
	var rec: Dictionary = state.game_data.get("wild_defeated", {})
	if int(rec.get("day", -1)) != state.day:
		return []
	return rec.get("ids", [])


## 現在這個時辰該在地圖上的野怪：id -> 條目（加上 x）
func wild_roster() -> Dictionary:
	var out := {}
	var gone := wild_defeated()
	var list: Array = regions.get(state.region, {}).get("wild", [])
	for e in list.size():
		var entry: Dictionary = list[e]
		if not chunk_x.has(entry["chunk"]):
			continue
		if entry.has("times") and not state.time_of_day in entry["times"]:
			continue
		var width := float(chunks.get(entry["chunk"], {}).get("width", 900))
		var n := int(entry.get("count", 1))
		for i in n:
			var id := "wild.%s.%d.%d" % [entry["chunk"].trim_prefix("chunk."), e, i]
			if id in gone:
				continue
			var x: float = chunk_x[entry["chunk"]] + width * (i + 1) / (n + 1) + 50.0 * (e % 3)
			out[id] = entry.merged({"x": x})
	return out


## 讓地圖上的野怪符合現在的時辰：該出現的補上、時辰過了的退場。事件進行中不出怪。
func refresh_wild() -> void:
	var roster := wild_roster() if not blocking() else {}
	for id in wild.keys():
		if not roster.has(id):
			_remove_actor_view(id)
			wild.erase(id)
	for id in roster:
		if wild.has(id):
			continue
		var entry: Dictionary = roster[id]
		var actor := {"id": id, "template": entry["template"], "name": entry["name"], "disposition": "hostile"}
		var view := _make_actor_view(actor, true)
		view.position = Vector2(entry["x"], FLOOR_Y)
		view.set_meta("hostile", true)
		level.add_child(view)
		wild[id] = entry
		actor_views[id] = view
		actor_power[id] = float(entry.get("power", 1.0))
		actor_tier[id] = wild_tier()
		actor_hp[id] = Cultivation.enemy_hp(actor_power[id], actor_tier[id])
		actor_max_hp[id] = actor_hp[id]
		actor_boss.erase(id)
		enemy_cooldown[id] = 0.0


func clear_wild() -> void:
	for id in wild.keys():
		_remove_actor_view(id)
	wild.clear()


## 打倒野怪：記下來（今天不再出現）、給修為（強度越高給越多）、可能掉普通物品
func _wild_defeated(id: String) -> void:
	var entry: Dictionary = wild[id]
	wild.erase(id)
	var ids := wild_defeated().duplicate()
	ids.append(id)
	state.game_data["wild_defeated"] = {"day": state.day, "ids": ids}
	gain_cultivation(Cultivation.kill_exp(float(entry.get("power", 1.0))) * (1 + int(actor_tier.get(id, 0))))
	var table: String = entry.get("loot", "")
	if table != "" and randf() < wild_drop_chance:
		var items: Array = loot.get(table, {}).get("common", [])
		if not items.is_empty():
			var item: String = items[randi() % items.size()]
			state.add_item(item)
			add_log("拾得：" + item)
			audio.play("reward")
	# 擊殺數記在引擎（state.kills）：觸發條件、導演和打怪目標都看它
	if runner != null:
		runner.notify({"type": "monster_killed", "monster_tag": entry["template"]})
		refresh_objective()
	else:
		state.record_kill(entry["template"])
	playlog.write("wild_kill", {"template": entry["template"], "region": state.region, "day": state.day})
	autosave()


## 落腳地圖兩端的傳送點，通往 exits 裡相鄰的地區。
func _build_portals() -> void:
	var exits: Dictionary = regions.get(state.region, {}).get("exits", {})
	for side in exits:
		var to: String = exits[side]
		var px := PORTAL_INSET if side == "left" else map_width - PORTAL_INSET
		var view := Node2D.new()
		view.position = Vector2(px, FLOOR_Y)
		var glow := TextureRect.new()
		glow.texture = InkUI.portal_glow(Color("#bfe0dc"))
		glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glow.position = Vector2(-45, -140)
		glow.size = Vector2(90, 140)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.add_child(glow)
		var motes := CPUParticles2D.new()
		motes.texture = InkUI.soft_dot(8)
		motes.amount = 10
		motes.lifetime = 1.8
		motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		motes.emission_rect_extents = Vector2(16, 4)
		motes.gravity = Vector2(0, -40)
		motes.initial_velocity_min = 0.0
		motes.initial_velocity_max = 6.0
		motes.color = Color("#e6fbf6", 0.8)
		motes.scale_amount_min = 0.4
		motes.scale_amount_max = 0.9
		view.add_child(motes)
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
	if blocking():
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
		if blocking():
			add_log("事情還沒了結，走不開。")
			return true
		travel_to(portal["to"], true)
		return true
	var cache := nearby_cache()
	if cache != "":
		open_cache(cache)
		return true
	if nearby_board():
		open_errand_board()
		return true
	var id := nearby_resident()
	if id != "":
		talk_to(id)
		return true
	return false


## 常駐 NPC 一次說一句，輪著說。跳鍵（或 Enter）關掉。
func talk_to(id: String) -> void:
	var r: Dictionary = residents[id]
	var lines: Array = r["info"].get("lines", [])
	if lines.is_empty():
		return
	var line: String = lines[r["said"] % lines.size()]
	r["said"] += 1
	_set_speaker(r["info"]["name"], _speaker_texture(id))
	dialogue_label.text = "%s\n（%s 繼續）" % [line, Keys.hint("jump")]
	dialogue_panel.visible = true
	player.frozen = true
	lingering = true
	audio.motif(state.region)
	playlog.write("talk", {"npc": r["info"].get("memory_key", id), "region": state.region})


func region_name(id: String = "") -> String:
	return regions.get(id if id != "" else state.region, {}).get("name", "")


## 前往另一個地區：花掉 travel_hours 個時辰，換落腳地圖，請導演補貨，再看有沒有事件。
## by_portal：走傳送點過去的，出現在新地圖通往原地區的那一端。
func travel_to(id: String, by_portal := false) -> bool:
	if blocking() or not regions.has(id) or id == state.region:
		return false
	if state.tier_index < int(REGION_MIN_TIER.get(id, 0)):
		add_log("師門規矩：%s需%s以上方可前往。" % [region_name(id), state.ruleset["tiers"][REGION_MIN_TIER[id]]])
		return false
	var new_day := advance_time(int(regions[id].get("travel_hours", 1)))
	var from: String = state.region
	state.region = id
	audio.play("travel")
	audio.motif(id)
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
	if blocking() or dialogue_panel.visible:
		return
	travel_options = regions.keys().filter(func(id): return id != state.region)
	var text := "前往何處？（目前在%s）" % region_name()
	for i in travel_options.size():
		var id: String = travel_options[i]
		var note := "（需%s）" % state.ruleset["tiers"][REGION_MIN_TIER[id]] if state.tier_index < int(REGION_MIN_TIER.get(id, 0)) else ""
		text += "\n  %d. %s・%d 個時辰%s" % [i + 1, region_name(id), int(regions[id].get("travel_hours", 1)), note]
	text += "\n  （%s 選、%s 確定、Esc 取消）" % [Keys.first("move_up") + Keys.first("move_down"), Keys.hint("jump")]
	_set_speaker("輿圖", null)
	_set_menu_text(text)
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
	# summary 是寫給導演與設計者看的（會劇透），玩家只看標題
	add_log("【%s】" % pack["meta"]["title"])
	_scroll_card(pack["meta"]["title"], event_seal(pack), true)
	_heart_demon_event = pack["meta"].get("request_tag", "") == "heart_demon" or _pack_has_tag(pack, "illusion")
	_combat_hold = 0.0
	if _heart_demon_event:
		audio.stinger("heart_demon", "event_start")
	else:
		audio.stinger("event_start", "event_start")
	pack_stats = {"started": Time.get_ticks_msec(), "lines": 0, "skipped": 0, "rewritten": 0}
	playlog.write("pack_start", {"pack": pack["id"], "title": pack["meta"]["title"], "author": pack["meta"].get("author", ""),
		"request_tag": pack["meta"].get("request_tag", ""), "region": state.region, "day": state.day, "tier": state.tier_name()})
	if not is_field_pack(pack):
		_clear_residents()
		clear_wild()
	runner = PackRunner.new(pack, state)
	runner.actor_spawned.connect(_on_actor_spawned)
	runner.actor_despawned.connect(_remove_actor_view)
	runner.line_shown.connect(_on_line_shown)
	runner.line_updated.connect(_on_line_updated)
	runner.dialogue_ended.connect(_on_dialogue_ended)
	runner.objective_changed.connect(func(_t): refresh_objective())
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
	_scroll_card(title, {"complete": "了", "fail": "敗", "abandon": "罷"}[result], false)
	audio.stinger("event_end", "event_end")
	runner = null
	hud_objective.text = ""
	objective_panel.visible = false
	if dialogue_panel.visible and current_choices.is_empty() and result != "abandon":
		lingering = true
	else:
		_hide_dialogue()
	update_movement_skills()  # 事件可能用旗標傳授身法
	if had_map and lingering:
		# 最後一句還在畫面上：玩家關掉對話後才回落腳地圖，免得台詞蓋在別的場景上
		home_after_dialogue = true
	elif had_map:
		go_home()
	else:
		_spawn_residents()
		refresh_wild()
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
		if not use_director:
			pass  # 已經停用，還在路上的請求不再重複提示
		elif reason.contains("401"):
			# 存取碼錯了或沒填：這次就不再連導演，免得每個動作都報錯
			use_director = false
			add_log("（存取碼無效，這次只玩手寫事件。）")
		else:
			add_log("（AI 導演暫時沒有回應，稍後再試。）")


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
	if not hostile and runner != null:
		_add_event_mark(view, event_seal(runner.pack).left(1))
	view.set_meta("hostile", hostile)
	level.add_child(view)
	var power := float(actor.get("power", 1.0))
	actor_views[actor["id"]] = view
	actor_power[actor["id"]] = power
	var boss: bool = hostile and actor["template"].begins_with("boss.")
	actor_tier.erase(actor["id"])
	actor_hp[actor["id"]] = Cultivation.enemy_hp(power, pack_tier(), boss)
	actor_max_hp[actor["id"]] = actor_hp[actor["id"]]
	actor_boss.erase(actor["id"])
	if boss:
		actor_boss[actor["id"]] = false  # false＝還沒發狠
	enemy_cooldown[actor["id"]] = 0.0


## 角色的樣子：有圖畫圖，沒圖畫色塊，頭上掛名字。原點在腳底。
func _make_actor_view(actor: Dictionary, hostile: bool) -> Node2D:
	var view := ActorView.new()
	view.hostile = hostile
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
		sprite.material = InkUI.halo_material("hostile" if hostile else "npc")
		size = Vector2(tex.get_width() * sprite.scale.x, height)
		view.add_child(sprite)
	else:
		var body := ColorRect.new()
		body.color = Color("#c0392b") if hostile else Color("#7fb3d5")
		body.size = size
		body.position = Vector2(-size.x / 2, -size.y)
		view.add_child(body)
	view.set_meta("height", size.y)
	var label := Label.new()
	label.text = "%s・%s" % [actor.get("title", ""), actor["name"]] if actor.has("title") else actor["name"]
	label.size = Vector2(240, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-120, -size.y - 26)
	label.add_theme_font_size_override("font_size", 14)
	if hostile:
		label.add_theme_color_override("font_color", Color("#ffb4a6"))
	view.add_child(label)
	return view


func _remove_actor_view(id: String) -> void:
	enemy_windup.erase(id)
	if actor_views.has(id):
		actor_views[id].queue_free()
		actor_views.erase(id)


func _on_reward(effect: Dictionary) -> void:
	if effect["type"] == "give_loot":
		var items: Array = loot.get(effect["loot_table"], {}).get(effect["tier"], [])
		for item in items:
			state.add_item(item)
		add_log("獲得：" + "、".join(items))
		audio.play("reward")
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
	var text: String = line["text"]
	_set_speaker(speaker, _speaker_texture(line["speaker"]) if speaker != "" else null)
	current_choices = line["choices"]
	for i in current_choices.size():
		text += "\n  %d. %s" % [i + 1, current_choices[i]["text"]]
	if current_choices.is_empty():
		text += "\n（%s 繼續）" % Keys.hint("jump")
	_set_menu_text(text)
	dialogue_panel.visible = true
	player.frozen = true


func _on_dialogue_ended() -> void:
	_hide_dialogue()


func _hide_dialogue() -> void:
	lingering = false
	current_choices = []
	dialogue_panel.visible = false
	player.frozen = false
	if home_after_dialogue and runner == null:
		home_after_dialogue = false
		go_home()


func advance_dialogue() -> void:
	if lingering:
		_hide_dialogue()
	elif runner != null and runner.current_node != "":
		_note_skip()
		audio.play("ui_tick")
		runner.advance()


## i 是畫面上的選項順序（從 0 開始）。
## 翻頁前看這句停留多久，太短算跳過
func _note_skip() -> void:
	var read_ms := line_length / READ_CHARS_PER_SEC * 1000.0
	if Time.get_ticks_msec() - line_shown_at < read_ms * SKIP_FACTOR:
		pack_stats["skipped"] = int(pack_stats.get("skipped", 0)) + 1


func choose_visible(i: int) -> void:
	if runner != null and i < current_choices.size():
		audio.play("ui_tick")
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
	if blocking():
		return
	var gain: int = Cultivation.MEDITATE_EXP_IN_SECT if state.region == "region.qingyun_sect" else Cultivation.MEDITATE_EXP
	var new_day := advance_time(1)
	state.game_data["hp"] = Cultivation.max_hp(state.tier_index)
	audio.play("meditate")
	player.sit(1.6)
	add_log("打坐一個時辰。（第 %d 天・%s）" % [state.day, state.time_of_day])
	gain_cultivation(gain)
	if new_day:
		day_started()
		restock()
	refresh_wild()
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
## 這個敵人的強度境界：野怪看地區，事件裡的敵人看內容包
func enemy_tier(id: String) -> int:
	return int(actor_tier.get(id, pack_tier()))


func pack_tier() -> int:
	if runner == null:
		return 0
	return maxi(0, state.tier_index_of(runner.pack["meta"]["tier_range"]["min"]))


func attack() -> void:
	if attack_cooldown > 0.0:
		return
	attack_cooldown = ATTACK_COOLDOWN
	var glyph: Node2D = player.play_attack()
	audio.play("attack")
	for id in actor_views.keys():
		var view: Node2D = actor_views[id]
		if view.get_meta("hostile") and absf(view.position.x - player.position.x) <= ATTACK_RANGE and player_near_ground():
			damage_actor(id, Cultivation.player_damage(state.tier_index))
			if glyph != null:
				glyph.shatter()


func player_near_ground() -> bool:
	return player.feet() > FLOOR_Y - MELEE_HEIGHT


func damage_actor(id: String, amount: int) -> void:
	if not actor_views.has(id):
		return
	actor_hp[id] -= amount
	audio.play("hit")
	add_log("擊中 %s（剩 %d）" % [actor_label(id), maxi(0, actor_hp[id])])
	var view: Node2D = actor_views[id]
	if view.has_method("hit"):
		view.hit(player.position.x)
	# 雙向擊退：敵人退、玩家也被反推一點；打斷前搖
	var away := signf(view.position.x - player.position.x)
	if away == 0.0:
		away = float(player.facing)
	# Boss 站得穩，只退一半
	view.position.x += away * ENEMY_KNOCKBACK * (0.5 if actor_boss.has(id) else 1.0)
	player.move_and_collide(Vector2(-away * PLAYER_RECOIL, 0))
	_cancel_windup(id)
	InkFx.number(level, view.position + Vector2(0, -110), str(amount), Color("#f3ecd9"))
	if actor_hp[id] <= 0:
		hitstop(HITSTOP_KILL)
		player.shake(5.0)
		audio.play("defeat")
		if view.has_method("die"):
			actor_views.erase(id)
			view.die()
		else:
			_remove_actor_view(id)
		enemy_windup.erase(id)
		if wild.has(id):
			_wild_defeated(id)
		else:
			gain_cultivation(Cultivation.kill_exp(float(actor_power.get(id, 1.0))))
		if runner != null:
			runner.notify({"type": "actor_defeated", "actor": id})
	else:
		hitstop(HITSTOP)
		if actor_boss.get(id, true) == false and actor_hp[id] <= actor_max_hp[id] * Cultivation.BOSS_ENRAGE_AT:
			actor_boss[id] = true
			add_log("%s怒了，出手更快！" % actor_label(id))
			player.shake(4.0)


## 命中停頓：整個遊戲停一下再恢復。計時器用真實時間；main 被釋放也會恢復（_exit_tree）。
func hitstop(seconds: float) -> void:
	if not hitstop_enabled or not is_inside_tree():
		return
	Engine.time_scale = 0.05
	get_tree().create_timer(seconds, true, false, true).timeout.connect(Engine.set.bind("time_scale", 1.0))


func _exit_tree() -> void:
	Engine.time_scale = 1.0


## 發狠的 Boss 出招更快（乘在前搖與收招時間上）
func _enemy_speed(id: String) -> float:
	return Cultivation.BOSS_ENRAGE_SPEED if actor_boss.get(id, false) == true else 1.0


func _cancel_windup(id: String) -> void:
	enemy_windup.erase(id)
	var view = actor_views.get(id)
	if view != null and view.has_method("telegraph"):
		view.telegraph(false)


## 前搖結束：玩家還在眼前、在地面附近、不在無敵時間，才算打中。
func _enemy_strike(id: String) -> void:
	_cancel_windup(id)
	enemy_cooldown[id] = Cultivation.ENEMY_RECOVER * _enemy_speed(id)
	var view: Node2D = actor_views[id]
	if absf(player.position.x - view.position.x) > ENEMY_STRIKE_REACH or not player_near_ground() or player_invuln > 0.0 or player.dashing > 0.0:
		return
	player_invuln = PLAYER_INVULN
	player.knock_back(view.position.x)
	damage_player(Cultivation.enemy_damage(float(actor_power.get(id, 1.0)), enemy_tier(id)))


func actor_label(id: String) -> String:
	if wild.has(id):
		return wild[id]["name"]
	if runner != null:
		for a in runner.pack.get("actors", []):
			if a["id"] == id:
				return a["name"]
	return id


func damage_player(amount: int) -> void:
	state.game_data["hp"] = maxi(0, hp() - amount)
	InkFx.number(level, player.position + Vector2(0, -90), "-%d" % amount, Color("#e0503c"))
	var flash := player.create_tween()
	player.rig.modulate = Color(1.0, 0.4, 0.35)
	flash.tween_property(player.rig, "modulate", Color.WHITE, 0.3)
	audio.play("hurt")
	if amount > 0:
		player.shake(6.0)
	if hp() == 0:
		player_down()


## 重傷倒地：事件以失敗結算，醒來時血回一半、過了一個時辰。
func player_down() -> void:
	add_log("你重傷倒地，人事不知……")
	playlog.write("player_down", {"pack": runner.pack["id"] if runner != null else "", "region": state.region})
	for id in enemy_cooldown:
		enemy_cooldown[id] = ENEMY_HIT_INTERVAL
	for id in enemy_windup.keys():
		_cancel_windup(id)
	var in_event := blocking()
	if in_event:
		runner.abort("fail")
	state.game_data["hp"] = Cultivation.max_hp(state.tier_index) / 2
	if advance_time(1):
		day_started()
	add_log("醒來時已是%s。" % state.time_of_day)
	if not in_event and not blocking():
		# 被野怪打倒：醒在落腳點，野怪跟著新的時辰換班
		_map_gen += 1
		place_player(regions.get(state.region, {}).get("spawn", ""))
		refresh_wild()
	_refresh_status()


func _process(delta: float) -> void:
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	player_invuln = maxf(0.0, player_invuln - delta)
	player.camera_zone = active_camera_zone()
	_update_ambience()
	# 受傷後無敵時閃爍
	player.modulate.a = 0.35 if player_invuln > 0.0 and fmod(player_invuln, 0.14) < 0.07 else 1.0
	_combat_hold = COMBAT_MUSIC_HOLD if (blocking() and _hostile_near()) else maxf(0.0, _combat_hold - delta)
	audio.play_music(music_choice(), state.region)
	audio.set_mood(absf(player.velocity.x) > 10.0 or player.climbing, in_danger(), dialogue_panel.visible, delta)
	_update_prompt()
	if runner != null:
		for p in points:
			if not runner.reached_points.has(p) and absf(points[p] - player.position.x) < 32.0:
				runner.notify({"type": "reach_point", "point": p})
				if runner == null:
					return
	if dialogue_panel.visible or player.frozen:
		return
	var gen := _map_gen
	var was_runner = runner
	for id in actor_views.keys():
		var view: Node2D = actor_views[id]
		if not view.get_meta("hostile"):
			continue
		var dx := player.position.x - view.position.x
		# 敵人出招：靠近 → 前搖（頭上朱紅「煞」字）→ 判定 → 收招破綻（不動）
		if enemy_windup.has(id):
			enemy_windup[id] -= delta
			if enemy_windup[id] <= 0.0:
				_enemy_strike(id)
				if gen != _map_gen or runner != was_runner or not actor_views.has(id):
					return
			continue
		enemy_cooldown[id] = maxf(0.0, float(enemy_cooldown.get(id, 0.0)) - delta)
		if enemy_cooldown[id] > 0.0:
			continue
		if absf(dx) > 40.0:
			view.position.x += signf(dx) * HOSTILE_SPEED * delta
		if absf(dx) <= ENEMY_REACH and player_near_ground():
			enemy_windup[id] = Cultivation.enemy_windup(enemy_tier(id)) * _enemy_speed(id)
			if view.has_method("telegraph"):
				view.telegraph(true, float(view.get_meta("height", 120.0)))
			audio.play("enemy_windup")


## 配樂節奏層：事件進行中，或附近有敵意角色
## 地圖盡頭的墨霧：從邊界往外由淡轉濃。side -1 在左端，1 在右端。
func _edge_mist(edge_x: float, side: int) -> TextureRect:
	var g := GradientTexture2D.new()
	g.width = 64
	g.height = 4
	g.gradient = Gradient.new()
	var ink := Color(0.13, 0.11, 0.1)
	g.gradient.set_color(0, Color(ink, 0.0) if side > 0 else ink)
	g.gradient.set_color(1, ink if side > 0 else Color(ink, 0.0))
	var mist := TextureRect.new()
	mist.texture = g
	mist.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := EDGE_MARGIN + 60.0
	mist.size = Vector2(w + 200.0, 1400)
	mist.position = Vector2(edge_x - 40.0 if side > 0 else edge_x - w - 160.0, FLOOR_Y - 1000)
	if side > 0:
		g.gradient.set_offset(1, w / mist.size.x)
	else:
		g.gradient.set_offset(0, 1.0 - w / mist.size.x)
	mist.z_index = 3
	return mist


## 玩家站在戰場鏡頭範圍內、而且有敵人在場時，鏡頭鎖住戰場。
func active_camera_zone() -> Dictionary:
	if not actor_views.values().any(func(v): return v.get_meta("hostile")):
		return {}
	for zone in camera_zones:
		if player.position.x >= zone["x0"] and player.position.x <= zone["x1"]:
			return zone
	return {}


func in_danger() -> bool:
	return blocking() or _hostile_near()


func _hostile_near() -> bool:
	for view in actor_views.values():
		if view.get_meta("hostile") and absf(view.position.x - player.position.x) < DANGER_RANGE:
			return true
	return false


## 該放哪一首配樂（每格呼叫，曲子沒變就不會重播）：
## 1. 事件裡有敵人在附近（剛打完也多留幾秒）→ 戰鬥曲；心魔事件 → 心魔對決曲。
## 2. 事件進行中（會擋住移動的那種）→ 地圖本身有專屬曲（心魔幻境）就用它，否則劇情曲。
## 3. 平常 → 玩家所在區塊的標籤有專屬曲（山洞、村落、山神廟、妖窟、傳功殿）就用它，否則地區的分層配樂。
## 野怪不換曲，只讓分層配樂的鼓聲層進來。
func music_choice() -> String:
	var tags := current_span_tags()
	var place: String = audio.music_key(state.region, tags)
	if blocking():
		if _combat_hold > 0.0:
			var fight := "event.heart_demon" if _heart_demon_event else "event.combat"
			if audio.music.has(fight):
				return fight
		if place.begins_with("tag.") and audio.music.get(place, {}).has("layers"):
			return place
		if audio.music.has("event.story"):
			return "event.story"
	return place


func current_span_tags() -> Array:
	for span in chunk_spans:
		if player.position.x >= span["x0"] and player.position.x < span["x1"]:
			return span["tags"]
	return state.map_tags


func _pack_has_tag(pack: Dictionary, tag: String) -> bool:
	for entry in pack.get("map", {}).get("chunks", []):
		if tag in chunks.get(entry["chunk"], {}).get("tags", []):
			return true
	return false


## 站在傳送點或 NPC 旁邊時，畫面下方提示可以按 ↑。
func _update_prompt() -> void:
	var text := ""
	if not dialogue_panel.visible and not player.climbing:
		var portal := nearby_portal()
		if not portal.is_empty():
			var need := int(REGION_MIN_TIER.get(portal["to"], 0))
			if state.tier_index < need:
				text = "需%s才能前往%s" % [state.ruleset["tiers"][need], region_name(portal["to"])]
			else:
				text = "%s 前往%s" % [Keys.hint("interact"), region_name(portal["to"])]
		elif nearby_cache() != "":
			text = Keys.hint("interact") + " 拿取"
		elif nearby_board():
			text = Keys.hint("interact") + " 看差事榜"
		elif nearby_resident() != "":
			text = Keys.hint("interact") + " 交談"
	prompt_label.text = text
	prompt_label.visible = text != ""
	if prompt_label.visible and player.is_inside_tree():
		# 跟在角色頭上
		var head := player.get_viewport().get_canvas_transform() * (player.global_position + Vector2(0, -PROMPT_HEIGHT))
		prompt_label.position = Vector2(head.x - prompt_label.size.x / 2, head.y - 28)


# ---------- 除錯：製造觸發條件 ----------

func spare_fox() -> void:
	state.set_flag("spared_white_fox", true)
	add_log("你放走了山崖下受傷的白狐。（第 %d 天）" % state.day)


func pass_day() -> void:
	state.day += 1
	add_log("過了一天，現在是第 %d 天。" % state.day)
	day_started()
	restock()
	refresh_wild()
	check_triggers({"type": "time_changed"})


func next_time() -> void:
	var times: Array = state.ruleset["times_of_day"]
	state.time_of_day = times[(times.find(state.time_of_day) + 1) % times.size()]
	add_log("時辰：" + state.time_of_day)
	refresh_wild()
	check_triggers({"type": "time_changed"})


func breakthrough() -> void:
	if state.tier_index + 1 >= state.ruleset["tiers"].size():
		return
	state.tier_index += 1
	_breakthrough_wash()
	state.game_data["hp"] = Cultivation.max_hp(state.tier_index)
	playlog.write("breakthrough", {"tier": state.tier_name(), "day": state.day})
	audio.stinger("breakthrough", "breakthrough")
	add_log("突破至" + state.tier_name() + "！")
	update_movement_skills()
	check_triggers({"type": "tier_up", "to": state.tier_name()})
	prepare_heart_demon()


func _unhandled_input(event: InputEvent) -> void:
	if key_panel != null and key_panel.visible:
		return
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
	elif event is InputEventJoypadButton:
		if not event.pressed:
			return
	else:
		return
	handle_input(event)
	_refresh_status()


## 一個按下去的按鍵／手把按鈕（測試也直接呼叫這個）。
func handle_input(event: InputEvent) -> void:
	var kc: int = event.physical_keycode if event is InputEventKey else 0
	var number := kc - KEY_1 if kc >= KEY_1 and kc <= KEY_4 else -1
	var confirm: bool = event.is_action_pressed("jump") or event.is_action_pressed("attack") or kc == KEY_ENTER or kc == KEY_KP_ENTER
	var cancel: bool = event.is_action_pressed("settings")
	var count := menu_count()
	# 有編號選項時：1-4 直接選，上下鍵／十字鍵移動游標，跳／攻擊／Enter 確定
	if count > 0:
		if number >= 0:
			choose_menu(number)
		elif event.is_action_pressed("move_up"):
			move_menu_cursor(-1)
		elif event.is_action_pressed("move_down"):
			move_menu_cursor(1)
		elif confirm:
			choose_menu(menu_cursor)
		elif cancel or event.is_action_pressed("map"):
			if not travel_options.is_empty():
				close_travel_menu()
			elif not errand_options.is_empty():
				close_errand_board()
		return
	if not errand_options.is_empty():   # 差事榜上沒東西可接：任何確定／取消都關掉
		if confirm or cancel or event.is_action_pressed("interact"):
			close_errand_board()
		return
	if dialogue_panel.visible:
		if confirm:
			advance_dialogue()
		elif cancel and lingering:
			_hide_dialogue()
		return
	if event.is_action_pressed("settings"):
		open_key_panel()
	elif event.is_action_pressed("map"):
		open_travel_menu()
	elif event.is_action_pressed("interact"):
		interact()
	elif event.is_action_pressed("attack"):
		attack()
	elif event.is_action_pressed("meditate"):
		meditate()
	elif event.is_action_pressed("breakthrough"):
		try_breakthrough()
	elif event.is_action_pressed("music"):
		add_log("配樂：" + ("開" if audio.toggle_music() else "關"))
	elif event.is_action_pressed("jump"):
		advance_dialogue()   # 事件剛結束、對話框收起前的最後一句
	match kc:
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


# ---------- 選單游標 ----------

## 對話框裡有幾個編號選項（對話選項、差事榜、地圖）。
func menu_count() -> int:
	if not travel_options.is_empty():
		return travel_options.size()
	if not errand_options.is_empty():
		return errand_options.size() if errand_options[0]["kind"] != "none" else 0
	if dialogue_panel.visible:
		return current_choices.size()
	return 0


func choose_menu(i: int) -> void:
	if not travel_options.is_empty():
		choose_travel(i)
	elif not errand_options.is_empty():
		choose_errand(i)
	else:
		choose_visible(i)


func move_menu_cursor(d: int) -> void:
	var n := menu_count()
	if n == 0:
		return
	menu_cursor = posmod(menu_cursor + d, n)
	audio.play("ui_tick")
	_render_menu()


func _set_menu_text(text: String) -> void:
	menu_text = text
	menu_cursor = 0
	_render_menu()


## 編號選項那幾行（「  1. ……」）裡，游標所在的那行換成「▶ 1. ……」。
func _render_menu() -> void:
	var lines := menu_text.split("\n")
	var n := 0
	for i in lines.size():
		var l: String = lines[i]
		if l.length() > 4 and l.begins_with("  ") and l[2].is_valid_int() and l[3] == ".":
			if n == menu_cursor and menu_count() > 1:
				lines[i] = "◆ " + l.substr(2)
			n += 1
	dialogue_label.text = "\n".join(lines)


# ---------- 按鍵設定 ----------

func open_key_panel() -> void:
	if key_panel == null:
		key_panel = KeyPanel.new()
		key_panel.keys_path = keys_path
		key_panel.changed.connect(_on_keys_changed)
		key_panel.closed.connect(func():
			player.input_blocked = false
			_refresh_status())
		hud_layer.add_child(key_panel)
	player.input_blocked = true
	key_panel.open()


func _on_keys_changed() -> void:
	help_label.text = Keys.help_line()
	_update_prompt()


# ---------- HUD ----------

func _build_hud() -> void:
	var vignette_layer := CanvasLayer.new()
	vignette_layer.layer = 1
	add_child(vignette_layer)
	fx_layer = vignette_layer
	vignette = TextureRect.new()
	vignette.texture = InkUI.vignette_texture()
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_layer.add_child(vignette)
	# 全畫面宣紙纖維：乘法疊上去，古畫、程式畫角色、介面像在同一張紙上（reference-study.md A5）
	var grain_tex: Texture2D = load("res://art/ui/paper_grain.png") if ResourceLoader.exists("res://art/ui/paper_grain.png") else null
	if grain_tex:
		var grain := TextureRect.new()
		grain.texture = grain_tex
		grain.stretch_mode = TextureRect.STRETCH_TILE
		grain.set_anchors_preset(Control.PRESET_FULL_RECT)
		grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mul := CanvasItemMaterial.new()
		mul.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		grain.material = mul
		vignette_layer.add_child(grain)
	var hud := CanvasLayer.new()
	hud.layer = 2
	add_child(hud)
	hud_layer = hud
	# 左上：墨底狀態列，朱砂邊
	var status_panel := PanelContainer.new()
	status_panel.add_theme_stylebox_override("panel", InkUI.ink_box(0.62, InkUI.CINNABAR))
	status_panel.position = Vector2(16, 12)
	hud.add_child(status_panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	status_panel.add_child(rows)
	hud_status = Label.new()
	hud_status.theme_type_variation = "HudTitle"
	rows.add_child(hud_status)
	var bars := HBoxContainer.new()
	bars.add_theme_constant_override("separation", 8)
	rows.add_child(bars)
	for spec in [["修為", InkUI.JADE], ["氣血", InkUI.CINNABAR]]:
		var name := Label.new()
		name.text = spec[0]
		name.theme_type_variation = "HudSmall"
		bars.add_child(name)
		var b := InkUI.bar(spec[1], 130.0)
		bars.add_child(b)
		if spec[0] == "修為":
			exp_bar = b
		else:
			hp_bar = b
	hud_detail = Label.new()
	hud_detail.theme_type_variation = "HudSmall"
	rows.add_child(hud_detail)
	# 右上：目標
	objective_panel = PanelContainer.new()
	objective_panel.add_theme_stylebox_override("panel", InkUI.ink_box(0.62, InkUI.GOLD))
	objective_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	objective_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	objective_panel.offset_right = -16
	objective_panel.offset_top = 12
	objective_panel.visible = false
	hud.add_child(objective_panel)
	hud_objective = Label.new()
	objective_panel.add_child(hud_objective)
	# 紀錄：狀態列下方，一段時間沒有新訊息就淡出
	log_panel = PanelContainer.new()
	log_panel.add_theme_stylebox_override("panel", InkUI.ink_box(0.45))
	log_panel.position = Vector2(16, 120)
	log_panel.custom_minimum_size = Vector2(0, 0)
	hud.add_child(log_panel)
	hud_log = Label.new()
	hud_log.theme_type_variation = "HudSmall"
	hud_log.custom_minimum_size = Vector2(0, 0)
	hud_log.autowrap_mode = TextServer.AUTOWRAP_OFF
	log_panel.add_child(hud_log)
	# 對話框：紙卷，左邊頭像，上緣朱砂名牌，兩端軸頭
	dialogue_panel = PanelContainer.new()
	dialogue_panel.add_theme_stylebox_override("panel", InkUI.paper_box())
	dialogue_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dialogue_panel.offset_left = -480
	dialogue_panel.offset_right = 480
	dialogue_panel.offset_top = -190
	dialogue_panel.offset_bottom = -36
	dialogue_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dialogue_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dialogue_panel.visible = false
	hud.add_child(dialogue_panel)
	var line_row := HBoxContainer.new()
	line_row.add_theme_constant_override("separation", 22)
	dialogue_panel.add_child(line_row)
	portrait_frame = PanelContainer.new()
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("#d8ccad")
	frame.border_color = InkUI.INK_SOFT
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(2)
	portrait_frame.add_theme_stylebox_override("panel", frame)
	portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line_row.add_child(portrait_frame)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(104, 104)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_frame.add_child(portrait)
	dialogue_label = Label.new()
	dialogue_label.theme_type_variation = "PaperLabel"
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialogue_label.custom_minimum_size = Vector2(0, 104)
	line_row.add_child(dialogue_label)
	for side in [0, 1]:
		var roller := Panel.new()
		roller.add_theme_stylebox_override("panel", InkUI.roller())
		roller.top_level = true
		roller.mouse_filter = Control.MOUSE_FILTER_IGNORE
		roller.set_meta("side", side)
		roller.add_to_group("roller")
		dialogue_panel.add_child(roller)
	dialogue_name_box = PanelContainer.new()
	dialogue_name_box.add_theme_stylebox_override("panel", InkUI.seal_box())
	dialogue_name_box.top_level = true
	dialogue_panel.add_child(dialogue_name_box)
	dialogue_name = Label.new()
	dialogue_name.theme_type_variation = "NameLabel"
	dialogue_name_box.add_child(dialogue_name)
	dialogue_panel.resized.connect(_layout_dialogue)
	dialogue_panel.visibility_changed.connect(_layout_dialogue)
	help_label = Label.new()
	help_label.text = Keys.help_line()
	help_label.theme_type_variation = "HudSmall"
	help_label.position = Vector2(16, 694)
	help_label.modulate = Color(1, 1, 1, 0.6)
	hud.add_child(help_label)
	prompt_label = Label.new()
	prompt_label.visible = false
	prompt_label.size = Vector2(400, 0)
	prompt_label.position = Vector2(440, 640)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 20)
	prompt_label.add_theme_color_override("font_color", Color("#f6e7b8"))
	hud.add_child(prompt_label)
	_refresh_status()


## 軸頭與名牌是 top_level，跟著對話框的位置擺
func _layout_dialogue() -> void:
	var r := dialogue_panel.get_global_rect()
	for roller in get_tree().get_nodes_in_group("roller"):
		roller.size = Vector2(18, r.size.y + 22)
		roller.position = Vector2(r.position.x - 12 if roller.get_meta("side") == 0 else r.end.x - 6, r.position.y - 11)
	dialogue_name_box.position = Vector2(r.position.x + 150, r.position.y - 16)


## 說話者：名牌與頭像。speaker 是角色 id、"player" 或空字串（旁白）。
func _set_speaker(display_name: String, tex: Texture2D) -> void:
	dialogue_name.text = display_name
	dialogue_name_box.visible = display_name != ""
	portrait.texture = _portrait_crop(tex)
	portrait_frame.visible = portrait.texture != null
	_layout_dialogue()


var _portrait_cache: Dictionary = {}


## 從全身立繪裁出頭肩：依不透明範圍取上面約四成。
func _portrait_crop(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	if _portrait_cache.has(tex):
		return _portrait_cache[tex]
	var used := Rect2i(0, 0, tex.get_width(), tex.get_height())
	var img := tex.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		var u := img.get_used_rect()
		if u.size.x > 0:
			used = u
	var side := int(used.size.y * 0.36)
	var cx := used.position.x + used.size.x / 2
	# 頭通常在不透明範圍頂端、略偏中線；面朝右，往右挪一點
	var region := Rect2(cx - side / 2 + side * 0.04, used.position.y - side * 0.04, side, side)
	var crop := AtlasTexture.new()
	crop.atlas = tex
	crop.region = region
	crop.filter_clip = true
	_portrait_cache[tex] = crop
	return crop


func _speaker_texture(speaker: String) -> Texture2D:
	if speaker == "player":
		return art.texture("player.disciple")
	var view: Node2D = actor_views.get(speaker)
	if view == null and residents.has(speaker):
		view = residents[speaker]["view"]
	if view != null:
		for n in view.get_children():
			if n is Sprite2D:
				return n.texture
	# 還沒出場（例如在畫面外喊話）：照內容包的角色表找出場時會用的同一張立繪
	if runner != null:
		for actor in runner.pack.get("actors", []):
			if actor.get("id", "") == speaker:
				var key: String = actor.get("memory_key", actor.get("name", ""))
				var hostile: bool = actor.get("disposition", "") == "hostile"
				return art.texture(actor.get("template", ""), key, "mob.generic" if hostile else "npc.generic")
	return null


func _refresh_status() -> void:
	if state == null or hud_status == null:
		return
	var karma := []
	for axis in state.karma:
		karma.append("%s %d" % [axis, state.karma[axis]])
	hud_status.text = "%s　第 %d 天・%s　%s" % [region_name(), state.day, state.time_of_day, state.tier_name()]
	var need := Cultivation.need(state.tier_index)
	exp_bar.max_value = maxf(1.0, float(need))
	exp_bar.value = cultivation()
	hp_bar.max_value = maxf(1.0, float(Cultivation.max_hp(state.tier_index)))
	hp_bar.value = hp()
	hud_detail.text = "修為 %d／%d　氣血 %d／%d　%s" % [cultivation(), need, hp(), Cultivation.max_hp(state.tier_index), "　".join(karma)]
	if tint != null:
		var target := InkUI.time_tint(state.time_of_day) * InkUI.karma_tint(_karma_lean())
		if vignette != null:
			vignette.modulate.a = 0.85 + 0.15 * maxf(0.0, -_karma_lean())
		if tint.color != target:
			if is_inside_tree() and tint.color != Color.WHITE:
				tint.create_tween().tween_property(tint, "color", target, 1.2)
			else:
				tint.color = target


func add_log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 8:
		log_lines.pop_front()
	if hud_log:
		hud_log.text = "\n".join(log_lines.slice(-5))
		log_panel.modulate.a = 1.0
		if log_tween != null:
			log_tween.kill()
		if log_panel.is_inside_tree():
			log_tween = log_panel.create_tween()
			log_tween.tween_interval(7.0)
			log_tween.tween_property(log_panel, "modulate:a", 0.0, 1.5)
	_refresh_status()
