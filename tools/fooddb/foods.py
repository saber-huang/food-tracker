"""
内置食物库的原始数据：App 里「选择食物」搜得到的常见食物。
改完运行 `python3 tools/fooddb/build_food_db.py`，会检查数据、生成 App 用的 FoodTracker/FoodTracker/FoodData/FoodDatabase.json。

目标不是「收录所有食物」，而是常吃的东西都能直接选；搜不到的交给 AI 估算或用户自己建「我的食物」。

每种食物写清楚营养数据从哪来（source）：
- usda(编号, ...)：美国农业部 FoodData Central（公有领域数据），编号可以在 https://fdc.nal.usda.gov 查到
  （SR Legacy 2018-04 版、FNDDS 2024-10-31 版）
- cn(...)：《中国食物成分表》里大家常用的数值（中国特有、或中式做法和美国差别大的主食，比如米饭、馒头）
- estimate(说明, ...)：按常见家常做法估算（写明用了哪些食材），只用于没有可靠数据的家常菜，界面上会显示「约」
营养素都是每 100 克可食部分；饮品写每 100 克的数值再加 density（密度），生成时换算成每 100 毫升。

份量单位（units）只放这种食物真的会用的：米饭用碗、鸡蛋用个、牛奶用杯和盒。克 / 毫升不用写，App 会自动加上。
每个单位：(单位, 多少克或毫升, 每次加减多少)。「多少克」是常见大小的估算，界面上都显示「约」。
"""

from __future__ import annotations

from dataclasses import dataclass, field

# 单位：中文名、英文单数、英文复数
UNITS: dict[str, tuple[str, str, str]] = {
    "bowl": ("碗", "bowl", "bowls"),
    "piece": ("个", "piece", "pieces"),
    "slice": ("片", "slice", "slices"),
    "stick": ("根", "piece", "pieces"),
    "cup": ("杯", "cup", "cups"),
    "carton": ("盒", "carton", "cartons"),
    "can": ("罐", "can", "cans"),
    "bottle": ("瓶", "bottle", "bottles"),
    "serving": ("份", "serving", "servings"),
    "handful": ("小把", "small handful", "small handfuls"),
    "tbsp": ("汤匙", "tbsp", "tbsp"),
    "tsp": ("茶匙", "tsp", "tsp"),
    "chunk": ("块", "piece", "pieces"),
    "each": ("只", "piece", "pieces"),
    "berry": ("颗", "piece", "pieces"),
    "pack": ("包", "pack", "packs"),
    "bag": ("小包", "small bag", "small bags"),
    "scoop": ("球", "scoop", "scoops"),
    "box": ("盒", "box", "boxes"),
    "square": ("小块", "square", "squares"),
}


@dataclass
class Source:
    kind: str  # usda / cn / estimate
    ref: str  # USDA 编号、成分表的条目名，或估算用的食材
    kcal: float
    protein: float
    carbs: float
    fat: float


def usda(fdc_id: int, kcal, protein, carbs, fat, desc: str = "") -> Source:
    return Source("usda", f"{fdc_id} {desc}".strip(), kcal, protein, carbs, fat)


def cn(entry: str, kcal, protein, carbs, fat) -> Source:
    return Source("cn", entry, kcal, protein, carbs, fat)


def estimate(note: str, kcal, protein, carbs, fat) -> Source:
    return Source("estimate", note, kcal, protein, carbs, fat)


@dataclass
class Food:
    id: str
    name: str
    name_en: str
    category: str  # staple / protein / dairy / vegetable / fruit / snack / drink / condiment / dish
    source: Source
    units: list[tuple]  # (单位, 克或毫升, 每次加减多少[, 英文单数, 英文复数])
    aliases: list[str] = field(default_factory=list)
    aliases_en: list[str] = field(default_factory=list)
    density: float | None = None  # 有值 = 饮品，按毫升记录（1 毫升多少克）
    default_quantity: float = 1


# 同义词：一组里的词当成同一个词（第一个是标准写法）。只放「换了哪个词都是同一样东西」的词，
# 不放「蛋 → 鸡蛋」这种会把「鸭蛋」变成「鸭鸡蛋」的词；菜名的其他叫法写在每种食物的 aliases 里
SYNONYMS: list[list[str]] = [
    ["番茄", "西红柿"],
    ["土豆", "马铃薯", "洋芋"],
    ["红薯", "地瓜", "番薯", "山芋", "甘薯"],
    ["玉米", "苞米", "包谷"],
    ["西兰花", "西蓝花"],
    ["卷心菜", "包菜", "圆白菜", "洋白菜", "包心菜"],
    ["猕猴桃", "奇异果"],
    ["菠萝", "凤梨"],
    ["牛奶", "牛乳"],
    ["三文鱼", "鲑鱼"],
    ["馄饨", "云吞", "抄手"],
    ["冰淇淋", "冰激凌"],
    ["披萨", "比萨", "匹萨"],
    ["汉堡", "汉堡包"],
    ["青椒", "菜椒", "灯笼椒"],
    ["虾仁", "虾肉"],
]

