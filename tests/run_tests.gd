## Zetas 測試：內容資料一致性 + 兩個內容包在主場景中從觸發到結局跑完一遍。
## 執行：python tools/sync_engine.py && godot --headless --path . -s res://tests/run_tests.gd
extends SceneTree

const TriggerJudge = preload("res://addons/zeworld/trigger_judge.gd")
const AssetLibrary = preload("res://addons/zeworld/asset_library.gd")
const Scenery = preload("res://scripts/scenery.gd")
const InkUI = preload("res://scripts/ink_ui.gd")
const InkGlyph = preload("res://scripts/ink_glyph.gd")

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
	await test_judge_fits()
	await test_cultivation()
	await test_combat()
	await test_art_and_placeholders()
	await test_ink_look()
	await test_event_dressing()
	await test_playlog()
	await test_map_layout_data()
	await test_walk_and_jump()
	await test_scrolling_camera_and_parallax()
	await test_dash()
	await test_battle_camera_zone()
	await test_platforms_and_ropes()
	await test_portals_and_residents()
	await test_melee_height()
	await test_double_jump_and_caches()
	await test_wall_jump()
	await test_glide()
	await test_earth_escape_and_flight()
	await test_audio()
	await test_music_by_map_and_event()
	await test_wild_mobs()
	await test_errand_board()
	await test_keyboard_layout()
	await test_weapons_and_arts()
	await test_wardrobe()
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
	main.audio_settings_path = ""
	main.keys_path = ""
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
	main.damage_actor("hunter", 100)
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
	expect(main.log_lines.has("【築基心魔】"), "the log names the event without the designer summary")
	expect(main.runner != null and main.runner.pack["id"] == "pack.heart_demon_trial.zhuji.s001", "breakthrough triggers heart demon")
	expect(main.state.map_tags == ["illusion"], "illusion map built")
	expect(main.dialogue_panel.visible, "the illusion is described as soon as you arrive")
	main.advance_dialogue()
	expect(not main.dialogue_panel.visible, "then you walk to the square yourself")
	main.player.position.x = main.points["pt.memory_square"]
	main._process(0.016)
	expect(main.runner.reached_points.has("pt.memory_square"), "walking to the square is noticed")
	expect(main.actor_views.has("demon"), "heart demon spawns")
	expect(main.dialogue_name.text.contains("舊日的你") and not main.dialogue_label.text.contains("白蘅"), "without the director the echo is your younger self, not someone you never met")
	for i in 2:
		main.advance_dialogue()
	expect(main.current_choices.size() == 2, "face or fight choice")
	main.choose_visible(0)
	expect(main.state.flags.get("heart_demon_faced") == true, "choice recorded")
	main.advance_dialogue()
	expect(main.actor_hp["demon"] == 160, "the heart demon is a boss: about 8 hits for a fresh 築基")
	var Cultivation = load("res://scripts/cultivation.gd")
	var windup_calm: float = Cultivation.enemy_windup(main.pack_tier()) * main._enemy_speed("demon")
	main.damage_actor("demon", 80)
	expect(main.actor_boss["demon"] == true and main.log_lines.any(func(l): return l.contains("怒了")), "at half hp the boss enrages")
	expect(main._enemy_speed("demon") < 1.0 and Cultivation.enemy_windup(main.pack_tier()) * main._enemy_speed("demon") < windup_calm, "an enraged boss winds up faster")
	main.damage_actor("demon", 80)
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
	main.damage_actor("hunter", 100)
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
	# 存取碼錯了：停用導演，只提示一次，不把 HTTP 錯誤原文丟給玩家
	main = await new_game(true)
	main.director.base_url = "http://127.0.0.1:9"
	main._on_pack_failed({}, "HTTP 401 access code missing or invalid")
	main._on_pack_failed({}, "HTTP 401 access code missing or invalid")
	expect(not main.use_director, "a rejected access code turns the director off")
	expect(main.log_lines.filter(func(l): return l.contains("存取碼")).size() == 1, "the player is told once")
	expect(not main.log_lines.any(func(l): return l.contains("HTTP")), "no raw HTTP errors in the log")
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
	expect(main.points.has("pt.master_seat"), "still in the cave while 師父 is talking")
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
	main.damage_actor("demon", 1000)
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


func test_judge_fits() -> void:
	var main: Node = await new_game()
	var a := generated("fit_a", [])
	var b := generated("fit_b", [])
	for p in [a, b]:
		p["meta"]["region"] = main.state.region
		p["meta"].erase("request_tag")
	b["trigger"]["priority"] = int(a["trigger"].get("priority", 50)) + 5
	main.pool += [a, b]
	expect(TriggerJudge.pick(main.pool, main.state, {}, main.fits)["id"] == b["id"], "without scores priority decides")
	main.director.ranking_ready.emit({a["id"]: 3.5, b["id"]: 1.0})
	main.check_triggers({})
	expect(main.runner != null and main.runner.pack["id"] == a["id"], "the judge's better fit starts first")
	main.free()
	main = await new_game(true)
	main.director.base_url = "http://127.0.0.1:9"
	main.pool += [a, b]
	main._ranked_key = ""
	main.rerank()
	expect(main._ranked_key.contains(a["id"]) and main._ranked_key.contains(b["id"]), "rerank sends today's candidates")
	main.free()


func test_cultivation() -> void:
	var main: Node = await new_game()
	expect(main.hp() == 30 and main.cultivation() == 0, "new 煉氣 disciple: 30 hp, no cultivation")
	expect(not main.try_breakthrough() and main.state.tier_index == 0, "cannot break through without cultivation")
	main.meditate()
	expect(main.cultivation() == 8 and main.state.time_of_day == "午", "meditating in the wild: +8 and one 時辰")
	expect(main.player.sitting > 0.0, "meditating sits the player down for a moment")
	var sx: float = main.player.position.x
	await step(main, {"right": true}, 20)
	expect(main.player.position.x == sx, "cannot walk off while sitting")
	await step(main, {}, 90)
	await step(main, {"right": true}, 10)
	expect(main.player.position.x > sx, "stands up after a moment")
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
	expect(main.actor_hp["hunter"] == 48, "hunter takes about 5 hits at 煉氣 (power 1.2)")
	var hunter: Node2D = main.actor_views["hunter"]
	hunter.position.x = main.player.position.x + 30
	main.attack()
	main.attack()
	expect(main.actor_hp["hunter"] == 36, "attack has a cooldown (one sword cut of 12: 10 × 1.15 for 青雲劍訣 with its own sword)")
	main.player_invuln = 0.0
	hunter.position.x = main.player.position.x + 30  # 擊退過了，拉回眼前
	main._process(0.1)
	expect(main.enemy_windup.has("hunter") and hunter.winding, "hunter in reach winds up first (red omen)")
	expect(main.hp() == 30, "no damage during the wind-up")
	main._process(0.5)
	expect(main.hp() == 30 - 5, "hunter in reach hits for 5 after the wind-up")
	expect(main.player_invuln > 0.0, "getting hit gives a moment of invulnerability")
	expect(main.player.velocity.x < 0.0 and main.player.velocity.y < 0.0, "getting hit knocks the player away from the enemy")
	expect(main.enemy_cooldown["hunter"] > 0.0 and not main.enemy_windup.has("hunter"), "hunter recovers after striking")
	# 看到紅字往後閃就躲得掉
	main._process(1.0)
	main._process(0.1)
	expect(main.enemy_windup.has("hunter"), "hunter winds up again")
	main.player.position.x = hunter.position.x - 120
	var hp_dodge: int = main.hp()
	main._process(0.5)
	expect(main.hp() == hp_dodge, "stepping back during the wind-up dodges the strike")
	main.player.position.x = hunter.position.x - 30
	# 打斷：前搖時被砍中就收招
	main._process(1.0)
	main._process(0.1)
	main.attack_cooldown = 0.0
	var hx: float = hunter.position.x
	main.attack()
	expect(not main.enemy_windup.has("hunter") and not hunter.winding, "hitting a winding-up enemy interrupts it")
	expect(hunter.position.x - hx >= 28.0, "hit knocks the enemy back about 30")
	expect(Engine.time_scale < 1.0, "hit-stop freezes the game for a moment")
	await create_timer(0.2, true, false, true).timeout
	expect(Engine.time_scale == 1.0, "hit-stop ends")
	for i in 40:
		main.player.position.x = hunter.position.x - 30
		main._process(0.5)
		if main.runner == null:
			break
	expect(main.runner == null and main.state.flags.get("baiheng_captured") == true, "falling in battle settles the event as fail")
	expect(main.hp() == 15, "wake up with half hp")
	expect(main.points.has("pt.home_start"), "carried back to the home map")
	main.free()


