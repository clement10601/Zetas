## 遊戲主控：橫軸地圖、玩家、角色，並把 ZeWorld 內容包與導演接到畫面上。
## T 開地圖在地區之間移動（青雲宗、青雲山腳、黑風嶺），移動要花時辰。
## 除錯鍵用來快速製造觸發條件：F1 放走白狐、F2 過一天、F3 換時辰、F4 突破境界、
## F6 請導演生成一個新事件、F5 存檔、F9 讀檔。
## 導演服務沒開時一切照常，只是不會有新事件與即時台詞。
extends Node2D

const WorldState = preload("res://addons/zeworld/world_state.gd")
const PackPool = preload("res://addons/zeworld/pack_pool.gd")
const TriggerJudge = preload("res://addons/zeworld/trigger_judge.gd")
const PackRunner = preload("res://addons/zeworld/pack_runner.gd")
const DirectorClient = preload("res://addons/zeworld/director_client.gd")
const Player = preload("res://scripts/player.gd")

const FLOOR_Y := 560.0
const START_REGION := "region.qingyun_foothills"
## 地區要求的最低境界（tier index）；黑風嶺築基以上才准去
const REGION_MIN_TIER := {"region.heifeng_ridge": 1}
## 補貨排程：每個地區、目前境界至少備著幾個沒玩過的事件
const RESTOCK_TARGET := 3
const HEART_DEMON_HINT := "突破到%s時的心魔幻境。心魔是玩家的鏡像，拿玩家經歷裡最難面對的事（history 裡的選擇、NPC 的記憶、karma 傾向）來質問玩家，每個玩家的心魔都該不同。地圖只用心魔幻境區塊（地圖標籤 illusion），心魔用模板 boss.heart_demon_mirror。tier_range 從%s到%s，不要設定 meta.region。通過時設旗標 %s_heart_demon_cleared。"
const ENCOUNTER_HINT := "今日奇遇：發生在玩家目前所在地區的小小偶遇，幾分鐘就能玩完，可以呼應玩家最近的經歷。今天就要能觸發：觸發條件只用這個地區區塊有的地圖標籤，可加時辰，不要用天數或其他事件才會立的旗標。獎勵要小。"
const ATTACK_RANGE := 90.0
const HOSTILE_SPEED := 70.0
const SAVE_ID := "save.001"

## 測試時設成空字串可停用存檔／導演生成資料夾；use_director 設 false 可完全不連導演。
var save_path := "user://save.json"
var generated_dir := "user://generated"
var use_director := true
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
var actor_views: Dictionary = {}  # actor id -> Node2D
var actor_hp: Dictionary = {}
var log_lines: Array = []

var hud_status: Label
var hud_objective: Label
var hud_log: Label
var dialogue_panel: PanelContainer
var dialogue_label: Label
var current_choices: Array = []
var travel_options: Array = []    # 地圖開著時可去的地區 id
var lingering := false            # 事件結束時最後一句先留在畫面上，按空白才關


func _ready() -> void:
	load_content()
	director = DirectorClient.new()
	add_child(director)
	director.pack_generated.connect(_on_pack_generated)
	director.pack_failed.connect(_on_pack_failed)
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
	go_home()
	add_log("%s。T 地圖、F1 放走白狐、F2 過一天、F3 換時辰、F4 突破境界、F6 新事件。" % region_name())
	request_followups()
	restock()
	prepare_heart_demon()
	check_triggers({"type": "enter_map"})


