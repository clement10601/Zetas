## 拍衣櫃畫面與幾套外觀在場景裡的樣子（美術對照用）。
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tools/wardrobe_shots.gd -- /tmp/shots
extends SceneTree

var out_dir := "/tmp/shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()
	create_timer(90.0).timeout.connect(func(): printerr("screenshot timeout"); quit(1))


func _shot(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = ""
	main.generated_dir = ""
	main.use_director = false
	main.playlog_path = ""
	main.encounter_chance = 0.0
	root.add_child(main)
	for i in 10:
		await process_frame
	main.open_wardrobe()
	await _shot("w1_wardrobe")
	var p = main.wardrobe_panel
	p.look = {"outfit": "xian", "head": "lotus_crown", "back": "ribbon_cloud", "waist": "jade_pendant",
		"hair": "high_tail", "hair_color": "frost", "face": "slender", "eyes": "phoenix", "brows": "willow"}
	p._refresh()
	await _shot("w2_try_xian")
	p.close()
	var looks := {
		"w3_mo": {"outfit": "mo", "head": "demon_mask", "back": "ink_cape", "hair": "wild", "hair_color": "crimson", "face": "square", "brows": "sword"},
		"w4_wanderer": {"outfit": "wanderer", "head": "weimao", "back": "", "waist": "gourd", "hair": "ponytail", "hair_color": "chestnut"},
	}
	main.state.tier_index = 3
	main.state.karma["仁殺"] = -50
	for k in ["流雲仙裳", "墨焰魔袍", "半面魔紋", "墨焰披風"]:
		main.state.items[k] = 1
	for name in looks:
		main.state.game_data["look"] = looks[name]
		main.apply_look()
		main.player.position.x = 600
		main.player.snap_camera()
		await _shot(name)
	quit(0)