## 水墨介面與畫面：區塊接縫有霧、地面依區塊染色、出劍有墨痕、敵人被打會閃、倒下淡出才移除。
func test_ink_look() -> void:
	var main: Node = await new_game()
	expect(main.level.get_children().any(func(n): return n is StaticBody2D and n.get_children().any(func(c): return c is Polygon2D)), "ground is a tinted strip")
	main.state.time_of_day = "夜"
	main._refresh_status()
	await create_timer(1.4).timeout
	expect(main.tint.color.b > main.tint.color.r, "night tints the world blue")
	main._on_actor_spawned({"id": "wolf", "template": "mob.wolf_demon", "name": "狼妖", "disposition": "hostile", "spawn_at": ""})
	var wolf: Node2D = main.actor_views["wolf"]
	expect(wolf.get_children().any(func(n): return n is Sprite2D and n.material is ShaderMaterial), "characters get the paper halo")
	expect(main.player.sprite.material is ShaderMaterial, "player gets the paper halo")
	wolf.position.x = main.player.position.x + 40
	main.actor_hp["wolf"] = 1
	main.attack()
	expect(main.get_children().any(func(n): return n.get_script() == main.InkFx and n.kind == 0), "attack draws an ink slash")
	expect(not main.actor_views.has("wolf") and is_instance_valid(wolf), "defeated enemy fades out before it is removed")
	await create_timer(0.8).timeout
	expect(not is_instance_valid(wolf), "faded enemy is freed")
	main.queue_free()
	await process_frame


## 參考研究 A2–A6：斬字劍氣、事件卷軸與印記、正邪色調、突破染色、垂掛前景。
func test_event_dressing() -> void:
	var main: Node = await new_game()
	expect(main.event_seal({"meta": {"request_tag": "heart_demon"}}) == "心魔", "heart demon pack gets the 心魔 seal")
	expect(main.event_seal({"meta": {"request_tag": "encounter"}}) == "奇遇", "daily encounter gets the 奇遇 seal")
	expect(main.event_seal({"meta": {"author": "director"}}) == "機緣", "director pack gets the 機緣 seal")
	expect(main.event_seal({"meta": {}}) == "事件", "hand-written pack gets the 事件 seal")
	# 出劍寫「斬」，命中散開
	var glyph: Node2D = main.player.play_attack()
	expect(glyph != null and glyph.get_script() == InkGlyph, "attack writes the 斬 glyph")
	glyph.shatter()
	expect(glyph.hit, "a hit marks the glyph to scatter")
	# 垂掛前景：森林有，心魔幻境沒有
	expect(main.level.has_node("Hanging") and main.level.has_node("Haze"), "forest map has hanging branches and far haze")
	expect(Scenery.hanging_kind(["illusion"]) == "" and Scenery.hanging_kind(["den", "forest"]) == "", "no hanging occluders in fight maps")
	expect(Scenery.hanging_kind(["cave"]) == "stalactite" and Scenery.hanging_kind(["sect"]) == "pillar", "cave and sect get their own occluders")
	# 正邪色調
	expect(InkUI.karma_tint(1.0).b > InkUI.karma_tint(1.0).r and InkUI.karma_tint(-1.0).r > InkUI.karma_tint(-1.0).b, "righteous tints cool, wicked tints warm")
	main.state.karma["正邪"] = -60
	main._refresh_status()
	await create_timer(1.4).timeout
	expect(main.tint.color.r > main.tint.color.b, "a wicked player sees a warmer world")
	# 事件開場的卷軸、事件 NPC 頭上的印
	main.spare_fox()
	for i in 3:
		main.pass_day()
	main.next_time()
	main.next_time()
	expect(main.hud_layer.has_node("ScrollCard"), "event opens with a scroll title card")
	expect(main.actor_views["fox"].get_children().any(func(n): return n.is_in_group("event_mark")), "event NPC wears a seal mark")
	expect(not main.actor_views.has("hunter") and main._speaker_texture("hunter") != null, "a speaker not yet on screen still gets a portrait")
	main.runner.abort("abandon")
	main.advance_dialogue()
	main.breakthrough()
	expect(main.fx_layer.has_node("BreakthroughWash"), "breakthrough washes the screen with colour")
	main.queue_free()
	await process_frame


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
	expect(lib.missing().is_empty(), "every asset in assets.json has a picture: %s" % [lib.missing()])
	main.free()
	# 正式素材：平台、繩梯、地面用貼圖，玩家換上立繪
	var game: Node = await new_game()
	var plats: Array = game.level.get_children().filter(func(n): return n.is_in_group("platform"))
	expect(not plats.is_empty() and plats.all(func(p): return p.has_node("InkLedge")), "platforms are drawn as ink brush ledges")
	var ropes: Array = game.level.get_children().filter(func(n): return n.is_in_group("rope"))
	expect(not ropes.is_empty() and ropes.all(func(r): return r.get_child(0) is TextureRect), "ropes and vines use textures")
	expect(game.player.sprite != null and not game.player.get_node("Body").visible, "player wears the disciple sprite")
	game.player.facing = -1
	await process_frame
	expect(game.player.sprite.flip_h, "player sprite turns with facing")
	game.free()
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
	var loot_tables: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/loot.json"))
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
		# 沒有繩子通上去的平台，要能從地面或別的平台跳上去；要身法的平台不算墊腳石
		var basic: Array = c.get("platforms", []).filter(func(q): return q.get("skill", "") == "")
		for p in basic:
			if c.get("ropes", []).any(func(r): return r["top"] == p["h"] and r["x"] >= p["x"] and r["x"] <= p["x"] + p["w"]):
				continue
			var from_below: bool = p["h"] < jump_height - 10 or basic.any(func(q): return q != p and p["h"] - q["h"] > 0 and p["h"] - q["h"] < jump_height - 10)
			expect(from_below, "%s: platform at h %d is reachable" % [id, p["h"]])
		# 要身法的平台：一般跳躍上不去（附近 200 像素內沒有夠高的立足點）；二段跳的要跳得上去
		var double_height: float = jump_height + 600.0 * 600.0 / (2.0 * 1800.0)
		for p in c.get("platforms", []).filter(func(q): return q.get("skill", "") != ""):
			expect(p["skill"] in ["double_jump", "wall_jump", "glide", "earth_escape", "sword_flight"], "%s: skill %s is a movement skill" % [id, p["skill"]])
			var too_easy: bool = p["h"] < jump_height + 30 or basic.any(func(q): return h_gap(p, q) < 200 and p["h"] - q["h"] < jump_height + 30)
			expect(not too_easy, "%s: %s platform at h %d is out of reach of a plain jump" % [id, p["skill"], p["h"]])
		for p in c.get("platforms", []).filter(func(q): return q.get("skill", "") == "double_jump"):
			var reachable: bool = p["h"] < double_height - 10 or basic.any(func(q): return h_gap(p, q) == 0 and p["h"] - q["h"] > 0 and p["h"] - q["h"] < double_height - 10)
			expect(reachable, "%s: double-jump platform at h %d is reachable with it" % [id, p["h"]])
		for cache in c.get("caches", []):
			var on_it: bool = cache["h"] == 0 or c["platforms"].any(func(q): return q["h"] == cache["h"] and cache["x"] >= q["x"] and cache["x"] <= q["x"] + q["w"])
			expect(on_it, "%s: %s sits on a platform" % [id, cache["id"]])
			expect(loot_tables.has(cache["loot"]), "%s: %s loot table exists" % [id, cache["id"]])
		if c.has("camera"):
			var cz: Dictionary = c["camera"]
			expect(cz.get("x0", 0) >= 0 and cz.get("x1", c["width"]) <= c["width"] and cz.get("x0", 0) < cz.get("x1", c["width"]), "%s: camera zone inside the chunk" % id)
			expect(cz.get("zoom", 0.9) >= 0.8 and cz.get("zoom", 0.9) <= 1.0, "%s: camera zoom 0.8–1.0" % id)
		for w in c.get("walls", []):
			expect(w["x"] >= 0 and w["x"] + w["w"] <= c["width"] and w["top"] > w.get("bottom", 0), "%s: wall inside the chunk" % id)
			expect(w.get("kind", "cliff") in ["cliff", "thin"], "%s: wall kind" % id)
			# 石壁不能擋住地面上的路（底下要留人走過的高度）
			expect(w.get("kind", "cliff") == "thin" or w.get("bottom", 0) >= 60, "%s: cliff leaves the ground path open" % id)
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


## 兩個平台水平方向的距離，重疊為 0
func h_gap(p: Dictionary, q: Dictionary) -> float:
	return maxf(0.0, maxf(p["x"], q["x"]) - minf(p["x"] + p["w"], q["x"] + q["w"]))


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