FOODS: list[Food] = [
    # ---------------- 主食 ----------------
    Food("rice", "米饭", "Steamed rice", "staple", cn("米饭（蒸，粳米）", 116, 2.6, 25.9, 0.3),
         [("bowl", 150, 0.5)], ["白米饭", "白饭", "大米饭", "蒸米饭", "熟米饭"], ["rice", "white rice", "cooked rice"]),
    Food("brown_rice", "糙米饭", "Brown rice", "staple", usda(169704, 123, 2.7, 25.6, 1.0, "Rice, brown, long-grain, cooked"),
         [("bowl", 150, 0.5)], ["糙米"], ["brown rice"]),
    Food("congee", "白粥", "Rice porridge", "staple", usda(2708418, 39, 0.8, 8.4, 0.1, "Congee"),
         [("bowl", 250, 0.5)], ["白米粥", "大米粥", "稀饭", "粥"], ["congee", "porridge"]),
    Food("millet_porridge", "小米粥", "Millet porridge", "staple", cn("小米粥", 46, 1.4, 8.4, 0.7),
         [("bowl", 250, 0.5)], ["小米稀饭"], ["millet porridge"]),
    Food("oats", "燕麦片", "Rolled oats (dry)", "staple", usda(173904, 379, 13.2, 67.7, 6.5, "Cereals, oats, regular and quick, dry"),
         [("serving", 40, 0.5)], ["燕麦", "麦片", "即食燕麦"], ["oats", "oatmeal"]),
    Food("mantou", "馒头", "Steamed bun (mantou)", "staple", cn("馒头（均值）", 223, 7.0, 47.0, 1.1),
         [("piece", 100, 0.5)], ["白馒头", "馍", "馍馍"], ["mantou", "steamed bun"]),
    Food("baozi", "肉包子", "Meat bun (baozi)", "staple", usda(2708724, 273, 11.2, 39.8, 7.6, "Bao bun"),
         [("piece", 80, 1)], ["包子", "猪肉包子", "鲜肉包", "肉包"], ["baozi", "bao", "meat bun"]),
    Food("dumplings", "饺子", "Dumplings", "staple",
         estimate("按常见猪肉白菜速冻水饺的营养标签估算", 220, 8.5, 26.0, 9.5),
         [("piece", 20, 1)], ["水饺", "猪肉饺子", "猪肉白菜饺子", "煮饺子"], ["dumplings", "jiaozi"], default_quantity=10),
    Food("potstickers", "煎饺", "Pan-fried dumplings", "staple",
         usda(2708705, 192, 8.8, 14.1, 11.1, "Wonton, dumpling or pot sticker, fried"),
         [("piece", 25, 1)], ["锅贴"], ["potstickers", "fried dumplings"], default_quantity=8),
    Food("noodles", "面条", "Noodles (cooked)", "staple",
         usda(168909, 131, 4.0, 27.5, 0.2, "Noodles, japanese, somen, cooked（小麦挂面，煮）"),
         [("bowl", 200, 0.5)], ["挂面", "煮面条", "清汤面", "素面"], ["noodles", "wheat noodles"]),
    Food("instant_noodles", "方便面", "Instant noodles (dry)", "staple",
         usda(171177, 440, 10.2, 60.3, 17.6, "Soup, ramen noodle, any flavor, dry"),
         [("pack", 100, 0.5)], ["泡面", "速食面"], ["instant noodles", "ramen"]),
    Food("rice_noodles", "米粉", "Rice noodles (cooked)", "staple", usda(168914, 108, 1.8, 24.0, 0.2, "Rice noodles, cooked"),
         [("bowl", 200, 0.5)], ["米线", "河粉"], ["rice noodles", "vermicelli"]),
    Food("whole_wheat_bread", "全麦面包", "Whole-wheat bread", "staple",
         usda(172688, 252, 12.4, 42.7, 3.5, "Bread, whole-wheat, commercially prepared"),
         [("slice", 30, 1)], ["全麦吐司"], ["whole wheat bread", "whole grain bread"]),
    Food("white_bread", "吐司", "White bread", "staple",
         usda(174924, 266, 8.8, 49.4, 3.3, "Bread, white, commercially prepared"),
         [("slice", 30, 1)], ["白吐司", "面包", "白面包", "切片面包", "土司"], ["bread", "white bread", "toast"]),
    Food("croissant", "牛角包", "Croissant", "staple", usda(2707678, 406, 8.2, 45.8, 21.0, "Croissant"),
         [("piece", 60, 1)], ["可颂", "羊角包"], ["croissant"]),
    Food("youtiao", "油条", "Youtiao (fried dough)", "staple", cn("油条", 386, 6.9, 51.0, 17.6),
         [("stick", 60, 0.5, "stick", "sticks")], [], ["youtiao", "fried dough stick"]),
    Food("corn", "玉米", "Corn on the cob", "staple",
         usda(169999, 96, 3.4, 21.0, 1.5, "Corn, sweet, yellow, cooked, boiled"),
         [("stick", 100, 0.5, "ear", "ears")], ["玉米棒", "甜玉米", "煮玉米", "玉米粒"], ["corn", "sweet corn"]),
    Food("sweet_potato", "红薯", "Sweet potato", "staple",
         usda(168483, 90, 2.0, 20.7, 0.1, "Sweet potato, cooked, baked in skin, flesh"),
         [("piece", 150, 0.5)], ["烤红薯", "蒸红薯", "紫薯"], ["sweet potato", "yam"]),
    Food("potato", "土豆", "Potato (boiled)", "staple",
         usda(170440, 86, 1.7, 20.0, 0.1, "Potatoes, boiled, cooked without skin, flesh"),
         [("piece", 150, 0.5)], ["煮土豆", "蒸土豆"], ["potato", "boiled potato"]),
    Food("pumpkin", "南瓜", "Pumpkin", "staple", usda(168449, 20, 0.7, 4.9, 0.1, "Pumpkin, cooked, boiled, drained"),
         [("chunk", 100, 0.5)], ["蒸南瓜"], ["pumpkin", "squash"]),
    Food("fried_rice", "蛋炒饭", "Egg fried rice", "dish",
         usda(167668, 174, 4.0, 32.8, 3.0, "Restaurant, Chinese, fried rice, without meat"),
         [("serving", 300, 0.5)], ["炒饭", "鸡蛋炒饭", "扬州炒饭"], ["fried rice", "egg fried rice"]),
    Food("lo_mein", "炒面", "Stir-fried noodles", "dish", usda(2708798, 121, 4.8, 20.2, 2.4, "Lo mein, NFS"),
         [("serving", 300, 0.5)], ["炒面条", "肉丝炒面"], ["lo mein", "chow mein", "fried noodles"]),
    Food("beef_noodle_soup", "牛肉面", "Beef noodle soup", "dish",
         estimate("一碗约 550 克：煮面 200 克、牛肉 50 克、汤 300 克（含少量油）", 80, 4.0, 10.5, 2.3),
         [("bowl", 550, 0.5)], ["兰州拉面", "红烧牛肉面", "拉面"], ["beef noodle soup", "beef noodles"]),

    # ---------------- 西式快餐 ----------------
    Food("hamburger", "汉堡", "Hamburger", "dish", usda(2706920, 288, 17.5, 20.7, 14.4, "Hamburger, NFS"),
         [("piece", 150, 1)], ["牛肉汉堡", "芝士汉堡"], ["hamburger", "burger", "cheeseburger"]),
    Food("pizza", "披萨", "Cheese pizza", "dish",
         usda(173292, 266, 11.4, 33.3, 9.7, "Fast Food, Pizza Chain, 14\" pizza, cheese topping, regular crust"),
         [("chunk", 100, 1, "slice", "slices")], ["芝士披萨"], ["pizza", "cheese pizza"]),
    Food("french_fries", "薯条", "French fries", "dish",
         usda(170698, 312, 3.4, 41.4, 14.7, "Fast foods, potato, french fried in vegetable oil"),
         [("serving", 110, 0.5)], ["炸薯条"], ["french fries", "fries", "chips"]),
    Food("fried_chicken", "炸鸡", "Fried chicken", "dish",
         usda(2706018, 241, 19.1, 6.0, 15.1, "Chicken drumstick, fried, coated, skin / coating eaten"),
         [("chunk", 100, 1)], ["炸鸡腿", "炸鸡块"], ["fried chicken"]),
    Food("sushi", "寿司", "Sushi", "dish", usda(2708959, 94, 2.9, 18.4, 0.7, "Sushi, NFS"),
         [("piece", 30, 1)], ["寿司卷"], ["sushi"], default_quantity=6),
    Food("spring_roll", "春卷", "Spring roll", "dish",
         usda(2708702, 272, 7.6, 27.0, 14.7, "Egg roll, with beef and/or pork"),
         [("piece", 50, 1)], ["炸春卷"], ["spring roll", "egg roll"]),

    # ---------------- 蛋、奶、豆制品 ----------------
    Food("egg", "鸡蛋", "Egg (boiled)", "protein", usda(173424, 155, 12.6, 1.1, 10.6, "Egg, whole, cooked, hard-boiled"),
         [("piece", 50, 1, "egg", "eggs")], ["水煮蛋", "煮鸡蛋", "白煮蛋", "茶叶蛋", "卤蛋", "蛋"],
         ["egg", "boiled egg", "hard-boiled egg"]),
    Food("fried_egg", "煎蛋", "Fried egg", "protein", usda(173423, 196, 13.6, 0.8, 14.8, "Egg, whole, cooked, fried"),
         [("piece", 50, 1, "egg", "eggs")], ["煎鸡蛋", "荷包蛋"], ["fried egg"]),
    Food("scrambled_egg", "炒鸡蛋", "Scrambled eggs", "protein",
         usda(2707200, 192, 11.6, 0.9, 15.8, "Egg omelet or scrambled egg, made with oil"),
         [("serving", 100, 0.5)], ["炒蛋", "鸡蛋饼", "煎蛋饼"], ["scrambled eggs", "omelet"]),
    Food("milk", "牛奶", "Milk (whole)", "dairy",
         usda(171265, 61, 3.1, 4.8, 3.2, "Milk, whole, 3.25% milkfat"),
         [("cup", 250, 0.5), ("carton", 250, 1)], ["全脂牛奶", "纯牛奶", "鲜牛奶"], ["milk", "whole milk"], density=1.03),
    Food("skim_milk", "脱脂牛奶", "Skim milk", "dairy",
         usda(171269, 34, 3.4, 5.0, 0.1, "Milk, nonfat, fluid"),
         [("cup", 250, 0.5), ("carton", 250, 1)], ["低脂牛奶", "脱脂奶"], ["skim milk", "nonfat milk"], density=1.035),
    Food("yogurt", "酸奶", "Yogurt (sweetened)", "dairy", cn("酸奶（均值）", 72, 2.5, 9.3, 2.7),
         [("cup", 150, 0.5)], ["酸牛奶", "风味酸奶", "原味酸奶"], ["yogurt", "yoghurt"]),
    Food("plain_yogurt", "无糖酸奶", "Plain yogurt (unsweetened)", "dairy",
         usda(171284, 61, 3.5, 4.7, 3.2, "Yogurt, plain, whole milk"),
         [("cup", 150, 0.5)], ["无蔗糖酸奶"], ["plain yogurt", "unsweetened yogurt"]),
    Food("greek_yogurt", "希腊酸奶", "Greek yogurt", "dairy",
         usda(171304, 97, 9.0, 4.0, 5.0, "Yogurt, Greek, plain, whole milk"),
         [("cup", 150, 0.5)], ["希腊式酸奶"], ["greek yogurt"]),
    Food("soy_milk", "豆浆", "Soy milk (unsweetened)", "dairy",
         usda(175215, 33, 2.9, 1.7, 1.6, "Soymilk (all flavors), unsweetened"),
         [("cup", 250, 0.5)], ["无糖豆浆", "原味豆浆"], ["soy milk", "soymilk"], density=1.02),
    Food("sweet_soy_milk", "甜豆浆", "Soy milk (sweetened)", "dairy",
         usda(172446, 54, 3.3, 6.3, 1.8, "Soymilk, original and vanilla, unfortified"),
         [("cup", 250, 0.5)], ["加糖豆浆", "豆奶"], ["sweetened soy milk"], density=1.02),
    Food("tofu", "豆腐", "Tofu", "protein",
         usda(172476, 76, 8.1, 1.9, 4.8, "Tofu, raw, regular, prepared with calcium sulfate"),
         [("serving", 100, 0.5)], ["北豆腐", "老豆腐", "卤水豆腐"], ["tofu", "bean curd"]),
    Food("silken_tofu", "嫩豆腐", "Silken tofu", "protein",
         usda(172461, 62, 6.9, 2.4, 2.7, "MORI-NU, Tofu, silken, firm"),
         [("serving", 100, 0.5)], ["内酯豆腐", "南豆腐"], ["silken tofu", "soft tofu"]),
    Food("cheese_slice", "奶酪片", "Cheese slice", "dairy",
         usda(170853, 366, 18.1, 4.8, 30.7, "Cheese, pasteurized process, American"),
         [("slice", 20, 1)], ["芝士片", "芝士", "奶酪"], ["cheese", "cheese slice"]),

    # ---------------- 肉、禽、鱼虾 ----------------
    Food("chicken_breast", "鸡胸肉", "Chicken breast (cooked)", "protein",
         usda(171477, 165, 31.0, 0.0, 3.6, "Chicken, broilers or fryers, breast, meat only, cooked, roasted"),
         [("serving", 100, 0.5)], ["鸡胸", "鸡胸脯肉", "鸡脯肉", "水煮鸡胸肉"], ["chicken breast", "chicken"]),
    Food("chicken_drumstick", "鸡腿", "Chicken drumstick", "protein",
         usda(173612, 191, 23.4, 0.0, 10.2, "Chicken, broilers or fryers, drumstick, meat and skin, cooked, roasted"),
         [("piece", 80, 1)], ["鸡腿肉", "烤鸡腿", "卤鸡腿", "琵琶腿"], ["chicken drumstick", "drumstick", "chicken leg"]),
    Food("chicken_wing", "鸡翅", "Chicken wing", "protein",
         usda(173630, 254, 23.8, 0.0, 16.9, "Chicken, broilers or fryers, wing, meat and skin, cooked, roasted"),
         [("piece", 30, 1)], ["鸡翅中", "烤鸡翅", "奥尔良鸡翅"], ["chicken wing", "wings"], default_quantity=3),
    Food("pork_lean", "瘦猪肉", "Lean pork (cooked)", "protein",
         usda(168250, 143, 26.2, 0.0, 3.5, "Pork, fresh, loin, tenderloin, separable lean only, cooked, roasted"),
         [("serving", 100, 0.5)], ["猪里脊", "里脊肉", "猪瘦肉", "猪肉"], ["pork", "lean pork", "pork loin"]),
    Food("beef_lean", "牛肉", "Beef (lean, cooked)", "protein",
         usda(171809, 169, 29.7, 0.0, 4.7, "Beef, round, eye of round, roast, separable lean only, cooked, roasted"),
         [("serving", 100, 0.5)], ["瘦牛肉", "牛腱", "牛腱子"], ["beef", "lean beef"]),
    Food("steak", "牛排", "Beef steak", "protein",
         usda(169458, 219, 29.0, 0.0, 10.5, "Beef, top sirloin, steak, separable lean and fat, choice, cooked, broiled"),
         [("chunk", 200, 0.5)], ["西冷牛排", "煎牛排", "牛扒"], ["steak", "sirloin"]),
    Food("lamb", "羊肉", "Lamb (lean, cooked)", "protein",
         usda(174314, 191, 28.3, 0.0, 7.7, "Lamb, leg, whole, separable lean only, cooked, roasted"),
         [("serving", 100, 0.5)], ["羊腿肉", "烤羊肉"], ["lamb", "mutton"]),
    Food("salmon", "三文鱼", "Salmon", "protein",
         usda(175168, 206, 22.1, 0.0, 12.3, "Fish, salmon, Atlantic, farmed, cooked, dry heat"),
         [("serving", 100, 0.5)], ["煎三文鱼", "烤三文鱼"], ["salmon"]),
    Food("sea_bass", "鲈鱼", "Sea bass", "protein",
         usda(173694, 124, 23.6, 0.0, 2.6, "Fish, sea bass, mixed species, cooked, dry heat"),
         [("serving", 150, 0.5)], ["清蒸鲈鱼", "清蒸鱼", "鱼肉", "鱼"], ["sea bass", "fish", "steamed fish"]),
    Food("shrimp", "虾", "Shrimp (boiled)", "protein", usda(175180, 99, 24.0, 0.2, 0.3, "Crustaceans, shrimp, cooked"),
         [("each", 10, 1), ("serving", 100, 0.5)], ["白灼虾", "虾仁", "大虾", "基围虾", "水煮虾"], ["shrimp", "prawns"],
         default_quantity=10),
    Food("ham_sausage", "火腿肠", "Ham sausage", "protein", cn("火腿肠", 212, 14.0, 15.6, 10.4),
         [("stick", 45, 1, "stick", "sticks")], [], ["ham sausage", "sausage"]),
    Food("bacon", "培根", "Bacon", "protein", usda(2705890, 468, 33.9, 1.7, 35.1, "Bacon or side pork, fresh, cooked"),
         [("slice", 10, 1)], ["煎培根"], ["bacon"], default_quantity=2),
    Food("luncheon_meat", "午餐肉", "Luncheon meat", "protein",
         usda(174571, 334, 12.5, 2.1, 30.3, "Luncheon meat, pork, canned"),
         [("slice", 20, 1)], ["午餐肉罐头", "斯帕姆"], ["luncheon meat", "spam"]),

    # ---------------- 蔬菜 ----------------
    Food("broccoli", "西兰花", "Broccoli", "vegetable", usda(169967, 35, 2.4, 7.2, 0.4, "Broccoli, cooked, boiled, drained"),
         [("serving", 100, 0.5)], ["绿花菜", "白灼西兰花", "水煮西兰花"], ["broccoli"]),
    Food("bok_choy", "小白菜", "Bok choy", "vegetable",
         usda(170391, 12, 1.6, 1.8, 0.2, "Cabbage, chinese (pak-choi), cooked, boiled, drained"),
         [("serving", 100, 0.5)], ["青菜", "上海青", "油菜", "小油菜", "菜心"], ["bok choy", "pak choi", "greens"]),
    Food("spinach", "菠菜", "Spinach", "vegetable", usda(168463, 23, 3.0, 3.8, 0.3, "Spinach, cooked, boiled, drained"),
         [("serving", 100, 0.5)], ["菠菜叶"], ["spinach"]),
    Food("lettuce", "生菜", "Lettuce", "vegetable", usda(169247, 17, 1.2, 3.3, 0.3, "Lettuce, cos or romaine, raw"),
         [("serving", 100, 0.5)], ["罗马生菜", "球生菜"], ["lettuce", "romaine"]),
    Food("cucumber", "黄瓜", "Cucumber", "vegetable", usda(168409, 15, 0.7, 3.6, 0.1, "Cucumber, with peel, raw"),
         [("stick", 200, 0.5)], ["青瓜", "凉拌黄瓜"], ["cucumber"]),
    Food("tomato", "番茄", "Tomato", "vegetable",
         usda(170457, 18, 0.9, 3.9, 0.2, "Tomatoes, red, ripe, raw, year round average"),
         [("piece", 150, 0.5)], ["小番茄", "圣女果"], ["tomato", "cherry tomato"]),
    Food("carrot", "胡萝卜", "Carrot", "vegetable", usda(170393, 41, 0.9, 9.6, 0.2, "Carrots, raw"),
         [("stick", 100, 0.5)], ["红萝卜"], ["carrot"]),
    Food("onion", "洋葱", "Onion", "vegetable", usda(170000, 40, 1.1, 9.3, 0.1, "Onions, raw"),
         [("piece", 150, 0.5)], ["圆葱"], ["onion"]),
    Food("green_pepper", "青椒", "Green bell pepper", "vegetable", usda(170427, 20, 0.9, 4.6, 0.2, "Peppers, sweet, green, raw"),
         [("piece", 100, 0.5)], ["甜椒"], ["bell pepper", "green pepper"]),
    Food("eggplant", "茄子", "Eggplant", "vegetable", usda(169229, 35, 0.8, 8.7, 0.2, "Eggplant, cooked, boiled, drained"),
         [("serving", 100, 0.5)], ["蒸茄子"], ["eggplant", "aubergine"]),
    Food("napa_cabbage", "大白菜", "Napa cabbage", "vegetable", usda(169979, 16, 1.2, 3.2, 0.2, "Cabbage, chinese (pe-tsai), raw"),
         [("serving", 100, 0.5)], ["白菜", "娃娃菜", "黄芽白"], ["napa cabbage", "chinese cabbage"]),
    Food("cabbage", "卷心菜", "Cabbage", "vegetable", usda(169975, 25, 1.3, 5.8, 0.1, "Cabbage, raw"),
         [("serving", 100, 0.5)], ["甘蓝", "莲花白"], ["cabbage"]),
    Food("celery", "芹菜", "Celery", "vegetable", usda(169988, 14, 0.7, 3.0, 0.2, "Celery, raw"),
         [("serving", 100, 0.5)], ["西芹"], ["celery"]),
    Food("mushroom", "蘑菇", "Mushrooms", "vegetable", usda(169251, 22, 3.1, 3.3, 0.3, "Mushrooms, white, raw"),
         [("serving", 100, 0.5)], ["白蘑菇", "口蘑"], ["mushroom", "mushrooms"]),
    Food("bean_sprouts", "豆芽", "Bean sprouts", "vegetable", usda(169957, 30, 3.0, 5.9, 0.2, "Mung beans, sprouted, raw"),
         [("serving", 100, 0.5)], ["绿豆芽"], ["bean sprouts"]),
    Food("winter_melon", "冬瓜", "Winter melon", "vegetable", usda(170475, 14, 0.4, 3.0, 0.2, "Waxgourd, cooked, boiled, drained"),
         [("serving", 100, 0.5)], [], ["winter melon"]),
    Food("enoki", "金针菇", "Enoki mushrooms", "vegetable", usda(169382, 37, 2.7, 7.8, 0.3, "Mushrooms, enoki, raw"),
         [("serving", 100, 0.5)], [], ["enoki"]),
    Food("edamame", "毛豆", "Edamame", "vegetable", usda(168411, 121, 11.9, 8.9, 5.2, "Edamame, frozen, prepared"),
         [("serving", 100, 0.5)], ["水煮毛豆", "毛豆仁"], ["edamame"]),

    # ---------------- 水果 ----------------
    Food("apple", "苹果", "Apple", "fruit", usda(171688, 52, 0.3, 13.8, 0.2, "Apples, raw, with skin"),
         [("piece", 180, 0.5, "apple", "apples")], [], ["apple"]),
    Food("banana", "香蕉", "Banana", "fruit", usda(173944, 89, 1.1, 22.8, 0.3, "Bananas, raw"),
         [("stick", 120, 0.5, "banana", "bananas")], [], ["banana"]),
    Food("orange", "橙子", "Orange", "fruit", usda(169097, 47, 0.9, 11.8, 0.1, "Oranges, raw, all commercial varieties"),
         [("piece", 150, 0.5, "orange", "oranges")], ["橙", "甜橙", "脐橙"], ["orange"]),
    Food("pear", "梨", "Pear", "fruit", usda(169118, 57, 0.4, 15.2, 0.1, "Pears, raw"),
         [("piece", 200, 0.5, "pear", "pears")], ["雪梨", "梨子", "香梨"], ["pear"]),
    Food("grapes", "葡萄", "Grapes", "fruit", usda(174683, 69, 0.7, 18.1, 0.2, "Grapes, red or green, raw"),
         [("serving", 100, 0.5)], ["提子", "青提", "红提"], ["grapes"]),
    Food("watermelon", "西瓜", "Watermelon", "fruit", usda(167765, 30, 0.6, 7.5, 0.1, "Watermelon, raw"),
         [("chunk", 200, 0.5, "slice", "slices")], [], ["watermelon"]),
    Food("strawberry", "草莓", "Strawberries", "fruit", usda(167762, 32, 0.7, 7.7, 0.3, "Strawberries, raw"),
         [("berry", 15, 1, "strawberry", "strawberries")], [], ["strawberry", "strawberries"], default_quantity=8),
    Food("kiwi", "猕猴桃", "Kiwi", "fruit", usda(168153, 61, 1.1, 14.7, 0.5, "Kiwifruit, green, raw"),
         [("piece", 75, 1, "kiwi", "kiwis")], [], ["kiwi", "kiwifruit"]),
    Food("mango", "芒果", "Mango", "fruit", usda(169910, 60, 0.8, 15.0, 0.4, "Mangos, raw"),
         [("piece", 200, 0.5, "mango", "mangoes")], [], ["mango"]),
    Food("peach", "桃子", "Peach", "fruit", usda(169928, 39, 0.9, 9.5, 0.2, "Peaches, yellow, raw"),
         [("piece", 150, 0.5, "peach", "peaches")], ["桃", "水蜜桃", "黄桃"], ["peach"]),
    Food("cherry", "樱桃", "Cherries", "fruit", usda(171719, 63, 1.1, 16.0, 0.2, "Cherries, sweet, raw"),
         [("berry", 8, 1, "cherry", "cherries")], ["车厘子"], ["cherries", "cherry"], default_quantity=10),
    Food("blueberry", "蓝莓", "Blueberries", "fruit", usda(171711, 57, 0.7, 14.5, 0.3, "Blueberries, raw"),
         [("box", 125, 0.5)], [], ["blueberries", "blueberry"]),
    Food("pineapple", "菠萝", "Pineapple", "fruit", usda(169124, 50, 0.5, 13.1, 0.1, "Pineapple, raw, all varieties"),
         [("serving", 100, 0.5)], [], ["pineapple"]),
    Food("dragon_fruit", "火龙果", "Dragon fruit", "fruit", usda(2709234, 68, 0.7, 16.2, 0.2, "Dragon fruit"),
         [("piece", 300, 0.5)], ["红心火龙果", "白心火龙果"], ["dragon fruit", "pitaya"]),
    Food("pomelo", "柚子", "Pomelo", "fruit", usda(167754, 38, 0.8, 9.6, 0.0, "Pummelo, raw"),
         [("serving", 100, 0.5)], ["柚", "西柚", "沙田柚"], ["pomelo", "grapefruit"]),
    Food("cantaloupe", "哈密瓜", "Cantaloupe", "fruit", usda(169092, 34, 0.8, 8.2, 0.2, "Melons, cantaloupe, raw"),
         [("chunk", 150, 0.5, "slice", "slices")], ["甜瓜", "蜜瓜"], ["cantaloupe", "melon"]),
    Food("lychee", "荔枝", "Lychee", "fruit", usda(169086, 66, 0.8, 16.5, 0.4, "Litchis, raw"),
         [("berry", 20, 1, "lychee", "lychees")], [], ["lychee", "litchi"], default_quantity=10),

    # ---------------- 坚果、零食 ----------------
    Food("peanuts", "花生", "Peanuts", "snack", usda(173806, 587, 24.4, 21.3, 49.7, "Peanuts, all types, dry-roasted"),
         [("handful", 15, 0.5)], ["花生米", "炒花生"], ["peanuts"]),
    Food("walnuts", "核桃", "Walnuts", "snack", usda(170187, 654, 15.2, 13.7, 65.2, "Nuts, walnuts, english"),
         [("piece", 5, 1, "walnut", "walnuts"), ("handful", 15, 0.5)], ["核桃仁"], ["walnuts"], default_quantity=3),
    Food("almonds", "杏仁", "Almonds", "snack", usda(170158, 598, 21.0, 21.0, 52.5, "Nuts, almonds, dry roasted"),
         [("handful", 15, 0.5)], ["巴旦木", "扁桃仁"], ["almonds"]),
    Food("cashews", "腰果", "Cashews", "snack", usda(170571, 574, 15.3, 32.7, 46.4, "Nuts, cashew nuts, dry roasted"),
         [("handful", 15, 0.5)], [], ["cashews"]),
    Food("mixed_nuts", "混合坚果", "Mixed nuts", "snack",
         usda(170585, 607, 19.5, 22.4, 53.5, "Nuts, mixed nuts, dry roasted, with peanuts"),
         [("pack", 25, 1), ("handful", 15, 0.5)], ["每日坚果", "坚果"], ["mixed nuts", "nuts"]),
    Food("sunflower_seeds", "瓜子", "Sunflower seeds", "snack",
         usda(170563, 582, 19.3, 24.1, 49.8, "Seeds, sunflower seed kernels, dry roasted"),
         [("handful", 15, 0.5)], ["葵花籽", "瓜子仁"], ["sunflower seeds"]),
    Food("potato_chips", "薯片", "Potato chips", "snack", usda(169677, 532, 6.4, 53.8, 34.0, "Snacks, potato chips, plain, salted"),
         [("bag", 40, 0.5)], [], ["potato chips", "crisps"]),
    Food("cookies", "饼干", "Cookies", "snack", usda(174950, 467, 6.1, 68.9, 18.8, "Cookies, butter, commercially prepared"),
         [("chunk", 10, 1)], ["曲奇", "黄油饼干"], ["cookies", "biscuits"], default_quantity=3),
    Food("dark_chocolate", "黑巧克力", "Dark chocolate", "snack", usda(170273, 598, 7.8, 45.9, 42.6, "Chocolate, dark, 70-85% cacao solids"),
         [("square", 10, 1)], ["巧克力"], ["dark chocolate", "chocolate"]),
    Food("sponge_cake", "蛋糕", "Sponge cake", "snack", usda(172706, 290, 5.4, 61.0, 2.7, "Cake, sponge, commercially prepared"),
         [("chunk", 80, 0.5, "slice", "slices")], ["海绵蛋糕", "戚风蛋糕"], ["cake", "sponge cake"]),
    Food("ice_cream", "冰淇淋", "Ice cream", "snack", usda(167575, 207, 3.5, 23.6, 11.0, "Ice creams, vanilla"),
         [("scoop", 65, 1)], ["雪糕", "香草冰淇淋"], ["ice cream"]),

    # ---------------- 饮品（按毫升记录） ----------------
    Food("cola", "可乐", "Cola", "drink", usda(2710541, 42, 0.0, 10.4, 0.0, "Soft drink, cola"),
         [("can", 330, 1), ("bottle", 500, 1)], ["可口可乐", "百事可乐", "汽水"], ["cola", "coke", "soda"], density=1.04),
    Food("diet_cola", "无糖可乐", "Diet cola", "drink", usda(2710542, 2, 0.1, 0.3, 0.0, "Soft drink, cola, diet"),
         [("can", 330, 1), ("bottle", 500, 1)], ["零度可乐", "健怡可乐", "零糖可乐"], ["diet coke", "coke zero", "diet cola"],
         density=1.0),
    Food("orange_juice", "橙汁", "Orange juice", "drink", usda(2709186, 47, 0.8, 10.2, 0.3, "Orange juice, 100%, NFS"),
         [("cup", 250, 0.5)], ["鲜榨橙汁", "果汁"], ["orange juice", "juice"], density=1.04),
    Food("black_coffee", "美式咖啡", "Black coffee", "drink", usda(171890, 1, 0.1, 0.0, 0.0, "Beverages, coffee, brewed"),
         [("cup", 350, 0.5)], ["黑咖啡", "咖啡", "美式"], ["black coffee", "coffee", "americano"], density=1.0),
    Food("latte", "拿铁", "Latte", "drink", usda(2710386, 43, 2.8, 4.3, 1.6, "Coffee, Latte"),
         [("cup", 350, 0.5)], ["拿铁咖啡", "咖啡拿铁"], ["latte", "cafe latte"], density=1.02),
    Food("bubble_tea", "奶茶", "Bubble tea", "drink", usda(2710508, 55, 0.4, 10.3, 1.4, "Tea, bubble"),
         [("cup", 500, 0.5)], ["珍珠奶茶", "波霸奶茶"], ["bubble tea", "milk tea", "boba"], density=1.04),
    Food("beer", "啤酒", "Beer", "drink", usda(168746, 43, 0.5, 3.5, 0.0, "Alcoholic beverage, beer, regular, all"),
         [("can", 330, 1), ("bottle", 500, 1)], [], ["beer"], density=1.01),
    Food("red_wine", "红酒", "Red wine", "drink", usda(173190, 85, 0.1, 2.6, 0.0, "Alcoholic beverage, wine, table, red"),
         [("cup", 150, 0.5, "glass", "glasses")], ["葡萄酒", "红葡萄酒"], ["red wine", "wine"], density=0.99),

    # ---------------- 油、糖、调味 ----------------
    Food("cooking_oil", "食用油", "Cooking oil", "condiment", usda(171411, 884, 0.0, 0.0, 100.0, "Oil, soybean, salad or cooking"),
         [("tbsp", 10, 0.5), ("tsp", 4, 1)], ["植物油", "花生油", "菜籽油", "大豆油", "色拉油", "橄榄油", "油"],
         ["oil", "cooking oil", "olive oil"]),
    Food("sugar", "白砂糖", "Sugar", "condiment", usda(169655, 387, 0.0, 100.0, 0.0, "Sugars, granulated"),
         [("tsp", 4, 1), ("tbsp", 12, 0.5)], ["白糖", "砂糖", "糖"], ["sugar"]),
    Food("honey", "蜂蜜", "Honey", "condiment", usda(169640, 304, 0.3, 82.4, 0.0, "Honey"),
         [("tbsp", 20, 0.5), ("tsp", 7, 1)], [], ["honey"]),
    Food("peanut_butter", "花生酱", "Peanut butter", "condiment", usda(172470, 598, 22.2, 22.3, 51.4, "Peanut butter, smooth style"),
         [("tbsp", 16, 0.5)], [], ["peanut butter"]),

    # ---------------- 家常菜（按常见做法估算） ----------------
    Food("tomato_egg", "番茄炒蛋", "Tomato and egg stir-fry", "dish",
         estimate("鸡蛋 100 克、番茄 200 克、油 10 克、糖 5 克", 91, 4.6, 4.3, 6.3),
         [("serving", 200, 0.5)], ["番茄炒鸡蛋", "番茄鸡蛋"], ["tomato egg stir-fry", "tomato and egg"]),
    Food("kung_pao_chicken", "宫保鸡丁", "Kung pao chicken", "dish",
         estimate("鸡腿肉 250 克（熟后约 190 克）、花生 30 克、油 20 克、黄瓜葱段 60 克、糖和淀粉各 8 克", 219, 17.4, 7.4, 13.5),
         [("serving", 200, 0.5)], ["宫爆鸡丁"], ["kung pao chicken"]),
    Food("mapo_tofu", "麻婆豆腐", "Mapo tofu", "dish",
         estimate("豆腐 300 克、肉末 50 克、油 15 克、豆瓣酱 15 克、淀粉 5 克、汤汁 80 克", 117, 7.4, 2.8, 8.9),
         [("serving", 250, 0.5)], [], ["mapo tofu"]),
    Food("pork_pepper", "青椒肉丝", "Shredded pork with peppers", "dish",
         estimate("猪里脊 150 克、青椒 200 克、油 15 克、淀粉 5 克", 114, 10.5, 4.3, 6.2),
         [("serving", 200, 0.5)], ["青椒炒肉丝", "青椒炒肉"], ["pork with peppers"]),
    Food("yuxiang_pork", "鱼香肉丝", "Yuxiang shredded pork", "dish",
         estimate("猪里脊 150 克、木耳胡萝卜笋丝 150 克、油 20 克、糖 10 克、淀粉 8 克", 154, 11.0, 9.1, 7.9),
         [("serving", 200, 0.5)], [], ["yuxiang pork", "fish-flavored pork"]),
    Food("braised_pork", "红烧肉", "Braised pork belly", "dish",
         estimate("五花肉炖煮后（部分油脂析出），含少量糖和酱油", 460, 10.0, 6.0, 44.0),
         [("serving", 150, 0.5)], ["红烧五花肉", "东坡肉"], ["braised pork belly", "red braised pork"]),
    Food("stir_fried_greens", "清炒时蔬", "Stir-fried greens", "dish",
         estimate("青菜 300 克（炒后约 280 克）、油 10 克", 48, 1.7, 1.9, 3.8),
         [("serving", 200, 0.5)], ["炒青菜", "清炒青菜", "蒜蓉青菜", "炒时蔬", "清炒小白菜", "炒菜心"],
         ["stir-fried vegetables", "stir-fried greens"]),
    Food("potato_shreds", "土豆丝", "Stir-fried shredded potato", "dish",
         estimate("土豆 300 克、油 15 克、醋和辣椒少量", 121, 2.0, 17.4, 5.1),
         [("serving", 200, 0.5)], ["酸辣土豆丝", "炒土豆丝", "醋溜土豆丝"], ["shredded potato stir-fry"]),
]
