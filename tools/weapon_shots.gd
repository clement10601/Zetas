## 拍兵器與功法的特效：四種兵器出手、劍氣、火符、金身、血祭、兵器選單，各一張（docs/design/weapons-and-arts.md）。
## 執行：xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -s res://tools/weapon_shots.gd -- /tmp/shots
extends SceneTree

var out_dir := "/tmp/shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()
	create_timer(120.0).timeout.connect(func(): printerr("screenshot timeout"); quit(1))


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _dummy(main: Node, id: String, dx: float) -> void:
	main._on_actor_spawned({"id": id, "template": "mob.wandering_ghost", "name": "木人", "disposition": "hostile", "power": 50.0})
	main.actor_views[id].position.x = main.player.position.x + dx
	main.enemy_cooldown[id] = 999.0


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = ""
	main.generated_dir = ""
	main.use_director = false
	main.playlog_path = ""
	main.encounter_chance = 0.0
	main.hitstop_enabled = false
	root.add_child(main)
	await _frames(20)
	main.clear_wild()
	main.player.facing = 1
	_dummy(main, "d", 55)
	for w in [["weapon.qingfeng_sword", 3], ["weapon.kaishan_blade", 2], ["weapon.diangang_spear", 3], ["weapon.iron_fist", 4]]:
		main.equip_weapon(w[0])
		await _frames(10)
		for i in w[1]:
			main.actor_views["d"].position.x = main.player.position.x + 55
			main.attack_cooldown = 0.0
			main.attack()
			await _frames(4)
			if i == w[1] - 1 or i == 0:
				await _shot("%s_%d" % [w[0].get_slice(".", 1), i + 1])
			await _frames(6)
		await _frames(20)
	main.equip_weapon("weapon.qingfeng_sword")
	main.actor_views["d"].position.x = main.player.position.x + 400
	main.art_cooldown = 0.0
	main.mp = 99
	main.cast_art()
	await _frames(14)
	await _shot("art_qi_slash")
	await _frames(30)
	main.practice("gongfa.wuxing")
	main.art_cooldown = 0.0
	main.mp = 99
	main.cast_art()
	await _frames(14)
	await _shot("art_fire")
	await _frames(40)
	main.practice("gongfa.jingang")
	main.equip_weapon("weapon.iron_fist")
	main.art_cooldown = 0.0
	main.mp = 99
	main.cast_art()
	await _frames(12)
	await _shot("art_golden_body")
	main.gain_item("血煞殘卷")
	main.practice("gongfa.xuesha")
	main.equip_weapon("weapon.kaishan_blade")
	main.actor_views["d"].position.x = main.player.position.x + 90
	main.art_cooldown = 0.0
	main.cast_art()
	await _frames(8)
	await _shot("art_blood")
	await _frames(30)
	main.open_gear_menu()
	await _frames(10)
	await _shot("gear_menu")
	quit(0)