## 橫向卷軸：鏡頭往前看、小跳不跟高度、按住 ↓ 往下看；背景畫比地面慢；山嵐與近景層。
func test_scrolling_camera_and_parallax() -> void:
	var main: Node = await new_game()
	var player: CharacterBody2D = main.player
	var cam: Camera2D = player.camera
	player.position = Vector2(900, main.FLOOR_Y - 27)
	player.snap_camera()
	await step(main, {}, 20)
	await step(main, {"right": true}, 90)
	expect(cam.global_position.x > player.position.x + 60.0, "camera looks ahead in the walking direction")
	await step(main, {"left": true}, 120)
	expect(cam.global_position.x < player.position.x - 60.0, "turning around swings the look-ahead")
	# 高 300 的平台底下，跳不上去
	player.position = Vector2(1700, main.FLOOR_Y - 27)
	player.snap_camera()
	await step(main, {}, 30)
	var cam_y := cam.global_position.y
	main.player.test_input = {"jump": true}
	var drift := 0.0
	for i in 40:
		await physics_frame
		drift = maxf(drift, absf(cam.global_position.y - cam_y))
	main.player.test_input = {}
	expect(drift < 4.0, "a plain jump does not bob the camera (%.1f)" % drift)
	await step(main, {}, 20)
	cam_y = cam.global_position.y
	await step(main, {"down": true}, 60)
	expect(cam.global_position.y > cam_y + 60.0, "holding down looks down")
	await step(main, {}, 60)
	expect(absf(cam.global_position.y - cam_y) < 10.0, "letting go looks back")
	# 背景畫：鏡頭走 100，畫的下半跟著走 DEPTH × 100（螢幕上走 100 - 那麼多），越上面跟得越多、螢幕上走得越少；框固定蓋住區塊
	var painting: TextureRect = main.level.get_children().filter(func(n): return n is TextureRect and n.has_method("setup"))[0]
	var x0: float = painting.position.x
	painting._apply(painting.win_left + painting.win_width / 2 + 100.0)
	expect(is_equal_approx(painting.shift_at(1.0), 100.0 * painting.DEPTH), "chunk painting scrolls slower than the ground")
	expect(painting.shift_at(0.0) > painting.shift_at(0.5) and painting.shift_at(0.5) > painting.shift_at(1.0), "the top of the painting moves least on screen")
	painting._apply(-10000.0)
	expect(absf(painting.shift_at(1.0)) <= painting.extra, "painting never slides past its spare edge")
	expect(painting.position.x == x0 and painting.position.x <= painting.win_left and painting.position.x + painting.size.x >= painting.win_left + painting.win_width, "painting always covers its chunk")
	expect(main.level.has_node("Sky") and main.level.has_node("Ranges_far") and main.level.has_node("Ranges_mid"), "outdoor maps have sky and far ranges behind the painting")
	# 多層背景：每層各自一張圖，由遠到近捲得越來越快，古畫只是其中一層
	var speeds: Array = ["Ranges_far", "Ranges_mid", "Hills", "Flow", "Near"].map(func(n): return main.level.get_node(n).scroll_scale.x if main.level.has_node(n) else -1.0)
	speeds.append(1.0 - painting.DEPTH_FAR)
	speeds.append(1.0)
	var ordered_speeds := true
	for i in speeds.size() - 1:
		ordered_speeds = ordered_speeds and speeds[i] > 0.0 and speeds[i] < speeds[i + 1]
	expect(ordered_speeds, "background layers scroll faster the nearer they are %s" % [speeds])
	expect(main.level.get_node("Near").z_index < painting.z_index and main.level.get_node("Hills").z_index < painting.z_index, "the chunk's own buildings and banks sit in front of every backdrop layer")
	expect(main.level.has_node("Mist") and main.level.has_node("Foreground"), "map has mist and foreground layers")
	expect(main.level.get_node("Foreground").z_index > 0 and main.level.get_node("Mist").z_index < 0, "foreground in front of the player, mist behind")
	# 天頂擋住御劍，不會飛出畫面
	player.position = Vector2(1700, main.FLOOR_Y - main.CEILING_HEIGHT + 60)
	player.velocity = Vector2(0, -900)
	await step(main, {}, 6)
	expect(player.position.y - player.SIZE.y / 2 >= main.FLOOR_Y - main.CEILING_HEIGHT - 1.0, "the sky ceiling stops the player (%d)" % int(player.position.y))
	await step(main, {}, 120)
	# 受傷鏡頭震一下
	main.damage_player(1)
	expect(player._shake > 0.0, "getting hit shakes the camera")
	main.free()


## 墨影步：閃 120 左右、期間無敵、有冷卻、空中只能一次。
func test_dash() -> void:
	var main: Node = await new_game()
	var player: CharacterBody2D = main.player
	player.position = Vector2(1700, main.FLOOR_Y - 27)
	await step(main, {}, 10)
	var x0: float = player.position.x
	main.player.test_input = {"dash": true}
	await physics_frame
	await physics_frame
	expect(player.dashing > 0.0, "shift/X starts the ink step")
	await step(main, {"dash": true}, 12)
	expect(absf(player.position.x - x0 - player.DASH_DISTANCE) < 12.0, "ink step covers about 120 (%d)" % int(player.position.x - x0))
	expect(player.dashing == 0.0 and player._dash_cooldown > 0.0, "ink step ends and cools down")
	await step(main, {}, 2)
	var x1: float = player.position.x
	await step(main, {"dash": true}, 4)
	expect(absf(player.position.x - x1) < 10.0, "no second ink step during the cooldown")
	await step(main, {}, 40)
	# 空中一次
	await step(main, {"jump": true}, 4)
	await step(main, {"dash": true}, 12)
	await step(main, {}, 1)
	var x2: float = player.position.x
	await step(main, {"dash": true}, 12)
	expect(absf(player.position.x - x2) < 10.0, "only one ink step per jump")
	await step(main, {}, 60)
	# 期間無敵
	main._on_actor_spawned({"id": "wolf", "template": "mob.wolf_demon", "name": "狼妖", "disposition": "hostile", "spawn_at": ""})
	var wolf: Node2D = main.actor_views["wolf"]
	wolf.position.x = player.position.x + 30
	main.enemy_windup["wolf"] = 0.01
	player.dashing = 0.1
	var hp: int = main.hp()
	main._process(0.05)
	expect(main.hp() == hp, "ink step dodges a strike")
	main.free()


## 戰場鏡頭：狼妖巢穴有敵人時鏡頭鎖住、拉遠；敵人沒了就放開。
func test_battle_camera_zone() -> void:
	var main: Node = await new_game()
	main.build_map([{"chunk": "chunk.heifeng_pass", "order": 0}, {"chunk": "chunk.demon_den", "order": 1}], "pt.den_mouth")
	var player: CharacterBody2D = main.player
	expect(main.camera_zones.size() == 1, "demon den has a battle camera")
	await step(main, {}, 10)
	expect(player.camera_zone.is_empty(), "no lock without enemies")
	main._on_actor_spawned({"id": "wolf", "template": "mob.wolf_demon", "name": "狼妖", "disposition": "hostile", "spawn_at": "pt.den_heart"})
	await step(main, {}, 60)
	var zone: Dictionary = main.camera_zones[0]
	expect(not player.camera_zone.is_empty() and player.camera.zoom.x < 0.95, "enemy in the den locks and widens the camera")
	expect(absf(player.camera.get_screen_center_position().x - clampf(player.camera.get_screen_center_position().x, zone["x0"], zone["x1"])) < 1.0, "camera centers inside the battle zone")
	main._remove_actor_view("wolf")
	await step(main, {}, 60)
	expect(player.camera.zoom.x == 1.0, "camera lets go after the fight")
	main.free()


func test_platforms_and_ropes() -> void:
	var main: Node = await new_game()
	var player: CharacterBody2D = main.player
	var road: Dictionary = main.chunks["chunk.qingyun_road"]
	var home: Array = main.regions["region.qingyun_foothills"]["home"]
	expect(home.size() >= 4, "the foothills home map strings several chunks together")
	var plats := 0
	var rope_count := 0
	for c in home:
		plats += main.chunks[c].get("platforms", []).size()
		rope_count += main.chunks[c].get("ropes", []).size()
	expect(main.level.get_children().filter(func(n): return n.is_in_group("platform")).size() == plats, "home map builds its platforms")
	expect(player.ropes.size() == rope_count, "player knows the ropes")
	expect(player.camera.limit_left == -int(main.EDGE_MARGIN) and player.camera.limit_right == int(main.map_width + main.EDGE_MARGIN), "camera stays near the map, with a little misty margin at the ends")
	# 跳上第一層平台（x 260~440，高 100）
	player.position = Vector2(350, main.FLOOR_Y - 40)
	await step(main, {}, 10)
	await step(main, {"jump": true}, 45)
	expect(player.on_platform() and absf(player.feet() - (main.FLOOR_Y - 100)) < 2.0, "jump up through a one-way platform and stand on it")
	await step(main, {}, 2)  # 先放開跳鍵，下一次按才算
	await step(main, {"down": true, "jump": true}, 40)
	expect(player.is_on_floor() and not player.on_platform(), "down + jump drops through the platform")
	# 藤蔓 x 640，從地面爬到高 200 的平台
	player.position = Vector2(664, main.FLOOR_Y - 40)  # 站在藤旁 24px 也抓得到
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
	main.build_map([{"chunk": "chunk.heifeng_pass", "order": 0}, {"chunk": "chunk.demon_den", "order": 1}], "pt.pass_start")
	main._process(0.016)
	var outside: Color = main.ambience.color
	main.player.position.x = main.chunk_x["chunk.demon_den"] + 100.0
	main._process(0.016)
	expect(main.ambience.color != outside, "walking into the den switches the ambient particles")
	main.player.position.x = main.chunk_x["chunk.heifeng_pass"] + 100.0
	main._process(0.016)
	expect(main.ambience.color == outside, "and back outside switches them back")
	main.free()


