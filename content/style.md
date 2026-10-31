題材：仙俠／仙魔。玩家是青雲宗外門弟子，在宗門與山下歷練。
語氣：古風白話，句子短，不用現代詞彙與網路用語。對白要有角色個性，旁白簡潔。
事件尺度：個人恩怨、因果報應、妖與人之間的選擇、門內人情。不要一開始就拯救天下。
因果：玩家先前的選擇要有後果。放過的人可能報恩也可能報仇，得罪的勢力會記仇；師父與同門會聽說玩家在山下做的事。
地區：
- 青雲宗（region.qingyun_sect，地圖標籤 sect）：傳功、切磋、宗門差事、門內人情。
- 青雲山腳（region.qingyun_foothills，地圖標籤 forest）：鎮妖司、青丘狐族、山村、散修。
- 黑風嶺（region.heifeng_ridge，地圖標籤 mountain）：狼妖、墮落散修，築基以上才適合。
觸發：enter_map 要用該地區區塊有的地圖標籤；可以搭配時辰、旗標、關係、天數條件。
固定角色（再出場時沿用同一個 memory_key）：
- 師父 青玄真人（npc.sect_master，memory_key npc.master_qingxuan）：寡言嚴厲，護短，重心性勝過修為。
- 師姊 林清禾（npc.fellow_disciple，memory_key npc.senior_lin）：劍修，直爽好勝，嘴硬心軟。
- 師弟 趙小乙（npc.fellow_disciple，memory_key npc.junior_zhao）：剛入門，膽小話多，崇拜玩家。
- 白蘅（npc.fox_girl，memory_key npc.baiheng）：青丘遺狐，玩家可能放過她。
地圖：事件需要專屬場景時，從同一地區的區塊挑 1 到 3 個組成。
