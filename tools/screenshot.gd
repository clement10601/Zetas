## 拍遊戲畫面：落腳地圖、常駐 NPC、對話框、洞窟、心魔幻境各一張，給美術調整前後對照。
## 執行（需要顯示器，雲端用 xvfb-run）：
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tools/screenshot.gd -- /tmp/shots
extends SceneTree

var out_dir := "/tmp/shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()
	# 卡住就放棄，免得 xvfb 一直掛著
	create_timer(90.0).timeout.connect(func(): printerr("screenshot timeout"); quit(1))


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = ""
	main.generated_dir = ""
	main.use_director = false
	main.playlog_path = ""
	main.encounter_chance = 0.0
	root.add_child(main)
	await _frames(10)
	# 1. 青雲山腳落腳處
	await _shot("01_foothills")
	# 2. 走到地圖中段看平台、繩梯
	main.player.position.x = 900
	main.player.snap_camera()
	await _shot("02_foothills_mid")
	# 3. 青雲宗，站在常駐 NPC 旁邊
	main.travel_to("region.qingyun_sect")
	await _frames(4)
	# 進宗門可能直接觸發事件（青玄峰問心）：先拍事件對話
	if main.runner != null:
		await create_timer(0.7).timeout   # 等卷軸標題卡展開、朱印蓋下
		await _shot("04_dialogue")
		for i in 40:
			if main.runner == null:
				break
			if not main.current_choices.is_empty():
				main.choose_visible(0)
			else:
				main.advance_dialogue()
			await _frames(1)
		main._hide_dialogue()
		main.go_home()
		await _frames(2)
	if main.residents.has("zhao"):
		main.player.position.x = main.residents["zhao"]["view"].position.x - 60
		main.player.snap_camera()
		await _shot("03_sect_resident")
		main.talk_to("zhao")
		await _shot("04b_resident_line")
		main._hide_dialogue()
	# 5. 洞窟與心魔幻境：直接用區塊建圖
	main.build_map([{"chunk": "chunk.mountain_cave", "order": 0}, {"chunk": "chunk.master_cave", "order": 1}], "")
	main.player.position = Vector2(500, 500)
	main.player.snap_camera()
	await _shot("05_cave")
	main.build_map([{"chunk": "chunk.illusion_entry", "order": 0}, {"chunk": "chunk.illusion_arena", "order": 1}], "")
	main.player.position = Vector2(700, 500)
	main.player.snap_camera()
	main._on_actor_spawned({"id": "mirror", "template": "boss.heart_demon_mirror", "name": "心魔", "disposition": "hostile", "spawn_at": ""})
	main.actor_views["mirror"].position.x = main.player.position.x + 70
	main.actor_hp["mirror"] = 999
	await _frames(20)
	main.attack()
	await create_timer(0.22).timeout
	await _shot("06_illusion")
	# 7. 暮色：回山腳換時辰
	main.go_home()
	main.state.time_of_day = "暮"
	main._refresh_status()
	main.tint.color = main.InkUI.time_tint("暮")
	main.player.position.x = 1500
	main.player.snap_camera()
	await _shot("07_dusk")
	# 8. 出劍寫「斬」字（沒打到東西：寫完淡出）
	main.state.time_of_day = "晨"
	main.tint.color = Color.WHITE
	main.attack_cooldown = 0.0
	main.attack()
	await create_timer(0.16).timeout
	await _shot("08_glyph")
	# 9. 突破時整圖染色（偏邪：朱）
	main.state.karma["正邪"] = -40
	main._breakthrough_wash()
	await create_timer(0.7).timeout
	await _shot("09_breakthrough")
	# 10. 夜裡的青雲宗：角色、平台要看得清
	main.travel_to("region.qingyun_sect")
	if main.runner != null:
		main.runner.abort("abandon")
		main._hide_dialogue()
	main.go_home()
	main.state.time_of_day = "夜"
	main.state.karma["正邪"] = 0
	main._refresh_status()
	main.tint.color = main.InkUI.time_tint("夜")
	main.player.position.x = 700
	main.player.snap_camera()
	await create_timer(1.6).timeout
	await _shot("10_sect_night")
	quit(0)