func test_portals_and_residents() -> void:
	var main: Node = await new_game()
	expect(main.portals.size() == 2, "foothills has portals at both ends")
	var right: Dictionary = main.portals.filter(func(p): return p["to"] == "region.heifeng_ridge")[0]
	main.player.position = Vector2(right["x"], main.FLOOR_Y - 27)
	main._process(0.016)
	expect(main.prompt_label.visible and main.prompt_label.text.contains("黑風嶺"), "standing on a portal shows where it goes")
	expect(main.prompt_label.text.contains("需築基") and not main.prompt_label.text.begins_with("↑"), "a locked portal says which realm it needs")
	var head: Vector2 = main.player.get_viewport().get_canvas_transform() * main.player.global_position
	expect(absf(main.prompt_label.position.x + main.prompt_label.size.x / 2 - head.x) < 2.0 and main.prompt_label.position.y < head.y, "prompt floats above the player")
	expect(main.interact() and main.state.region == "region.qingyun_foothills", "煉氣 is turned back at the 黑風嶺 portal")
	main.state.tier_index = 1
	main._process(0.016)
	expect(main.prompt_label.text.begins_with("↑/E 前往"), "an open portal shows the up-arrow prompt")
	expect(main.interact() and main.state.region == "region.heifeng_ridge", "築基 walks through the portal")
	var back: Dictionary = main.portals.filter(func(p): return p["to"] == "region.qingyun_foothills")[0]
	expect(absf(main.player.position.x - back["x"]) <= main.PORTAL_INSET + 1.0, "arrive at the 黑風嶺 end that leads back")
	expect(main.residents.has("mo"), "黑風嶺 has its resident")
	var mo: Node2D = main.residents["mo"]["view"]
	main.player.position = Vector2(mo.position.x + 20, main.FLOOR_Y - 27)
	main._process(0.016)
	expect(main.prompt_label.text.contains("交談"), "standing next to an NPC shows the talk prompt")
	expect(main.interact() and main.dialogue_panel.visible and main.dialogue_name.text.contains("莫老三"), "talk to the resident")
	expect(main.player.frozen, "player stands still while talking")
	expect(main.portrait_frame.visible and main.portrait.texture is AtlasTexture, "talking shows the speaker's portrait cropped from the sprite")
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
	expect(main.hp() == hp_before and main.actor_hp["hunter"] == 48, "on a platform out of melee reach both ways")
	main.free()


func test_double_jump_and_caches() -> void:
	var path := "user://zetas_test_double_jump.json"
	var main: Node = await new_game(false, path)
	var player: CharacterBody2D = main.player
	expect(not player.double_jump, "煉氣 starts without 輕身術")
	# 樹梢藥匣在高 390 的平台上，底下是高 200 的平台（x 480~680）
	player.position = Vector2(580, main.FLOOR_Y - 200 - 27)
	await step(main, {}, 10)
	expect(player.on_platform(), "stand on the 200 platform under the pine")
	await step(main, {"jump": true}, 4)
	await step(main, {}, 2)
	await step(main, {"jump": true}, 60)
	expect(absf(player.feet() - (main.FLOOR_Y - 200)) < 2.0, "without 輕身術 a second press does nothing")
	main.gain_cultivation(100)
	expect(player.double_jump and main.state.game_data["movement"].has("double_jump"), "full cultivation at 煉氣 teaches 輕身術")
	expect(main.log_lines.any(func(l): return l.contains("輕身術")), "the log says so")
	await step(main, {}, 2)
	await step(main, {"jump": true}, 12)
	await step(main, {}, 2)
	await step(main, {"jump": true}, 60)
	await step(main, {}, 10)
	expect(player.on_platform() and absf(player.feet() - (main.FLOOR_Y - 390)) < 2.0, "double jump reaches the 390 ledge")
	main._process(0.016)
	expect(main.prompt_label.text.contains("拿取"), "standing by the cache shows the prompt")
	var bag: int = main.state.items.size()
	expect(main.interact() and main.state.items.size() > bag, "open the cache")
	expect(main.state.game_data["found"].has("cache.road_pine") and not main.caches.has("cache.road_pine"), "cache is taken")
	main.free()
	var again: Node = await new_game(false, path)
	expect(again.player.double_jump, "輕身術 restored from save")
	expect(not again.caches.has("cache.road_pine"), "a taken cache stays taken")
	again.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 不跑事件，直接把落腳地圖換到某個地區，並給境界與修為
func at_region(main: Node, region: String, tier: int, exp := 0) -> void:
	main.state.region = region
	main.state.tier_index = tier
	main.state.game_data["exp"] = exp
	main.update_movement_skills()
	main.go_home()
	await step(main, {}, 10)


func test_wall_jump() -> void:
	var main: Node = await new_game()
	var player: CharacterBody2D = main.player
	await at_region(main, "region.qingyun_sect", 0)
	expect(not player.wall_jump, "煉氣 does not know 踏葉")
	expect(main.level.get_children().filter(func(n): return n.is_in_group("wall")).size() == 2, "山門 has two cliffs")
	await at_region(main, "region.qingyun_sect", 1)
	expect(player.wall_jump and main.log_lines.any(func(l): return l.contains("踏葉")), "築基 learns 踏葉")
	var gate: float = main.chunk_x["chunk.sect_gate"]
	player.position = Vector2(gate + 183, main.FLOOR_Y - 27)
	await step(main, {}, 5)
	var toward := 1
	var pressed := true
	main.player.test_input = {"jump": true, "right": true}
	await physics_frame
	for i in 300:
		var inp := {"right": toward == 1, "left": toward == -1}
		if player.feet() < main.FLOOR_Y - 400:
			inp = {}
		elif player.is_on_wall_only() and not pressed and int(-signf(player.get_wall_normal().x)) == toward:
			inp["jump"] = true
			toward = -toward
		pressed = inp.get("jump", false)
		player.test_input = inp
		await physics_frame
		if player.on_platform():
			break
	await step(main, {}, 10)
	expect(player.on_platform() and absf(player.feet() - (main.FLOOR_Y - 410)) < 2.0, "踏葉 climbs between the cliffs to the 410 ledge")
	main.free()


func glide_run(main: Node, target_x: float) -> void:
	var player: CharacterBody2D = main.player
	await step(main, {}, 2)
	for i in 240:
		# 滑到目標上空就放開，直接落下
		var going: bool = player.position.x > target_x
		player.test_input = {"left": going, "jump": going}
		await physics_frame
		if player.is_on_floor() and i > 5:
			break
	await step(main, {}, 10)


func test_glide() -> void:
	var main: Node = await new_game()
	var player: CharacterBody2D = main.player
	await at_region(main, "region.heifeng_ridge", 1, 100)
	expect(not player.glide, "early 築基 does not know 御風")
	var ravine: float = main.chunk_x["chunk.heifeng_ravine"]
	player.position = Vector2(ravine + 600, main.FLOOR_Y - 480 - 27)
	await step(main, {}, 10)
	expect(player.on_platform(), "stand on the high rock in 斷魂谷")
	await glide_run(main, ravine + 80)
	expect(not (player.on_platform() and absf(player.feet() - (main.FLOOR_Y - 340)) < 2.0), "without 御風 the cliff cave is out of reach")
	await at_region(main, "region.heifeng_ridge", 1, 200)
	expect(player.glide, "築基 halfway learns 御風")
	player.position = Vector2(ravine + 600, main.FLOOR_Y - 480 - 27)
	await step(main, {}, 10)
	await glide_run(main, ravine + 80)
	expect(player.on_platform() and absf(player.feet() - (main.FLOOR_Y - 340)) < 2.0, "御風 glides across to the cliff cave")
	var Cultivation = load("res://scripts/cultivation.gd")
	expect(Cultivation.knows_movement("glide", 0, 0, {"movement.glide": true}), "an event flag can teach 御風")
	main.free()


