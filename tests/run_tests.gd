## Zetas 測試：內容資料一致性 + 兩個內容包在主場景中從觸發到結局跑完一遍。
## 執行：python tools/sync_engine.py && godot --headless --path . -s res://tests/run_tests.gd
extends SceneTree

const AssetLibrary = preload("res://addons/zeworld/asset_library.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


## 場景樹在 _initialize 時尚未開始運作，延後一格才會呼叫節點的 _ready。
func _run() -> void:
	await test_content_references()
	await test_fox_repays_kindness()
	await test_heart_demon_trial()
	await test_director_followup_event()
	await test_live_rewrite_updates_dialogue()
	await test_director_offline_keeps_request()
	await test_save_and_load()
	await test_regions_and_travel()
	await test_sect_first_lesson()
	await test_personal_heart_demon()
	await test_daily_encounter()
	await test_cultivation()
	await test_combat()
	await test_art_and_placeholders()
	await test_playlog()
	await test_map_layout_data()
	await test_walk_and_jump()
	await test_platforms_and_ropes()
	await test_portals_and_residents()
	await test_melee_height()
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func expect(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + what)


## 測試預設不讀寫存檔、不連導演，避免互相影響。
func new_game(director := false, save := "", assets := "", playlog := "") -> Node:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.playlog_path = playlog
	if assets != "":
		main.assets_path = assets
	main.save_path = save
	main.generated_dir = ""
	main.use_director = director
	root.add_child(main)
	await process_frame
	return main


## 內容包引用的區塊、地點、掉落表都必須存在於遊戲資料中。
func test_content_references() -> void:
	var main: Node = await new_game()
	expect(main.pool.size() == 3, "all packs load")
	for pack in main.pool:
		var region: String = pack["meta"].get("region", "")
		expect(region == "" or main.regions.has(region), "%s: region %s exists" % [pack["id"], region])
		var pts := {}
		for entry in pack.get("map", {}).get("chunks", []):
			expect(main.chunks.has(entry["chunk"]), "%s: chunk %s exists" % [pack["id"], entry["chunk"]])
			for p in main.chunks.get(entry["chunk"], {}).get("points", {}):
				pts[p] = true
		if pack.has("map"):
			for p in pack["map"]["points"] + [pack["map"]["spawn"]]:
				expect(pts.has(p), "%s: point %s exists in its chunks" % [pack["id"], p])
			for a in pack.get("actors", []):
				expect(not a.has("spawn_at") or pts.has(a["spawn_at"]), "%s: %s spawn point exists" % [pack["id"], a["id"]])
		for key in pack["outcomes"]:
			for e in pack["outcomes"][key]:
				if e["type"] == "give_loot":
					expect(main.loot.has(e["loot_table"]), "%s: loot table %s exists" % [pack["id"], e["loot_table"]])
	main.free()


func test_fox_repays_kindness() -> void:
	var main: Node = await new_game()
	main.spare_fox()
	for i in 3:
		main.pass_day()
	expect(main.runner == null, "fox event waits for dusk")
	main.next_time()
	expect(main.runner == null, "noon does not trigger")
	main.next_time()
	expect(main.runner != null and main.runner.pack["id"] == "pack.fox_repays_kindness.s001", "fox event triggers at dusk on day 3")
	expect(main.points.has("pt.clearing_center"), "clearing map built")
	expect(main.actor_views.has("fox") and not main.actor_views.has("hunter"), "fox appears, hunter waits")
	expect(main.dialogue_panel.visible and main.player.frozen, "dialogue opens and freezes player")
	for i in 3:
		main.advance_dialogue()
	expect(main.actor_views.has("hunter"), "hunter arrives")
	expect(main.current_choices.size() == 2, "betray option hidden for a non-righteous player")
	main.choose_visible(0)
	expect(main.hud_objective.text == "目標：擊退獵妖人", "objective switches to fighting the hunter")
	main.advance_dialogue()
	expect(not main.dialogue_panel.visible, "dialogue closes")
	main.damage_actor("hunter", 10)
	expect(main.runner == null, "event ends after hunter defeated")
	expect(main.state.relations.get("npc.baiheng") == 25, "白蘅 relation +25")
	expect(main.state.items.has("中品妖丹"), "rare loot from game loot table")
	expect(main.state.followups.size() == 1, "followup queued for director")
	expect(main.points.has("pt.home_start"), "back on home map")
	main.next_time()
	main.pass_day()
	expect(main.runner == null, "fox event does not repeat")
	main.free()


func test_heart_demon_trial() -> void:
	var main: Node = await new_game()
	main.breakthrough()
	expect(main.runner != null and main.runner.pack["id"] == "pack.heart_demon_trial.zhuji.s001", "breakthrough triggers heart demon")
	expect(main.state.map_tags == ["illusion"], "illusion map built")
	main.player.position.x = main.points["pt.memory_square"]
	main._process(0.016)
	expect(main.runner.reached_points.has("pt.memory_square"), "walking to the square is noticed")
	expect(main.actor_views.has("demon"), "heart demon spawns")
	for i in 3:
		main.advance_dialogue()
	expect(main.current_choices.size() == 2, "face or fight choice")
	main.choose_visible(0)
	expect(main.state.flags.get("heart_demon_faced") == true, "choice recorded")
	main.advance_dialogue()
	main.damage_actor("demon", 10)
	expect(main.runner == null, "trial ends")
	expect(main.state.flags.get("zhuji_heart_demon_cleared") == true, "trial cleared")
	expect(main.state.tier_name() == "築基", "player is now 築基")
	main.breakthrough()
	expect(main.runner == null, "no pack for 金丹 yet")
	main.free()


## 白狐事件結局交出後續請求 → 導演生成的內容包進池 → 等滿天數後在白天觸發。
func test_director_followup_event() -> void:
	var main: Node = await new_game()
	main.spare_fox()
	for i in 3:
		main.pass_day()
	main.next_time()
	main.next_time()
	for i in 3:
		main.advance_dialogue()
	main.choose_visible(0)
	main.advance_dialogue()
	main.damage_actor("hunter", 10)
	var f: Dictionary = main.state.followups[0]
	expect(f["flag"] == "followup:pack.fox_repays_kindness.s001", "fox followup carries its flag")
	var pack = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/generated_zhenyao.json"))
	f["status"] = "requested"
	main._on_pack_generated(pack, f.duplicate())
	expect(main.pool.size() == 4, "generated pack joins the pool")
	expect(f["status"] == "ready" and f["pack"] == pack["id"], "followup marked ready")
	main._on_pack_generated(pack, f.duplicate())
	expect(main.pool.size() == 4, "same pack not added twice")
	main.next_time()
	main.next_time()
	expect(main.runner == null, "followup waits for its days")
	for i in 5:
		main.pass_day()
	if main.runner == null:
		main.next_time()
	expect(main.runner != null and main.runner.pack["id"] == pack["id"], "generated event triggers after 5 days in the daytime")
	expect(main.points.has("pt.village_well"), "village map built from catalog chunks")
	main.free()


func test_live_rewrite_updates_dialogue() -> void:
	var main: Node = await new_game()
	main.spare_fox()
	for i in 3:
		main.pass_day()
	main.next_time()
	main.next_time()
	expect(main.dialogue_label.text.contains("三日前山崖下"), "authored line shown first")
	main.director.line_rewritten.emit("d1", "恩公，那日崖下一念之仁，白蘅記到今日。")
	expect(main.dialogue_label.text.contains("一念之仁"), "rewritten line replaces the authored one")
	main.advance_dialogue()
	main.director.line_rewritten.emit("d1", "遲到的改寫")
	expect(not main.dialogue_label.text.contains("遲到的改寫"), "late rewrite for an old line is ignored")
	main.free()


## 導演沒開：請求失敗後退回待送，遊戲照常。
func test_director_offline_keeps_request() -> void:
	var main: Node = await new_game(true)
	main.director.base_url = "http://127.0.0.1:9"
	main.state.followups.append({"hint": "h", "after_days": 1, "from_pack": "p", "day": 0, "flag": "followup:p", "status": ""})
	main.request_followups()
	expect(main.state.followups[0]["status"] == "requested", "followup sent")
	# 開場的補貨請求也會失敗，等到後續請求本身的失敗為止
	for i in 10:
		var failed: Array = await main.director.pack_failed
		if not failed[0].is_empty():
			break
	expect(main.state.followups[0]["status"] == "", "failed request goes back to pending")
	expect(main.director.restock(main.state, main.pool, 3) == 0, "failed restock waits before asking again")
	await process_frame  # await 在訊號發送途中恢復，下一格再釋放
	main.free()


func test_save_and_load() -> void:
	var path := "user://zetas_test_save.json"
	var main: Node = await new_game(false, path)
	main.spare_fox()
	main.pass_day()
	main.autosave()
	main.free()
	var again: Node = await new_game(false, path)
	expect(again.state.day == 1 and again.state.flags.get("spared_white_fox") == true, "save restored on start")
	again.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_regions_and_travel() -> void:
	var path := "user://zetas_test_travel.json"
	var main: Node = await new_game(false, path)
	expect(main.state.region == "region.qingyun_foothills" and main.state.map_tags.has("forest"), "new game starts in the foothills")
	for id in main.regions:
		for c in main.regions[id]["home"]:
			expect(main.chunks.has(c) and c in main.regions[id]["chunks"], "%s: home chunk %s belongs to it" % [id, c])
	expect(not main.travel_to("region.heifeng_ridge"), "煉氣 may not go to 黑風嶺")
	expect(main.state.region == "region.qingyun_foothills", "still in the foothills")
	main.open_travel_menu()
	expect(main.travel_options.size() == 2 and main.dialogue_label.text.contains("需築基"), "map lists the other regions and the tier rule")
	main.close_travel_menu()
	main.state.time_of_day = "夜"
	main.state.tier_index = 1
	expect(main.travel_to("region.heifeng_ridge"), "築基 may travel to 黑風嶺")
	expect(main.state.region == "region.heifeng_ridge" and main.state.map_tags.has("mountain"), "map switched to 黑風嶺")
	expect(main.state.day == 1 and main.state.time_of_day == "午", "two hours of travel past midnight is the next day")
	expect(main.points.has("pt.pass_start"), "黑風嶺 home map built")
	main.free()
	var again: Node = await new_game(false, path)
	expect(again.state.region == "region.heifeng_ridge" and again.points.has("pt.pass_start"), "region restored from save")
	again.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_sect_first_lesson() -> void:
	var main: Node = await new_game()
	main.spare_fox()
	expect(main.travel_to("region.qingyun_sect"), "travel to the sect")
	expect(main.runner != null and main.runner.pack["id"] == "pack.sect_first_lesson.s001", "entering the sect starts the lesson")
	expect(main.actor_views.has("lin") and main.actor_views.has("master"), "師姊 and 師父 appear")
	main.advance_dialogue()
	main.advance_dialogue()
	expect(not main.dialogue_panel.visible, "player walks to the cave")
	main.player.position.x = main.points["pt.cave_door"]
	main._process(0.016)
	expect(main.current_choices.size() == 3, "spared fox opens a third answer")
	main.choose_visible(1)
	expect(main.state.flags.get("master_knows_fox") == true, "師父 now knows about the fox")
	main.advance_dialogue()
	expect(main.runner == null, "lesson ends on 師父's last line")
	expect(main.dialogue_panel.visible and main.dialogue_label.text.contains("劍訣殘頁"), "last line stays on screen")
	main.advance_dialogue()
	expect(not main.dialogue_panel.visible, "space closes the last line")
	expect(main.state.items.has("青雲劍訣殘頁"), "sect reward from loot table")
	expect(main.state.relations.get("npc.master_qingxuan") == 10, "師父 relation +10")
	expect(main.state.history.back()["pack"] == "pack.sect_first_lesson.s001", "lesson written to history")
	expect(main.points.has("pt.sect_gate"), "back at the sect gate")
	expect(main.state.followups.back()["after_days"] == 2, "師父's errand queued for the director")
	main.free()


func generated(tag: String, trigger_all: Array, expires := 0) -> Dictionary:
	var pack = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/generated_zhenyao.json"))
	pack["id"] = "pack.gen.%s.test" % tag
	pack["meta"]["request_tag"] = tag
	pack["trigger"]["all"] = trigger_all
	if expires > 0:
		pack["trigger"]["expires_after_days"] = expires
	return pack


func test_personal_heart_demon() -> void:
	var main: Node = await new_game(true)
	main.director.base_url = "http://127.0.0.1:9"
	expect(main.heart_demon_pending == "", "築基 already has a hand-written trial")
	main.breakthrough()
	main.player.position.x = main.points["pt.memory_square"]
	main._process(0.016)
	for i in 3:
		main.advance_dialogue()
	main.choose_visible(0)
	main.advance_dialogue()
	main.damage_actor("demon", 10)
	expect(main.runner == null, "築基 trial finished")
	expect(main.heart_demon_pending == "", "no heart demon request while cultivation is far from full")
	main.gain_cultivation(300)
	expect(main.state.tier_name() == "築基" and main.heart_demon_pending == "金丹", "the director is asked for the 金丹 heart demon near the bottleneck")
	main.prepare_heart_demon()
	await main.director.pack_failed
	await process_frame
	expect(main.heart_demon_pending == "", "a failed request can be sent again later")
	var pack := generated("heart_demon", [{"type": "tier_up", "to": "金丹"}])
	main.heart_demon_pending = "金丹"
	main._on_pack_generated(pack, {})
	expect(main.heart_demon_pending == "" and main.has_breakthrough_pack("金丹"), "heart demon arrives for 金丹")
	main.prepare_heart_demon()
	expect(main.heart_demon_pending == "", "no second request while one is waiting in the pool")
	main.breakthrough()
	expect(main.runner != null and main.runner.pack["id"] == pack["id"], "breakthrough to 金丹 opens the personal heart demon")
	await process_frame
	main.free()


func test_daily_encounter() -> void:
	var main: Node = await new_game()
	var pack := generated("encounter", [{"type": "enter_map", "map_tag": "forest"}], 1)
	main._on_pack_generated(pack, {})
	expect(main.state.pack_arrivals.get(pack["id"]) == 0, "arrival day recorded")
	expect(main.runner != null and main.runner.pack["id"] == pack["id"], "today's encounter starts right away")
	main.free()
	main = await new_game()
	main.runner = Object.new()  # 玩家正在別的事件裡，奇遇等著
	main._on_pack_generated(pack, {})
	main.runner.free()
	main.runner = null
	main.pass_day()
	expect(not main.pool.has(pack) and main.runner == null, "unplayed encounter expires the next day")
	main.free()


func test_cultivation() -> void:
	var main: Node = await new_game()
	expect(main.hp() == 30 and main.cultivation() == 0, "new 煉氣 disciple: 30 hp, no cultivation")
	expect(not main.try_breakthrough() and main.state.tier_index == 0, "cannot break through without cultivation")
	main.meditate()
	expect(main.cultivation() == 8 and main.state.time_of_day == "午", "meditating in the wild: +8 and one 時辰")
	main.travel_to("region.qingyun_sect")
	main.runner.abort("abandon")  # 進宗門會開「青玄峰問心」，先結束它才能打坐
	main.advance_dialogue()
	main.meditate()
	expect(main.cultivation() == 8 + 15, "meditating in the sect: +15")
	main.gain_cultivation(100)
	expect(main.try_breakthrough() and main.state.tier_name() == "築基", "full cultivation breaks through")
	expect(main.cultivation() == 23 and main.hp() == 50, "breakthrough spends the threshold and heals to the new max")
	main.free()


func test_combat() -> void:
	var main: Node = await new_game()
	main.spare_fox()
	for i in 3:
		main.pass_day()
	main.next_time()
	main.next_time()
	for i in 3:
		main.advance_dialogue()
	main.choose_visible(0)
	main.advance_dialogue()
	expect(main.actor_hp["hunter"] == 4, "hunter hp from power 1.2 at 煉氣")
	var hunter: Node2D = main.actor_views["hunter"]
	hunter.position.x = main.player.position.x + 30
	main.attack()
	main.attack()
	expect(main.actor_hp["hunter"] == 3, "attack has a cooldown")
	main._process(1.0)
	expect(main.hp() == 30 - 5, "hunter in reach hits for 5")
	for i in 6:
		main._process(1.0)
		if main.runner == null:
			break
	expect(main.runner == null and main.state.flags.get("baiheng_captured") == true, "falling in battle settles the event as fail")
	expect(main.hp() == 15, "wake up with half hp")
	expect(main.points.has("pt.home_start"), "carried back to the home map")
	main.free()


func test_art_and_placeholders() -> void:
	var dir := "user://zetas_test_art"
	DirAccess.make_dir_recursive_absolute(dir)
	Image.create(40, 240, false, Image.FORMAT_RGBA8).save_png(dir.path_join("fox.png"))
	Image.create(96, 60, false, Image.FORMAT_RGBA8).save_png(dir.path_join("road.png"))
	var f := FileAccess.open(dir.path_join("assets.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"assets": {
		"npc.fox_girl": {"type": "sprite", "files": ["fox.png"], "height": 120},
		"chunk.qingyun_road": {"type": "chunk", "files": ["road.png"]},
	}}))
	f.close()
	var main: Node = await new_game(false, "", dir.path_join("assets.json"))
	expect(main.level.get_children().any(func(n): return n is TextureRect), "chunk with art gets its background picture")
	expect(main.level.get_children().any(func(n): return n is ColorRect and n.color == Color(main.chunks["chunk.qingyun_woods"]["color"])), "chunk without art stays a color block")
	main.spare_fox()
	for i in 3:
		main.pass_day()
	main.next_time()
	main.next_time()
	var fox: Node2D = main.actor_views["fox"]
	var sprite = fox.get_children().filter(func(n): return n is Sprite2D)
	expect(sprite.size() == 1 and is_equal_approx(sprite[0].scale.y, 0.5), "fox sprite scaled to 120 high")
	for i in 3:
		main.advance_dialogue()
	expect(main.actor_views["hunter"].get_children().any(func(n): return n is ColorRect), "hunter without art is a color block")
	var lib = AssetLibrary.from_file("res://content/assets.json")
	for t in main.chunks:
		if not t.begins_with("_"):
			expect(lib.info(t).get("type") == "chunk", "%s listed in assets.json" % t)
	main.free()
	for n in ["fox.png", "road.png", "assets.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(n)))


func test_playlog() -> void:
	var path := "user://zetas_test_playlog.jsonl"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var main: Node = await new_game(false, "", "", path)
	main.spare_fox()
	for i in 3:
		main.pass_day()
	main.next_time()
	main.next_time()
	for i in 3:
		main.advance_dialogue()  # 立刻翻頁：三句都算跳過
	main.choose_visible(1)
	main.advance_dialogue()
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	main.free()
	var rows: Array = []
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		rows.append(JSON.parse_string(line))
	var events := rows.map(func(r): return r["event"])
	expect(events == ["session_start", "pack_start", "pack_end", "session_end"], "playlog events in order: %s" % [events])
	var end: Dictionary = rows[2]
	expect(end["pack"] == "pack.fox_repays_kindness.s001" and end["result"] == "abandon", "pack end records the result")
	expect(end["lines"] >= 4 and end["skipped"] == 3, "lines shown and quick page turns counted")
	expect(rows.all(func(r): return r["session"] == rows[0]["session"]), "one session id per run")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func step(main: Node, input: Dictionary, frames: int) -> void:
	main.player.test_input = input
	for i in frames:
		await physics_frame
	main.player.test_input = {}


## 平台與繩子的資料要在區塊內、繩子兩端接在地面或平台上，平台每層差距跳得上去。
func test_map_layout_data() -> void:
	var chunks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/chunks.json"))
	var jump_height: float = 660.0 * 660.0 / (2.0 * 1800.0)
	for id in chunks:
		if id.begins_with("_"):
			continue
		var c: Dictionary = chunks[id]
		for p in c.get("platforms", []):
			expect(p["x"] >= 0 and p["x"] + p["w"] <= c["width"], "%s: platform inside the chunk" % id)
		for r in c.get("ropes", []):
			for end in [r["top"], r.get("bottom", 0)]:
				var landed: bool = end == 0 or c.get("platforms", []).any(func(p): return p["h"] == end and r["x"] >= p["x"] and r["x"] <= p["x"] + p["w"])
				expect(landed, "%s: rope at %d ends on ground or a platform (%d)" % [id, r["x"], end])
			expect(r["kind"] in ["rope", "vine", "ladder"], "%s: rope kind" % id)
		# 沒有繩子通上去的平台，要能從地面或別的平台跳上去
		for p in c.get("platforms", []):
			if c.get("ropes", []).any(func(r): return r["top"] == p["h"] and r["x"] >= p["x"] and r["x"] <= p["x"] + p["w"]):
				continue
			var from_below: bool = p["h"] < jump_height - 10 or c["platforms"].any(func(q): return q != p and p["h"] - q["h"] > 0 and p["h"] - q["h"] < jump_height - 10)
			expect(from_below, "%s: platform at h %d is reachable" % [id, p["h"]])
	var regions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/regions.json"))
	for id in regions:
		if id.begins_with("_"):
			continue
		for side in regions[id].get("exits", {}):
			var to: String = regions[id]["exits"][side]
			expect(regions[to].get("exits", {}).values().has(id), "%s <-> %s exits match" % [id, to])
		for r in regions[id].get("residents", []):
			expect(r["chunk"] in regions[id]["home"], "%s: resident %s stands on the home map" % [id, r["id"]])
			expect(not r.get("lines", []).is_empty(), "%s: resident %s has lines" % [id, r["id"]])


func test_walk_and_jump() -> void:
	var main: Node = await new_game()
	var player: CharacterBody2D = main.player
	await step(main, {}, 20)
	expect(player.is_on_floor(), "player lands on the ground")
	var x0: float = player.position.x
	await step(main, {"right": true}, 2)
	expect(player.velocity.x > 0.0 and player.velocity.x < player.SPEED, "walking speeds up instead of starting at full speed")
	await step(main, {"right": true}, 30)
	expect(player.position.x > x0 + 80.0 and is_equal_approx(player.velocity.x, player.SPEED), "walk right at full speed")
	await step(main, {}, 10)
	expect(player.velocity.x == 0.0, "letting go stops quickly")
	var ground: float = player.feet()
	var top := ground
	main.player.test_input = {"jump": true}
	for i in 40:
		await physics_frame
		top = minf(top, player.feet())
	main.player.test_input = {}
	expect(ground - top > 100.0 and ground - top < 140.0, "jump is about 120 high (%d)" % int(ground - top))
	expect(player.is_on_floor(), "lands again")
	await step(main, {}, 2)
	await step(main, {"jump": true}, 90)
	expect(player.is_on_floor(), "holding jump does not bounce forever")
	main.player.frozen = true
	await step(main, {"right": true, "jump": true}, 10)
	expect(player.is_on_floor() and player.velocity.x == 0.0, "frozen during dialogue")
	main.free()


func test_platforms_and_ropes() -> void:
	var main: Node = await new_game()
	var player: CharacterBody2D = main.player
	var road: Dictionary = main.chunks["chunk.qingyun_road"]
	expect(main.level.get_children().filter(func(n): return n.is_in_group("platform")).size() ==
		road["platforms"].size() + main.chunks["chunk.qingyun_woods"]["platforms"].size(), "home map builds its platforms")
	expect(player.ropes.size() == road["ropes"].size() + main.chunks["chunk.qingyun_woods"]["ropes"].size(), "player knows the ropes")
	expect(player.camera.limit_left == 0 and player.camera.limit_right == int(main.map_width), "camera stays inside the map")
	# 跳上第一層平台（x 260~440，高 100）
	player.position = Vector2(350, main.FLOOR_Y - 40)
	await step(main, {}, 10)
	await step(main, {"jump": true}, 45)
	expect(player.on_platform() and absf(player.feet() - (main.FLOOR_Y - 100)) < 2.0, "jump up through a one-way platform and stand on it")
	await step(main, {}, 2)  # 先放開跳鍵，下一次按才算
	await step(main, {"down": true, "jump": true}, 40)
	expect(player.is_on_floor() and not player.on_platform(), "down + jump drops through the platform")
	# 藤蔓 x 640，從地面爬到高 200 的平台
	player.position = Vector2(645, main.FLOOR_Y - 40)
	await step(main, {}, 10)
	await step(main, {"up": true}, 2)
	expect(player.climbing and player.position.x == 640.0, "up grabs the vine and snaps onto it")
	await step(main, {"up": true}, 90)
	await step(main, {}, 10)
	expect(not player.climbing and player.on_platform() and absf(player.feet() - (main.FLOOR_Y - 200)) < 2.0, "climb to the top and step onto the platform")
	await step(main, {"down": true}, 2)
	expect(player.climbing, "down at the top climbs back down")
	await step(main, {"down": true}, 20)
	await step(main, {"right": true, "jump": true}, 2)
	expect(not player.climbing and player.velocity.x > 0.0, "side jump lets go of the vine")
	await step(main, {}, 60)
	expect(player.is_on_floor(), "falls back down")
	main.free()


func test_portals_and_residents() -> void:
	var main: Node = await new_game()
	expect(main.portals.size() == 2, "foothills has portals at both ends")
	var right: Dictionary = main.portals.filter(func(p): return p["to"] == "region.heifeng_ridge")[0]
	main.player.position = Vector2(right["x"], main.FLOOR_Y - 27)
	main._process(0.016)
	expect(main.prompt_label.visible and main.prompt_label.text.contains("黑風嶺"), "standing on a portal shows where it goes")
	expect(main.interact() and main.state.region == "region.qingyun_foothills", "煉氣 is turned back at the 黑風嶺 portal")
	main.state.tier_index = 1
	expect(main.interact() and main.state.region == "region.heifeng_ridge", "築基 walks through the portal")
	var back: Dictionary = main.portals.filter(func(p): return p["to"] == "region.qingyun_foothills")[0]
	expect(absf(main.player.position.x - back["x"]) <= main.PORTAL_INSET + 1.0, "arrive at the 黑風嶺 end that leads back")
	expect(main.residents.has("mo"), "黑風嶺 has its resident")
	var mo: Node2D = main.residents["mo"]["view"]
	main.player.position = Vector2(mo.position.x + 20, main.FLOOR_Y - 27)
	main._process(0.016)
	expect(main.prompt_label.text.contains("交談"), "standing next to an NPC shows the talk prompt")
	expect(main.interact() and main.dialogue_panel.visible and main.dialogue_label.text.contains("莫老三"), "talk to the resident")
	expect(main.player.frozen, "player stands still while talking")
	main.advance_dialogue()
	expect(not main.dialogue_panel.visible and not main.player.frozen, "space closes the talk")
	main.interact()
	expect(main.dialogue_label.text.contains(main.regions["region.heifeng_ridge"]["residents"][0]["lines"][1]), "next talk says the next line")
	main.advance_dialogue()
	# 進宗門會開始傳功事件：常駐 NPC 先退場，事件結束再回來
	main.travel_to("region.qingyun_sect")
	expect(main.runner != null and main.residents.is_empty(), "residents step aside during an event")
	main.runner.abort("abandon")
	await process_frame
	expect(main.residents.has("lin") and main.residents.has("zhao"), "residents come back after the event")
	main.free()


func test_melee_height() -> void:
	var main: Node = await new_game()
	main.spare_fox()
	for i in 3:
		main.pass_day()
	main.next_time()
	main.next_time()
	for i in 3:
		main.advance_dialogue()
	main.choose_visible(0)
	main.advance_dialogue()
	var hunter: Node2D = main.actor_views["hunter"]
	hunter.position.x = main.player.position.x + 30
	main.player.position.y = main.FLOOR_Y - 100 - 27
	var hp_before: int = main.hp()
	main._process(1.0)
	main.attack()
	expect(main.hp() == hp_before and main.actor_hp["hunter"] == 4, "on a platform out of melee reach both ways")
	main.free()
