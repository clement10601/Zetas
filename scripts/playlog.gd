## 遊玩紀錄：每行一筆 JSON，寫到 user://playlog.jsonl，給封閉測試算完成率與跳過率。
## 測試者把這個檔案傳回來，用 tools/playlog_report.py 彙整。
## 不記玩家輸入的文字，也不記任何帳號資訊；session 是每次啟動隨機產生的 id。
extends RefCounted

var path := ""
var session := ""
var _started := 0


func _init(p_path: String = "") -> void:
	path = p_path
	session = "%08x" % (randi() & 0x7fffffff)
	_started = Time.get_ticks_msec()


## t 是 Unix 秒，play 是本次啟動後經過的秒數
func write(event: String, data: Dictionary = {}) -> void:
	if path == "":
		return
	var f := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	var row := {"t": int(Time.get_unix_time_from_system()), "session": session, "event": event,
		"play": snappedf((Time.get_ticks_msec() - _started) / 1000.0, 0.1)}
	row.merge(data)
	f.store_line(JSON.stringify(row))