func load_content() -> void:
	state = WorldState.new(PackPool.load_ruleset("res://content/ruleset.json"))
	state.save_id = SAVE_ID
	pool = PackPool.load_dir("res://content/packs")
	if generated_dir != "":
		pool += PackPool.for_save(PackPool.load_dir(generated_dir), SAVE_ID)
	chunks = _read_json("res://content/chunks.json")
	loot = _read_json("res://content/loot.json")
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
	var tags: Array = []
	var x := 0.0
	var ordered := chunk_list.duplicate()
	ordered.sort_custom(func(a, b): return a["order"] < b["order"])
	for entry in ordered:
		var info: Dictionary = chunks.get(entry["chunk"], {})
		if info.is_empty():
			push_error("Zetas: unknown chunk %s" % entry["chunk"])
			continue
		var width: float = info["width"]
		var bg := ColorRect.new()
		bg.color = Color(info["color"])
		bg.position = Vector2(x, FLOOR_Y - 600)
		bg.size = Vector2(width, 600)
		level.add_child(bg)
		var name_label := Label.new()
		name_label.text = info["name"]
		name_label.position = Vector2(x + 24, FLOOR_Y - 580)
		name_label.modulate = Color(1, 1, 1, 0.5)
		level.add_child(name_label)
		for p in info.get("points", {}):
			points[p] = x + float(info["points"][p])
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
	state.map_tags = tags
	place_player(spawn_point)


## 回到目前地區的落腳地圖。
func go_home() -> void:
	var info: Dictionary = regions.get(state.region, {})
	var list := []
	for i in info.get("home", []).size():
		list.append({"chunk": info["home"][i], "order": i})
	build_map(list, info.get("spawn", ""))


func region_name(id: String = "") -> String:
	return regions.get(id if id != "" else state.region, {}).get("name", "")


## 前往另一個地區：花掉 travel_hours 個時辰，換落腳地圖，請導演補貨，再看有沒有事件。
func travel_to(id: String) -> bool:
	if runner != null or not regions.has(id) or id == state.region:
		return false
	if state.tier_index < int(REGION_MIN_TIER.get(id, 0)):
		add_log("師門規矩：%s需%s以上方可前往。" % [region_name(id), state.ruleset["tiers"][REGION_MIN_TIER[id]]])
		return false
	var day_before: int = state.day
	advance_time(int(regions[id].get("travel_hours", 1)))
	state.region = id
	go_home()
	add_log("你來到%s。（第 %d 天・%s）" % [region_name(), state.day, state.time_of_day])
	if state.day != day_before:
		day_started()
	restock()
	autosave()
	check_triggers({"type": "enter_map"})
	return true


## 時辰往前走 steps 格，過了夜就是隔天。
func advance_time(steps: int) -> void:
	var times: Array = state.ruleset["times_of_day"]
	for i in steps:
		var next: int = (times.find(state.time_of_day) + 1) % times.size()
		if next == 0:
			state.day += 1
		state.time_of_day = times[next]


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


# ---------- 觸發與內容包 ----------

func check_triggers(event: Dictionary) -> void:
	if runner != null:
		return
	var pack := TriggerJudge.pick(pool, state, event)
	if not pack.is_empty():
		start_pack(pack)


func start_pack(pack: Dictionary) -> void:
	add_log("【%s】%s" % [pack["meta"]["title"], pack["meta"]["summary"]])
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


func _on_pack_finished(result: String) -> void:
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
	if had_map:
		go_home()
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


## 目前地區、境界可用的事件不夠時請導演補（送出中的請求也算存貨）。
func restock() -> void:
	if use_director:
		director.restock(state, PackPool.for_save(pool, SAVE_ID), RESTOCK_TARGET)


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


## 請導演依玩家經歷準備下一個境界的心魔。池子裡已有該境界的突破事件（例如手寫的築基心魔）就不請。
func prepare_heart_demon() -> void:
	var tiers: Array = state.ruleset["tiers"]
	if not use_director or state.tier_index + 1 >= tiers.size():
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
	autosave()
	if pack["meta"].get("request_tag", "") == "encounter":
		check_triggers({"type": "enter_map"})


func _on_pack_failed(followup: Dictionary, reason: String) -> void:
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
		go_home()
		add_log("讀取存檔：第 %d 天，%s。" % [state.day, region_name()])


