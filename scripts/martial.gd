## 兵器與功法的戰鬥換算（docs/design/weapons-and-arts.md）。全是純函式；數值在 content/weapons.json、content/arts.json。
extends RefCounted

const DEFAULT_WEAPON := "weapon.qingfeng_sword"
const DEFAULT_GONGFA := "gongfa.qingyun_sword"
## 試玩版開局就給的兵器（正式版改成宗門兵器架、差事兌換）
const STARTER_WEAPONS := ["weapon.qingfeng_sword", "weapon.kaishan_blade", "weapon.diangang_spear", "weapon.iron_fist"]
## 試玩版開局就會的功法；血煞魔功要條件
const STARTER_GONGFA := ["gongfa.qingyun_sword", "gongfa.wuxing", "gongfa.jingang", "gongfa.xuesha"]
const MP_BASE := 30
const MP_PER_TIER := 10
const MP_REGEN := 3.0


static func max_mp(tier: int) -> int:
	return MP_BASE + MP_PER_TIER * tier


## 兵器的類別數值（劍、刀、槍、拳）
static func kind_of(weapons: Dictionary, weapon_id: String) -> Dictionary:
	var w: Dictionary = weapons.get(weapon_id, weapons.get(DEFAULT_WEAPON, {}))
	return weapons.get("kinds", {}).get(w.get("kind", "sword"), {})


static func is_affinity(weapons: Dictionary, weapon_id: String, gongfa: Dictionary) -> bool:
	return weapons.get(weapon_id, {}).get("kind", "") == gongfa.get("affinity", "")


## 連段第幾下（0 起）是不是最後一下
static func is_finisher(kind: Dictionary, step: int) -> bool:
	return step == (kind.get("combo", [1.0]) as Array).size() - 1


## 普攻一下的傷害：境界基礎 × 連段倍率 × 品階 × 功法（本命加成、魔功加成）
static func attack_damage(base: int, weapons: Dictionary, weapon_id: String, step: int, gongfa: Dictionary) -> int:
	var kind := kind_of(weapons, weapon_id)
	var combo: Array = kind.get("combo", [1.0])
	var mult := float(combo[clampi(step, 0, combo.size() - 1)])
	var grade := int(weapons.get(weapon_id, {}).get("grade", 0))
	mult *= 1.0 + float(weapons.get("grade_bonus", 0.25)) * grade
	var passive: Dictionary = gongfa.get("passive", {})
	if is_affinity(weapons, weapon_id, gongfa):
		mult *= float(passive.get("affinity_damage", 1.0))
	mult *= float(passive.get("damage", 1.0))
	return maxi(1, roundi(base * mult))


## 術法傷害：境界基礎 × 術法倍率 × 功法術法加成
static func art_damage(base: int, gongfa: Dictionary) -> int:
	var art: Dictionary = gongfa.get("art", {})
	var mult := float(art.get("damage", 1.0)) * float(gongfa.get("passive", {}).get("art_power", 1.0))
	mult *= float(gongfa.get("passive", {}).get("damage", 1.0))
	return maxi(1, roundi(base * mult))


## 敵人在不在這把兵器打得到的地方：dx＝敵人 x − 玩家 x
static func in_reach(dx: float, facing: int, kind: Dictionary) -> bool:
	var ahead := dx * facing
	return ahead <= float(kind.get("reach", 90)) and ahead >= -float(kind.get("behind", 20))


## 這門功法修不修得了：沒有 requires 就能修；有的話正邪夠低或持有物品其一成立
static func can_practice(gongfa: Dictionary, zhengxie: int, items: Array) -> bool:
	var req: Dictionary = gongfa.get("requires", {})
	if req.is_empty():
		return true
	if req.has("karma_max") and zhengxie <= int(req["karma_max"]):
		return true
	return req.has("item") and items.has(req["item"])


static func requirement_text(gongfa: Dictionary) -> String:
	var req: Dictionary = gongfa.get("requires", {})
	var parts := []
	if req.has("karma_max"):
		parts.append("正邪 ≤ %d" % int(req["karma_max"]))
	if req.has("item"):
		parts.append("得到《%s》" % req["item"])
	return "或".join(parts)


## 受到的傷害：金剛體術減傷
static func damage_taken(amount: int, gongfa: Dictionary) -> int:
	return maxi(1, roundi(amount * float(gongfa.get("passive", {}).get("damage_taken", 1.0))))


static func mp_regen(gongfa: Dictionary) -> float:
	return MP_REGEN * float(gongfa.get("passive", {}).get("mp_regen", 1.0))


## 物品名對到兵器 id（loot.json 的物品名等於兵器名就是那把兵器）
static func weapon_by_name(weapons: Dictionary, item: String) -> String:
	for id in weapons:
		if id.begins_with("weapon.") and weapons[id].get("name", "") == item:
			return id
	return ""