func test_earth_escape_and_flight() -> void:
	var main: Node = await new_game()
	var player: CharacterBody2D = main.player
	await at_region(main, "region.heifeng_ridge", 1)
	var ravine: float = main.chunk_x["chunk.heifeng_ravine"]
	expect(main.caches.has("cache.ravine_hidden_room"), "hidden room behind the thin wall at the end of the map")
	player.position = Vector2(ravine + 990, main.FLOOR_Y - 27)
	await step(main, {"right": true}, 40)
	expect(player.position.x < ravine + 1030, "the thin wall blocks before 土遁")
	await at_region(main, "region.heifeng_ridge", 2)
	expect(player.earth_escape, "金丹 learns 土遁")
	player.position = Vector2(ravine + 990, main.FLOOR_Y - 27)
	await step(main, {"right": true}, 40)
	await step(main, {}, 10)
	expect(player.position.x > ravine + 1050, "土遁 walks through the thin wall")
	expect(main.interact() and main.state.game_data["found"].has("cache.ravine_hidden_room"), "take the hidden room cache")
	# 薄牆只在地圖盡頭；放在中間就不蓋，免得擋住事件的路
	main.build_map([{"chunk": "chunk.heifeng_ravine", "order": 0}, {"chunk": "chunk.demon_den", "order": 1}], "pt.ravine_edge")
	expect(main.level.get_children().filter(func(n): return n.is_in_group("wall")).is_empty(), "no thin wall when the chunk is not the last")
	main.go_home()
	await step(main, {}, 10)
	expect(not player.sword_flight, "金丹 cannot fly yet")
	await at_region(main, "region.heifeng_ridge", 3)
	expect(player.sword_flight, "元嬰 learns 御劍")
	var ground: float = player.feet()
	await step(main, {"jump": true}, 10)
	await step(main, {"fly": true, "up": true}, 2)
	await step(main, {"up": true}, 40)
	expect(player.flying > 0.0 and ground - player.feet() > 250.0, "御劍 flies far above a jump")
	await step(main, {"right": true}, 60)
	expect(player.flying == 0.0, "flight runs out")
	await step(main, {"fly": true}, 2)
	expect(player.flying == 0.0, "only one flight before landing again")
	await step(main, {}, 120)
	expect(player.is_on_floor(), "falls back down")
	main.free()


## 配樂與音效：清單裡的檔案都在、每個地區都有三層曲子與短樂句、心魔幻境換曲並用所在地區的旋律、
## 走動才有旋律、危險才有鼓、對話時壓低、動作會出聲、N 可關配樂。
func test_audio() -> void:
	var main: Node = await new_game()
	var audio: Node = main.audio
	for key in audio.music:
		var entry: Dictionary = audio.music[key]
		expect(float(entry.get("bpm", 0)) > 0.0, "%s has a tempo for stingers" % key)
		if entry.has("file"):
			expect(ResourceLoader.exists(entry["file"]), "%s track exists" % key)
			continue
		for layer in ["base", "melody", "rhythm"]:
			var f: String = audio.layer_file(key, layer, "region.qingyun_sect")
			expect(ResourceLoader.exists(f), "%s %s layer exists (%s)" % [key, layer, f])
		for st in ["event_start", "event_end", "breakthrough", "motif"]:
			expect(ResourceLoader.exists(entry["stingers"][st]), "%s stinger %s exists" % [key, st])
	for st in audio.stingers:
		expect(ResourceLoader.exists(audio.stingers[st]), "shared stinger %s exists" % st)
	for name in audio.sfx:
		for f in audio.sfx[name]["files"]:
			expect(ResourceLoader.exists(f), "sfx file %s exists" % f)
	for region in main.regions:
		if region.begins_with("region."):
			expect(audio.music_key(region, []) == region, "%s has music" % region)
			expect(audio.layer_file("tag.illusion", "melody", region).contains(region.trim_prefix("region.")),
				"heart demon melody mirrors %s's motif" % region)
	expect(audio.music_key("region.qingyun_sect", ["illusion"]) == "tag.illusion", "illusion maps use the heart demon music")
	expect(audio.current_music == main.state.region, "the home region's music plays on start")
	await step(main, {}, 20)
	expect(audio.layer_target["base"] == 1.0 and audio.layer_target["rhythm"] == 0.0, "calm: only the base layer and no drums")
	audio.played.clear()
	await step(main, {"right": true, "jump": true}, 6)
	expect(audio.played.has("jump"), "jumping makes a sound")
	expect(audio.layer_target["melody"] == 1.0, "walking brings in the melody")
	await step(main, {}, 30)
	main.attack()
	expect(audio.played.has("attack"), "attacking makes a sound")
	audio.set_mood(false, true, true, 1.0)
	expect(audio.layer_target["rhythm"] == 1.0, "danger brings in the drums")
	expect(audio.duck_db < 0.0, "dialogue ducks the music")
	audio.set_mood(false, false, false, audio.IDLE_SECONDS + 1.0)
	expect(audio.layer_target["melody"] == 0.0 and audio.layer_target["rhythm"] == 0.0, "standing still lets the melody rest")
	for name in ["jump", "double_jump", "wall_jump", "flight", "land", "attack", "hit", "hurt", "defeat",
			"event_start", "event_end", "reward", "breakthrough", "meditate", "travel", "ui_tick"]:
		expect(audio.sfx.has(name), "sfx %s is listed" % name)
	audio.played.clear()
	expect(main.travel_to("region.qingyun_sect"), "travel to the sect")
	expect(audio.played.has("motif:region.qingyun_sect"), "travelling plays the destination's motif")
	expect(audio.current_music == main.music_choice() and audio.current_region == "region.qingyun_sect", "and switches the music (%s)" % audio.current_music)
	audio.played.clear()
	main.breakthrough()
	expect(audio.played.has("stinger:breakthrough"), "breakthrough plays the regional stinger")
	var piece: String = audio.current_music
	expect(not audio.toggle_music() and not audio.music_on, "N turns the music off")
	expect(audio.toggle_music() and audio.current_music == piece, "and back on with the same piece (%s)" % piece)
	main.free()


## 野怪：依時辰出現、打倒給修為與掉落、當天不再出現、隔天重生；事件開始時退場；被打倒醒在落腳點。
func test_wild_mobs() -> void:
	var main: Node = await new_game()
	main.wild_drop_chance = 1.0
	await at_region(main, "region.qingyun_sect", 0)
	expect(main.wild.is_empty(), "no wild mobs inside the sect")
	main.state.time_of_day = "晨"
	await at_region(main, "region.qingyun_foothills", 0)
	var monkeys: Array = main.wild.keys().filter(func(id): return main.wild[id]["template"] == "mob.shengsheng")
	expect(monkeys.size() == 2, "two 狌狌 roam the woods in the morning")
	expect(main.wild.keys().all(func(id): return main.wild[id]["template"] != "mob.wandering_ghost"), "no ghosts by day")
	var first_end: float = main.chunk_x["chunk.qingyun_woods"]
	expect(main.wild.keys().all(func(id): return main.actor_views[id].position.x >= first_end), "no mobs in the first chunk where the player arrives")
	for id in main.wild:
		expect(main.actor_views[id].get_meta("hostile"), "wild mobs are hostile")
	# 時辰到夜：狌狌回巢、遊魂出來
	main.state.time_of_day = "暮"
	main.next_time()
	expect(main.state.time_of_day == "夜", "night falls")
	expect(main.wild.keys().all(func(id): return main.wild[id]["template"] != "mob.shengsheng"), "狌狌 are gone at night")
	var ghosts: Array = main.wild.keys().filter(func(id): return main.wild[id]["template"] == "mob.wandering_ghost")
	expect(ghosts.size() == 2, "ghosts haunt the shrine at night")
	# 野怪也會出招
	var g: String = ghosts[0]
	var gv: Node2D = main.actor_views[g]
	main.player.position = Vector2(gv.position.x - 30, main.FLOOR_Y - 40)
	await step(main, {}, 5)
	main.player.position.x = gv.position.x - 30
	main.player_invuln = 0.0
	main._process(0.1)
	expect(main.enemy_windup.has(g), "wild mobs wind up and strike even with no event running")
	# 打倒：修為、掉落、當天不再出現
	var exp_before: int = main.cultivation()
	var hits := 0
	while main.wild.has(g) and hits < 20:
		main.attack_cooldown = 0.0
		main.actor_views[g].position.x = main.player.position.x + 30
		main.attack()
		hits += 1
	expect(hits == 3, "a 煉氣 ghost (power 0.8) takes 3 sword hits (the third of the combo is heavier)")
	expect(main.cultivation() - exp_before == 4, "killing a wild mob gives a little cultivation (about half a meditation)")
	expect(main.state.items.has("陰魂殘絲"), "wild mobs drop common loot")
	expect(g in main.wild_defeated(), "the defeat is remembered")
	main.go_home()
	expect(not main.wild.has(g) and main.wild.size() == 1, "a defeated mob stays gone for the day")
	main.pass_day()
	expect(main.wild_defeated().is_empty() and main.wild.has(g), "mobs respawn the next day")
	expect(int(main.state.kills.get("mob.wandering_ghost", 0)) == 1, "wild kills are recorded in the engine by template")
	# 黑風嶺：強度跟著地區門檻（築基），夜裡狼妖加倍
	main.state.time_of_day = "夜"
	await at_region(main, "region.heifeng_ridge", 1)
	var wolves: Array = main.wild.keys().filter(func(id): return main.wild[id]["template"] == "mob.wolf_demon")
	expect(wolves.size() == 4, "the den has twice the wolves at night")
	expect(main.actor_hp[wolves[0]] == 80 and main.enemy_tier(wolves[0]) == 1, "heifeng mobs are as tough as a 築基 event")
	main.state.time_of_day = "晨"
	main.go_home()
	expect(main.wild.keys().filter(func(id): return main.wild[id]["template"] == "mob.wolf_demon").size() == 2, "two wolves by day")
	expect(main.wild.keys().all(func(id): return main.wild[id]["template"] != "mob.gudiao"), "蠱雕 only come out at dusk and night")
	# 被野怪打倒：醒在落腳點，時辰往前
	main.state.tier_index = 0
	main.state.game_data["hp"] = 1
	var w: String = wolves[0]
	var wv: Node2D = main.actor_views[w]
	main.player.position = Vector2(wv.position.x - 30, main.FLOOR_Y - 40)
	main.player_invuln = 0.0
	for i in 20:
		main.player.position.x = wv.position.x - 30
		main._process(0.3)
		if main.hp() != 1:
			break
	expect(main.hp() == main.Cultivation.max_hp(0) / 2, "knocked out by a wild mob, wake with half hp")
	expect(absf(main.player.position.x - main.points["pt.pass_start"]) < 1.0, "wake up at the region's spawn point")
	expect(main.state.time_of_day == "午", "an hour passed")
	# 事件開始時野怪退場，結束後回來
	main.state.region = "region.qingyun_foothills"
	main.state.time_of_day = "晨"
	main.go_home()
	expect(not main.wild.is_empty(), "foothills has mobs in the morning")
	main.spare_fox()
	for i in 3:
		main.pass_day()
	main.next_time()
	main.next_time()
	expect(main.runner != null and main.wild.is_empty(), "wild mobs leave when an event starts")
	main.runner.abort("abandon")
	expect(main.runner == null and not main.wild.is_empty(), "wild mobs come back after the event")
	main.free()


