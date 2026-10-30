## Zetas 測試：內容資料一致性 + 兩個內容包在主場景中從觸發到結局跑完一遍。
## 執行：python tools/sync_engine.py && godot --headless --path . -s res://tests/run_tests.gd
extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


## 場景樹在 _initialize 時尚未開始運作，延後一格才會呼叫節點的 _ready。
func _run() -> void:
	await test_content_references()
	await test_fox_repays_kindness()
	await test_heart_demon_trial()
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func expect(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + what)


func new_game() -> Node:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	return main


## 內容包引用的區塊、地點、掉落表都必須存在於遊戲資料中。
func test_content_references() -> void:
	var main: Node = await new_game()
	expect(main.pool.size() == 2, "both packs load")
	for pack in main.pool:
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