func _on_actor_spawned(actor: Dictionary) -> void:
	var view := Node2D.new()
	var hostile: bool = actor["disposition"] == "hostile"
	var size := Vector2(32, 60) * (1.3 if actor["template"].begins_with("boss.") else 1.0)
	var body := ColorRect.new()
	body.color = Color("#c0392b") if hostile else Color("#7fb3d5")
	body.size = size
	body.position = Vector2(-size.x / 2, -size.y)
	view.add_child(body)
	var label := Label.new()
	label.text = "%s・%s" % [actor.get("title", ""), actor["name"]] if actor.has("title") else actor["name"]
	label.position = Vector2(-size.x, -size.y - 28)
	view.add_child(label)
	view.position = Vector2(points.get(actor.get("spawn_at", ""), player.position.x + 200), FLOOR_Y)
	view.set_meta("hostile", hostile)
	level.add_child(view)
	actor_views[actor["id"]] = view
	actor_hp[actor["id"]] = maxi(1, roundi(3 * float(actor.get("power", 1.0))))


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
		add_log("修為大增（%s）" % effect["amount"])


func _on_presentation(effect: Dictionary) -> void:
	if effect["type"] == "teleport":
		place_player(effect["point"])


# ---------- 對話 ----------

func _on_line_shown(id: String, line: Dictionary) -> void:
	_show_line(line)
	if line["live_rewrite"] and use_director:
		director.request_rewrite(id, line["text"], runner.pack, state)


func _on_line_updated(_id: String, line: Dictionary) -> void:
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
		runner.advance()


## i 是畫面上的選項順序（從 0 開始）。
func choose_visible(i: int) -> void:
	if runner != null and i < current_choices.size():
		runner.choose(current_choices[i]["index"])


# ---------- 戰鬥（M0：近身按 J 打三下） ----------

func attack() -> void:
	for id in actor_views.keys():
		var view: Node2D = actor_views[id]
		if view.get_meta("hostile") and absf(view.position.x - player.position.x) <= ATTACK_RANGE:
			damage_actor(id, 1)


func damage_actor(id: String, amount: int) -> void:
	if not actor_views.has(id):
		return
	actor_hp[id] -= amount
	add_log("擊中 %s（剩 %d）" % [id, actor_hp[id]])
	if actor_hp[id] <= 0:
		_remove_actor_view(id)
		if runner != null:
			runner.notify({"type": "actor_defeated", "actor": id})


func _process(delta: float) -> void:
	if runner == null:
		return
	for p in points:
		if not runner.reached_points.has(p) and absf(points[p] - player.position.x) < 32.0:
			runner.notify({"type": "reach_point", "point": p})
			if runner == null:
				return
	if dialogue_panel.visible:
		return
	for id in actor_views:
		var view: Node2D = actor_views[id]
		if view.get_meta("hostile"):
			var dx := player.position.x - view.position.x
			if absf(dx) > 40.0:
				view.position.x += signf(dx) * HOSTILE_SPEED * delta


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
	add_log("突破至" + state.tier_name() + "！")
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
		KEY_SPACE, KEY_ENTER:
			advance_dialogue()
		KEY_1, KEY_2, KEY_3, KEY_4:
			choose_visible(event.physical_keycode - KEY_1)
		KEY_J:
			if not dialogue_panel.visible:
				attack()
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
	help.text = "←→ 移動　↑ 跳　J 攻擊　空白 對話　1-4 選擇　T 地圖"
	help.position = Vector2(16, 690)
	help.modulate = Color(1, 1, 1, 0.5)
	hud.add_child(help)
	_refresh_status()


func _refresh_status() -> void:
	if state == null or hud_status == null:
		return
	var karma := []
	for axis in state.karma:
		karma.append("%s %d" % [axis, state.karma[axis]])
	hud_status.text = "%s　第 %d 天・%s　境界：%s　%s" % [region_name(), state.day, state.time_of_day, state.tier_name(), "　".join(karma)]


func add_log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 8:
		log_lines.pop_front()
	if hud_log:
		hud_log.text = "\n".join(log_lines)
	_refresh_status()