## 宗門差事榜：每天最多 3 件、接了是「打倒 N 隻」的事件（只算接了之後的），進行中照樣能趕路、打野怪，
## 完成給修為與掉落；同一件今天不能再接。導演寫的打怪事件（沒有地圖）也一樣不綁住玩家。
func test_errand_board() -> void:
	var main: Node = await new_game()
	main.wild_drop_chance = 0.0
	main.state.time_of_day = "晨"
	await at_region(main, "region.qingyun_sect", 0)
	expect(main.board_view != null, "the sect plaza has an errand board")
	var list: Array = main.todays_errands()
	expect(list.size() == 3 and list.all(func(e): return int(e["tier_min"]) == 0), "three 煉氣 errands on the board")
	main.player.position.x = main.board_view.position.x
	await step(main, {}, 5)
	expect(main.nearby_board() and main.prompt_label.text == "↑/E 看差事榜", "standing at the board shows a prompt")
	main.state.record_kill("mob.shengsheng")
	main.state.record_kill("mob.shengsheng")
	main.interact()
	expect(main.dialogue_panel.visible and main.errand_options.size() == 3, "↑ opens the board with three errands")
	var pick := -1
	for i in main.errand_options.size():
		if main.errand_options[i]["errand"]["id"] == "monkey_fruit":
			pick = i
	if pick < 0:
		# 今天不在榜上就直接接
		main.close_errand_board()
		main.start_pack(main.errand_pack(main.errands["errands"][0]))
	else:
		main.choose_errand(pick)
	expect(main.runner != null and main.runner.pack["meta"]["request_tag"] == "errand", "choosing an errand starts it")
	expect(not main.dialogue_panel.visible and main.errand_options.is_empty(), "the board closes")
	expect(main.hud_objective.text == "目標：打倒2隻狌狌（0／2）", "kills before accepting do not count")
	expect(not main.blocking(), "an errand does not tie the player down")
	expect(main.travel_to("region.qingyun_foothills", true), "can travel with an errand in hand")
	var monkeys: Array = main.wild.keys().filter(func(id): return main.wild[id]["template"] == "mob.shengsheng")
	expect(monkeys.size() == 2 and main.runner != null, "wild mobs stay out during an errand")
	main.meditate()
	expect(main.runner != null and main.state.time_of_day == "暮", "can meditate during an errand")
	var exp_before: int = main.cultivation()
	for m in monkeys:
		while main.wild.has(m):
			main.attack_cooldown = 0.0
			main.actor_views[m].position.x = main.player.position.x + 30
			main.attack()
		if main.runner != null:
			expect(main.hud_objective.text == "目標：打倒2隻狌狌（1／2）", "objective shows progress")
	expect(main.runner == null, "the errand completes after two kills")
	expect(main.cultivation() - exp_before == 3 + 3 + main.Cultivation.EXP_REWARD["small"], "kills plus the errand reward")
	expect(main.state.items.has("凝氣草"), "the errand gives its loot")
	main.state.region = "region.qingyun_sect"
	main.go_home()
	expect(main.todays_errands().all(func(e): return e["id"] != "monkey_fruit"), "a finished errand is off the board for the day")
	main.pass_day()
	expect(main.todays_errands().size() >= 2, "new errands the next day")
	# 放棄
	if main.runner != null:  # 第二天在宗門會觸發師父的第一課，先略過
		main.runner.abort("abandon")
	main._hide_dialogue()
	var e2: Dictionary = main.todays_errands()[0]
	main.start_pack(main.errand_pack(e2))
	main.player.position.x = main.board_view.position.x
	main.open_errand_board()
	expect(main.errand_options[0]["kind"] == "abandon", "the board offers to drop the current errand")
	main.choose_errand(0)
	expect(main.runner == null and not main.todays_errands().has(e2), "dropping an errand ends it for today")
	# 築基才看得到黑風嶺的差事
	main.state.tier_index = 1
	var all_ok: Array = main.errands["errands"].filter(func(e): return int(e["tier_min"]) <= 1)
	expect(all_ok.size() == 5, "築基 can take the heifeng errands too")
	# 一般事件仍然綁住玩家
	main.state.tier_index = 0
	main.spare_fox()
	main.state.region = "region.qingyun_foothills"
	main.go_home()
	for i in 3:
		main.pass_day()
	main.next_time()
	main.next_time()
	expect(main.runner != null and main.blocking() and main.wild.is_empty(), "a story event still keeps the player in the scene")
	main.free()


func press_key(kc: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = kc
	ev.pressed = true
	return ev


## 兩組預設鍵盤配置（方向鍵＋ZXCV、WASD＋KJLI）不互搶，按鍵提示跟著設定走，可以改鍵。
func test_keyboard_layout() -> void:
	const Keys = preload("res://scripts/keys.gd")
	var main: Node = await new_game()
	var player: CharacterBody2D = main.player
	# 預設：除了「上」和「交談」共用，一個鍵只做一件事
	var owner := {}
	var clash := []
	for a in Keys.ACTIONS:
		for kc in Keys.bindings[a["id"]]:
			if kc == 0:
				continue
			if owner.has(kc) and not Keys._shared(owner[kc], a["id"]):
				clash.append(Keys.key_name(kc))
			owner[kc] = a["id"]
	expect(clash.is_empty(), "default keys never do two things at once %s" % [clash])
	expect(not owner.has(KEY_ALT), "Alt is gone (browsers grab it)")
	for pair in [["jump", [KEY_Z, KEY_K, KEY_SPACE]], ["attack", [KEY_X, KEY_J]], ["dash", [KEY_C, KEY_L, KEY_SHIFT]], ["fly", [KEY_V, KEY_I]]]:
		for kc in pair[1]:
			expect(press_key(kc).is_action_pressed(pair[0]), "%s is on %s" % [Keys.key_name(kc), pair[0]])
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	expect(pad.is_action_pressed("jump"), "gamepad A jumps")
	expect(main.help_label.text.contains("Z/K/空白 跳") and main.help_label.text.contains("X/J 攻擊"), "help bar lists both layouts")
	# 真的從 InputMap 讀：按住「右」會往右走
	player.test_input = null
	var x0: float = player.position.x
	Input.action_press("move_right")
	for i in 20:
		await physics_frame
	Input.action_release("move_right")
	expect(player.position.x > x0 + 20, "holding the right key walks right")
	# X 攻擊
	main.attack_cooldown = 0.0
	main.handle_input(press_key(KEY_X))
	expect(main.attack_cooldown > 0.0, "X attacks")
	main.attack_cooldown = 0.0
	main.handle_input(press_key(KEY_J))
	expect(main.attack_cooldown > 0.0, "J attacks too")
	# 地圖選單：↓ 移游標、Esc 關
	main.handle_input(press_key(KEY_T))
	expect(main.travel_options.size() >= 2 and main.dialogue_label.text.contains("◆ 1."), "the map opens with a cursor on the first place")
	main.handle_input(press_key(KEY_DOWN))
	expect(main.menu_cursor == 1 and main.dialogue_label.text.contains("◆ 2."), "down moves the cursor")
	main.handle_input(press_key(KEY_W))
	expect(main.menu_cursor == 0, "W moves it back up")
	main.handle_input(press_key(KEY_ESCAPE))
	expect(main.travel_options.is_empty() and not main.dialogue_panel.visible, "Esc closes the map")
	# NPC 說話：K（跳）關掉
	var npc: String = main.residents.keys()[0]
	main.talk_to(npc)
	expect(main.dialogue_label.text.contains("Z/空白 繼續"), "dialogue names the real continue keys")
	main.handle_input(press_key(KEY_K))
	expect(not main.dialogue_panel.visible, "the jump key closes the line")
	# 改鍵：把 K 給攻擊，跳就不再用 K
	main.handle_input(press_key(KEY_ESCAPE))
	expect(main.key_panel != null and main.key_panel.visible and player.input_blocked, "Esc opens key settings and the player stops listening")
	main.key_panel._start_capture("attack", 0)
	main.key_panel.assign(KEY_K)
	expect(press_key(KEY_K).is_action_pressed("attack") and not press_key(KEY_K).is_action_pressed("jump"), "K moves from jump to attack")
	expect(Keys.bindings["jump"][1] == 0 and main.key_panel.status.text.contains("跳"), "the panel says jump lost K")
	expect(main.help_label.text.contains("K/J 攻擊"), "help bar follows the new keys")
	main.key_panel.close()
	expect(not player.input_blocked, "closing settings gives control back")
	Keys.reset("")
	expect(press_key(KEY_K).is_action_pressed("jump"), "reset brings the defaults back")
	main.free()

## 依地圖與事件切換配樂：走進村落換村落曲、事件裡換劇情曲、事件裡有敵人換戰鬥曲、心魔事件換心魔對決曲。
func test_music_by_map_and_event() -> void:
	var main: Node = await new_game()
	var audio: Node = main.audio
	for key in ["tag.cave", "tag.village", "tag.shrine", "tag.den", "tag.hall", "event.story", "event.combat", "event.heart_demon"]:
		expect(audio.music.has(key), "%s has music" % key)
	expect(main.state.region == "region.qingyun_foothills", "start in the foothills")
	var village: Dictionary = {}
	for span in main.chunk_spans:
		if "village" in span["tags"]:
			village = span
	expect(not village.is_empty(), "the foothills map has a village")
	main.player.position.x = (village["x0"] + village["x1"]) / 2.0
	main._process(0.016)
	expect(audio.current_music == "tag.village", "walking into the village switches to the village music")
	main.player.position.x = main.chunk_spans[0]["x0"] + 50.0
	main._process(0.016)
	expect(audio.current_music == "region.qingyun_foothills", "and back to the foothills music outside")
	var pack: Dictionary = {}
	for p in main.pool:
		if p.has("map") and not main._pack_has_tag(p, "illusion"):
			pack = p
	main.start_pack(pack)
	main._process(0.016)
	expect(audio.current_music == "event.story", "a story event plays the story music")
	main._combat_hold = 1.0
	expect(main.music_choice() == "event.combat", "enemies in an event switch to the battle music")
	main._heart_demon_event = true
	expect(main.music_choice() == "event.heart_demon", "the heart demon gets its own battle music")
	main.free()



## 兵器與功法（docs/design/weapons-and-arts.md）：四種兵器手感不同、功法有被動與術法、本命組合有招牌。
func spawn_dummy(main: Node, id: String, dx: float, power := 10.0) -> Node2D:
	main._on_actor_spawned({"id": id, "template": "mob.wandering_ghost", "name": "木人" + id, "disposition": "hostile", "power": power})
	var view: Node2D = main.actor_views[id]
	view.position.x = main.player.position.x + dx
	return view


func fresh_attack(main: Node) -> void:
	main.attack_cooldown = 0.0
	main.combo_timer = 0.0
	main.attack()


func test_weapons_and_arts() -> void:
	var main: Node = await new_game()
	main.clear_wild()
	await step(main, {}, 10)
	var weapons: Dictionary = main.weapons
	var arts: Dictionary = main.arts
	# 資料：兵器的類別、功法的本命、掉落表裡同名的兵器都對得上
	for id in weapons:
		if id.begins_with("weapon."):
			expect(weapons["kinds"].has(weapons[id]["kind"]), "%s has a known kind" % id)
	for id in arts:
		expect(arts[id].has("art") and arts[id].has("affinity"), "%s has an art and an affinity" % id)
	expect(main.Martial.weapon_by_name(weapons, "斬馬刀") != "" and main.loot["loot.wild_bandit"]["rare"].has("斬馬刀"), "the bandit drop 斬馬刀 is a weapon")
	expect(main.loot["loot.demon_core"]["rare"].has("血煞殘卷"), "the demon core can drop the 血煞 scroll")
	# 開局：青鋒劍、青雲劍訣，四種凡器都在手上
	expect(main.weapon_id() == "weapon.qingfeng_sword" and main.gongfa_id() == "gongfa.qingyun_sword", "start with the sect sword and 青雲劍訣")
	expect(main.owned_weapons().size() == 4, "playtest starts with all four plain weapons")
	expect(main.player.weapon_view.kind == "sword", "the sword is drawn on the player")
	main.player.facing = 1
	# 劍：本命 ×1.15，三段第三下最重、放劍氣
	var d: Node2D = spawn_dummy(main, "a", 40)
	var hp0: int = main.actor_hp["a"]
	fresh_attack(main)
	expect(hp0 - main.actor_hp["a"] == 12, "a sword cut does 12 with 青雲劍訣 (10 × 1.15)")
	expect(is_equal_approx(main.attack_cooldown, 0.35), "sword cooldown 0.35")
	for i in 2:
		d.position.x = main.player.position.x + 40
		main.attack_cooldown = 0.0
		main.attack()
	expect(main.projectiles.size() == 1 and main.projectiles[0]["kind"] == "wave", "the third sword cut of 青雲劍訣 sends out a sword qi")
	var far: Node2D = spawn_dummy(main, "far", 220)
	var far_hp: int = main.actor_hp["far"]
	for i in 30:
		main._update_projectiles(0.016)
	expect(main.actor_hp["far"] < far_hp, "the sword qi flies on and hits an enemy out of reach")
	main._remove_actor_view("far")
	main._remove_actor_view("a")
	# 背後：劍砍不到背後的敵人，刀砍得到
	var back: Node2D = spawn_dummy(main, "back", -45)
	var back_hp: int = main.actor_hp["back"]
	fresh_attack(main)
	expect(main.actor_hp["back"] == back_hp, "a sword does not reach an enemy behind you")
	expect(main.equip_weapon("weapon.kaishan_blade") and main.player.weapon_view.kind == "blade", "switch to the blade")
	var bx: float = back.position.x
	fresh_attack(main)
	expect(back_hp - main.actor_hp["back"] == 18, "a blade sweep does 18 and reaches behind")
	expect(is_equal_approx(main.attack_cooldown, 0.55), "the blade is slow (0.55)")
	expect(bx - back.position.x >= 40.0, "the blade knocks enemies far back")
	main._remove_actor_view("back")
	# 槍：遠、只打正前方
	var spear_t: Node2D = spawn_dummy(main, "s", 140)
	main.equip_weapon("weapon.diangang_spear")
	var s_hp: int = main.actor_hp["s"]
	fresh_attack(main)
	expect(s_hp - main.actor_hp["s"] == 12, "a spear thrust reaches 140 away for 12")
	main.equip_weapon("weapon.qingfeng_sword")
	spear_t.position.x = main.player.position.x + 140
	s_hp = main.actor_hp["s"]
	fresh_attack(main)
	expect(main.actor_hp["s"] == s_hp, "the sword does not reach that far")
	main._remove_actor_view("s")
	# 拳＋金剛體術：快、四段，第四拳震地波打到背後
	expect(main.practice("gongfa.jingang"), "switch to 金剛體術")
	main.equip_weapon("weapon.iron_fist")
	var f: Node2D = spawn_dummy(main, "f", 30)
	var f_back: Node2D = spawn_dummy(main, "fb", -100)
	var fb_hp: int = main.actor_hp["fb"]
	var f_hp: int = main.actor_hp["f"]
	fresh_attack(main)
	expect(f_hp - main.actor_hp["f"] == 7 and is_equal_approx(main.attack_cooldown, 0.2), "a jab is quick and light (6 × 1.15 → 7)")
	for i in 3:
		f.position.x = main.player.position.x + 30
		main.attack_cooldown = 0.0
		main.attack()
	expect(main.actor_hp["fb"] < fb_hp, "the fourth punch of 金剛體術 shakes the ground behind you too")
	# 金身：被打不扣血、反震
	main.mp = 30.0
	expect(main.cast_art() and main.armor_time > 0.0 and main.mp < 30.0, "金身 costs 靈力 and turns you to gold")
	var hp_armor: int = main.hp()
	f_hp = main.actor_hp["f"]
	main.player_invuln = 0.0
	f.position.x = main.player.position.x + 30
	main._enemy_strike("f")
	expect(main.hp() == hp_armor and main.actor_hp["f"] < f_hp, "under 金身 a strike does no harm and is reflected")
	main.armor_time = 0.0
	main.player_invuln = 0.0
	f.position.x = main.player.position.x + 30
	main._enemy_strike("f")
	expect(hp_armor - main.hp() == main.Martial.damage_taken(main.Cultivation.enemy_damage(10.0, 0), main.gongfa()), "金剛體術 takes 30% less damage")
	main._remove_actor_view("f")
	main._remove_actor_view("fb")
	# 五行法訣：火符，靈力不夠放不出來
	main.practice("gongfa.wuxing")
	main.art_cooldown = 0.0
	main.mp = 3.0
	expect(not main.cast_art(), "no 靈力, no fire talisman")
	main.mp = 30.0
	var fire_t: Node2D = spawn_dummy(main, "fire", 200)
	var fire_hp: int = main.actor_hp["fire"]
	expect(main.cast_art() and main.projectiles.any(func(p): return p["kind"] == "fireball"), "火符 flies out")
	for i in 40:
		main._update_projectiles(0.016)
	expect(fire_hp - main.actor_hp["fire"] == 30, "火符 hits for 30 at 煉氣 (10 × 2.4 × 1.25)")
	main._remove_actor_view("fire")
	# 血煞魔功：要條件；命中回血；殺生偏邪
	expect(not main.practice("gongfa.xuesha"), "血煞魔功 is locked for a righteous player")
	main.gain_item("血煞殘卷")
	expect(main.practice("gongfa.xuesha"), "the 血煞 scroll unlocks it")
	main.state.game_data["hp"] = 10
	var prey: Node2D = spawn_dummy(main, "prey", 30, 0.1)
	var zx: int = main.zhengxie()
	main.equip_weapon("weapon.qingfeng_sword")
	fresh_attack(main)
	expect(main.hp() == 11, "血煞魔功 heals 1 per hit")
	expect(not main.actor_views.has("prey") and main.zhengxie() == zx - 1, "killing with 血煞魔功 pulls 正邪 toward evil")
	main.state.game_data["hp"] = 30
	main.art_cooldown = 0.0
	expect(main.cast_art() and main.hp() == 24, "血祭 costs a fifth of 氣血 instead of 靈力")
	# 撿到兵器就入手；選單換兵器
	main.gain_item("斬馬刀")
	expect(main.owned_weapons().has("weapon.zhanma_blade"), "picking up 斬馬刀 adds it to your weapons")
	main.handle_input(press_key(KEY_G))
	expect(main.gear_options.size() == 5 + 4 and main.dialogue_panel.visible, "G opens the weapon and art menu")
	var idx: int = main.gear_options.find({"kind": "weapon", "id": "weapon.zhanma_blade"})
	main.choose_menu(idx)
	expect(main.weapon_id() == "weapon.zhanma_blade" and not main.dialogue_panel.visible, "pick 斬馬刀 from the menu")
	var z: Node2D = spawn_dummy(main, "z", 40)
	var z_hp: int = main.actor_hp["z"]
	fresh_attack(main)
	expect(z_hp - main.actor_hp["z"] == roundi(10 * 1.8 * 1.25 * 1.2), "a 法器 blade hits harder (grade ×1.25)")
	main._remove_actor_view("z")
	main.art_cooldown = 0.0
	main.mp = 30.0
	main.state.game_data["hp"] = 30
	main.handle_input(press_key(KEY_F))
	expect(main.art_cooldown > 0.0, "F casts the art")
	expect(main.help_label.text.contains("F/U 術法") and main.help_label.text.contains("G/O 兵器"), "help bar lists the art and gear keys")
	main.free()
## 衣櫃與容貌：每個選項都有圖層、疊出來跟原本立繪同尺寸、解鎖照條件、試穿關掉會換回、存檔帶著走。
func test_wardrobe() -> void:
	const Wardrobe = preload("res://scripts/wardrobe.gd")
	var layers: Dictionary = Wardrobe.layers()["layers"]
	var d := Wardrobe.default_look()
	for slot in Wardrobe.slots():
		var id: String = slot["id"]
		expect(d.has(id), "default look has %s" % id)
		var opts := Wardrobe.options(id)
		expect(opts.size() >= 2, "%s has choices" % id)
		for o in opts:
			for c in o.get("unlock", []):
				expect(c is Dictionary and c.has("type"), "%s/%s unlock is a condition" % [id, o["id"]])
			if not o.get("unlock", []).is_empty():
				expect(o.get("source", "") != "", "%s/%s says how to get it" % [id, o["id"]])
			var look := d.duplicate()
			look[id] = o["id"]
			for key in Wardrobe.layer_keys(look):
				# 短髮沒有後髮、沒戴配件沒有那層：那些 key 本來就可以沒有圖
				if key.begins_with("hair_back/") or key.begins_with("hair_under/"):
					continue
				expect(layers.has(key), "layer %s exists" % key)
				if layers.has(key):
					expect(ResourceLoader.exists("res://art/" + layers[key]["file"]), "layer file %s" % layers[key]["file"])
	var tex := Wardrobe.compose(d)
	var old: Texture2D = load("res://art/sprites/player.disciple.png")
	expect(tex.get_size() == old.get_size(), "composed look is the same size as the old sprite")
	var img := tex.get_image()
	var used := img.get_used_rect()
	var old_used := old.get_image().get_used_rect()
	expect(absi(used.position.y - old_used.position.y) <= 3 and absi(used.end.y - old_used.end.y) <= 3, "default look stands where the old sprite stood")
	expect(Wardrobe.compose(d) == tex, "same look composed once")
	expect(Wardrobe.normalize({"outfit": "nope", "hair": "twin"})["outfit"] == d["outfit"]
		and Wardrobe.normalize({"hair": "twin"})["hair"] == "twin", "normalize keeps known choices, drops unknown")

	var path := "user://zetas_test_wardrobe.json"
	var main: Node = await new_game(false, path)
	expect(main.player.sprite.texture == main.player_texture(), "player wears the composed look")
	expect(not Wardrobe.is_unlocked("outfit", "inner", main.state), "內門青衫 locked at 煉氣")
	main.state.tier_index = 1
	expect(Wardrobe.is_unlocked("outfit", "inner", main.state), "內門青衫 unlocked at 築基")
	main.autosave()
	expect(main.log_lines.any(func(l): return l.contains("內門青衫")), "new look announced")
	main.state.tier_index = 0
	main.open_wardrobe()
	var panel = main.wardrobe_panel
	expect(panel.visible and main.player.input_blocked, "Y opens the wardrobe")
	# 衣著欄往後換：外門短褐（已解鎖）直接穿上
	panel.cycle(1)
	expect(main.state.game_data["look"]["outfit"] == "outer", "unlocked outfit is worn at once")
	# 再往後：散修布衣、內門青衫（煉氣還沒解鎖）→ 試穿
	panel.cycle(1)
	panel.cycle(1)
	expect(panel.look["outfit"] == "inner" and main.state.game_data["look"]["outfit"] == "wanderer", "locked outfit is only tried on")
	expect(panel.note.text.contains("突破築基"), "locked outfit says where it comes from")
	var tried: Texture2D = panel.preview.texture
	panel.close()
	expect(not main.player.input_blocked, "closing gives control back")
	expect(main.player.sprite.texture != tried and main.player_look()["outfit"] == "wanderer", "closing drops the try-on")
	# 容貌：髮型換一個
	main.open_wardrobe()
	while panel.current_slot() != "hair":
		panel.move_row(1)
	panel.cycle(1)
	panel.close()
	expect(main.player_look()["hair"] == "bun", "hair changed")
	expect(main._portrait_crop(main._speaker_texture("player")).region == Wardrobe.PORTRAIT_RECT, "player portrait uses the fixed head crop")
	# 事件中不能換
	main.free()
	var again: Node = await new_game(false, path)
	expect(again.player_look()["outfit"] == "wanderer" and again.player_look()["hair"] == "bun", "look restored from save")
	# 心性變了：赤霞髮色條件不成立就換回預設
	again.state.game_data["look"]["hair_color"] = "crimson"
	expect(again.player_look()["hair_color"] == "ink", "crimson hair needs a killer's heart")
	again.state.karma["仁殺"] = -40
	expect(again.player_look()["hair_color"] == "crimson", "crimson hair with 仁殺 -40")
	again.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
