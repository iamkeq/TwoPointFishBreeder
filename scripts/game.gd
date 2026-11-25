extends Node
## The shop's money, calendar, stockroom, fish storage and monthly accounts (autoload "Game").
## The world (tanks, shelves, customers) lives in the scene; this is just the books.

const Data := preload("res://scripts/data.gd")
const FishData := preload("res://scripts/fish_data.gd")
const Genetics := preload("res://scripts/genetics.gd")
const Goals := preload("res://scripts/goals.gd")

signal money_changed
signal day_passed
signal month_ended(report: Dictionary)
signal stock_changed
signal fish_changed
signal speed_changed
signal notify(text: String)
signal staff_changed
signal loans_changed
signal plots_changed
signal started
signal show_result(result: Dictionary)
signal goals_changed
signal autosave_wanted
signal awards_changed
## Fish from the market arrived; the world puts them in holding tanks (see main.gd).
signal fish_delivered(fish: Array)

## Real seconds per game day at 1x speed.
const DAY_SECONDS := 6.0
const DAYS_PER_MONTH := 30
const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August",
	"September", "October", "November", "December"]
const SPEEDS := [0.0, 1.0, 2.0, 4.0]

var money: int = Data.START_MONEY
var day := 1
var month := 0
var year := 1
var abs_day := 1
## Paused until a start is chosen (see choose_start).
var speed := 0
## 0..100, rises with happy customers, falls with disappointed ones.
var reputation := 50.0
var marketing := ""

## Product id -> units waiting in the back room for the shelves.
var stockroom := {}
## [{"product" or "species", "units"/"stars", "arrives": abs_day}]
var pending_orders: Array = []
## Fish waiting in the back room (not in any tank): {"id", "species", "stars"}.
var fish_storage: Array = []

## Hired staff: {"id", "role", "name", "wage"}.
var staff: Array = []
var _next_staff_id := 1

## Loans being paid off: {"id", "name", "amount", "owed", "monthly"}.
var loans: Array = []
var extra_loans_taken := 0
## Plots bought ("west", "east", "back").
var owned_plots: Array = []
## Trophies from fish shows (top 3): {title, place, grand, day, fish}. Shown in the Hall of Fame.
var awards: Array = []
## The First steps checklist is folded down to its title bar.
var steps_minimized := false
var start_choice := ""
## Testing: months roll on without pausing for the report.
var autoplay := false
var _next_loan_id := 1

var stats := {}
## Lifetime counts for goals and achievements.
var totals := {"customers": 0, "fish_sold": 0, "items_sold": 0, "fish_bred": 0, "profit": 0,
	"mutations": 0, "best_stars": 0, "shows_won": 0, "grand_won": 0, "loans_paid": 0}
## "species:variety" of every non-common variety bred so far (the breeding book).
var discovered: Array = []
## "species:variety" of show-locked varieties won so far.
var unlocked: Array = []
var achievements_done: Array = []
## Goal star ratings reached (0..3).
var stars_earned := 0
## The fish entered in the next show (held there until the show), or {}.
var show_entry: Dictionary = {}
var show_number := 1
var last_show: Dictionary = {}
var last_report := {}
var history: Array = []

var _day_t := 0.0
var _next_fish_id := 1


## A save waiting to be applied when the main scene (re)loads (see save_game.gd).
var pending_load: Dictionary = {}
var _fresh: Dictionary = {}


func _ready() -> void:
	_reset_stats()
	_fresh = to_dict()


## Back to a brand new game (before the main scene reloads for one).
func reset() -> void:
	from_dict(_fresh.duplicate(true))
	pending_load = {}


## Everything worth keeping, as plain data for JSON.
func to_dict() -> Dictionary:
	var d := {}
	for key in SAVED:
		var v: Variant = get(key)
		d[key] = v.duplicate(true) if (v is Dictionary or v is Array) else v
	return d


func from_dict(d: Dictionary) -> void:
	for key in SAVED:
		if d.has(key):
			var v: Variant = d[key]
			set(key, v.duplicate(true) if (v is Dictionary or v is Array) else v)
	if not d.has("first_steps"):
		first_steps = ["keeper", "bred_on_show", "goldfish", "second_tank"]  # saves from before the checklist
	# Species taken out of the game (discus) leave old saves.
	fish_storage = fish_storage.filter(func(f): return Data.SPECIES.has(f.get("species", "")))
	if not show_entry.is_empty() and not Data.SPECIES.has(show_entry.get("species", "")):
		show_entry = {}
	if not d.has("awards"):
		# Saves from before the Hall of Fame: a gold trophy for each show already won.
		awards = []
		for i in int(totals.get("shows_won", 0)):
			awards.append({"title": "Fish Show", "place": 1, "grand": false, "fish": "", "day": 0})
	money_changed.emit()
	staff_changed.emit()
	loans_changed.emit()
	fish_changed.emit()
	stock_changed.emit()
	speed_changed.emit()


const SAVED := ["money", "day", "month", "year", "abs_day", "reputation", "marketing", "stockroom",
	"pending_orders", "fish_storage", "staff", "_next_staff_id", "loans", "extra_loans_taken", "owned_plots",
	"start_choice", "_next_loan_id", "stats", "last_report", "history", "totals", "discovered", "unlocked",
	"achievements_done", "stars_earned", "show_entry", "show_number", "last_show", "_day_t", "_next_fish_id",
	"showcase_peak", "first_steps", "awards", "steps_minimized"]


func time_scale() -> float:
	return SPEEDS[speed]


func set_speed(s: int) -> void:
	speed = clampi(s, 0, SPEEDS.size() - 1)
	speed_changed.emit()


func date_text() -> String:
	return "%d %s, Year %d" % [day, MONTHS[month], year]


func day_fraction() -> float:
	return _day_t / DAY_SECONDS


func _process(delta: float) -> void:
	if speed == 0:
		return
	_day_t += delta * time_scale()
	while _day_t >= DAY_SECONDS:
		_day_t -= DAY_SECONDS
		_next_day()


func _next_day() -> void:
	day += 1
	abs_day += 1
	_deliver_orders()
	_age_storage()
	if abs_day >= next_show_day():
		_run_show()
	check_goals()
	if day > DAYS_PER_MONTH:
		_end_month()
	day_passed.emit()


# --- Money ---------------------------------------------------------------------------

func can_afford(amount: int) -> bool:
	return money >= amount


## Pay `amount` for `category` (see _reset_stats). False (and nothing spent) if short.
func spend(amount: int, category: String) -> bool:
	if amount > money:
		notify.emit("Not enough money!")
		return false
	money -= amount
	stats["expenses"][category] = int(stats["expenses"].get(category, 0)) + amount
	money_changed.emit()
	return true


func earn(amount: int, category: String) -> void:
	money += amount
	stats["income"][category] = int(stats["income"].get(category, 0)) + amount
	money_changed.emit()


func add_stat(key: String, amount: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + amount
	if totals.has(key):
		totals[key] = int(totals[key]) + amount


func change_reputation(amount: float) -> void:
	reputation = clampf(reputation + amount, 0.0, 100.0)


## A "First steps" item done: pay its reward once.
func finish_step(id: String, text: String, reward: int) -> void:
	if first_steps.has(id):
		return
	first_steps.append(id)
	earn(reward, "goal_rewards")
	notify.emit("✔ First step done: %s (+$%d)" % [text, reward])


## How far each visit pulls reputation toward 100 (happy) or 0 (disappointed). Over
## time reputation settles at about the share of customers who leave happy, so a shop
## where 1 in 4 leaves disappointed sits near 75%. Bonuses (new varieties, show wins)
## lift it for a while and then wear off.
const REP_PULL := 0.02


func rate_visit(happy: bool) -> void:
	reputation = clampf(reputation + ((100.0 if happy else 0.0) - reputation) * REP_PULL, 0.0, 100.0)


# --- Fish ----------------------------------------------------------------------------

## A new fish. Variety defaults to a random common one, sex to random, age to adult.
func new_fish(species: String, stars: int, variety: String = "", sex: String = "", age: int = FishData.ADULT_AGE) -> Dictionary:
	if variety == "":
		var c := FishData.commons(species)
		variety = c[randi() % c.size()]
	if sex == "":
		sex = "m" if randf() < 0.5 else "f"
	var f := {"id": _next_fish_id, "species": species, "variety": variety, "sex": sex,
		"stars": clampi(stars, 1, 5), "age": age, "gen": 0}
	_next_fish_id += 1
	return f


## Fry from a breeding tank: give them ids, put them in storage and fill in the book.
func add_bred(fry: Array) -> void:
	for f in fry:
		f["id"] = _next_fish_id
		_next_fish_id += 1
		fish_storage.append(f)
		var key: String = f["species"] + ":" + f["variety"]
		var v := FishData.variety(f["species"], f["variety"])
		if v["kind"] != "common" and not discovered.has(key):
			discovered.append(key)
			var bonus := 100 if v["kind"] == "mutation" else 40 * int(pow(2, int(v.get("gen", 1)) - 1))
			earn(bonus, "discoveries")
			change_reputation(4.0 if v["kind"] == "mutation" else 2.0)
			notify.emit("New variety bred: %s! (+$%d)" % [FishData.full_name(f, Data.SPECIES[f["species"]]["name"]), bonus])
			if v["kind"] == "mutation":
				totals["mutations"] = int(totals["mutations"]) + 1
	add_stat("fish_bred", fry.size())
	fish_changed.emit()


## Fish in storage get a day older: fry grow up (their stars show once they're adults) and
## old fish die.
func _age_storage() -> void:
	for f in fish_storage.duplicate():
		var was_fry := not FishData.is_adult(f)
		if age_fish(f, "storage"):
			fish_storage.erase(f)
		elif was_fry and FishData.is_adult(f) and f.get("bred", false):
			totals["best_stars"] = maxi(int(totals["best_stars"]), int(f["stars"]))
	fish_changed.emit()


## Fish that died today: [fish, where].
var _deaths: Array = []


## A fish gets a day older. True if it died of old age (the caller takes it out).
## A valuable fish (4+ stars, a show ribbon, or `important`: one in a breeding tank) gets a
## warning near the end.
func age_fish(f: Dictionary, where: String, important: bool = false) -> bool:
	f["age"] = int(f.get("age", 0)) + 1
	var left := FishData.days_left(f)
	if left <= 0:
		if _deaths.is_empty():
			_report_deaths.call_deferred()
		_deaths.append([f, where])
		add_stat("fish_died")
		return true
	if left <= FishData.OLD_WARN_DAYS and not f.get("old_warned", false) and FishData.is_adult(f) \
			and (important or int(f["stars"]) >= 4 or int(f.get("ribbon", 0)) > 0):
		f["old_warned"] = true
		var keep := "Put it in the Hall of Fame to keep it forever." if owned_plots.has("hall") \
			else "Buy the Hall of Fame (Expand) to keep fish like this forever."
		if important and int(f["stars"]) < 4 and int(f.get("ribbon", 0)) == 0:
			keep = "Breed a replacement soon."
		notify.emit("%s (%s) is getting old: %d days left. %s" % [fish_label(f), where, left, keep])
	return false


func _report_deaths() -> void:
	if _deaths.is_empty():
		return
	if _deaths.size() == 1:
		var d: Array = _deaths[0]
		notify.emit("🕊 %s died of old age (%s)" % [FishData.full_name(d[0], Data.SPECIES[d[0]["species"]]["name"]), d[1]])
	else:
		var names := {}
		for d in _deaths:
			var n := FishData.full_name(d[0], Data.SPECIES[d[0]["species"]]["name"])
			names[n] = int(names.get(n, 0)) + 1
		var parts: Array[String] = []
		for n in names:
			parts.append(("%d x %s" % [names[n], n]) if names[n] > 1 else n)
		notify.emit("🕊 %d fish died of old age: %s" % [_deaths.size(), ", ".join(parts)])
	_deaths.clear()


## Every fish you own that is out of the tanks (the world adds tank fish when asked).
func all_storage_adults() -> Array:
	return fish_storage.filter(func(f): return FishData.is_adult(f))


func store_fish(fish: Dictionary) -> void:
	fish_storage.append(fish)
	fish_changed.emit()


func take_stored_fish(id: int) -> Dictionary:
	for i in fish_storage.size():
		if int(fish_storage[i]["id"]) == id:
			var f: Dictionary = fish_storage[i]
			fish_storage.remove_at(i)
			fish_changed.emit()
			return f
	return {}


## Sell a stored grown fish to the fish market. Returns what it paid (0 if it couldn't).
func sell_to_market(id: int) -> int:
	for f in fish_storage:
		if int(f["id"]) == id:
			var pay := Data.market_buy_price(f)
			if pay <= 0:
				return 0
			take_stored_fish(id)
			earn(pay, "market_sales")
			return pay
	return 0


## Stored grown fish of `max_stars` or fewer that can go to the market in bulk. Keeps
## any fish with a show ribbon, and one male and one female of each variety (the best).
func market_surplus(max_stars: int) -> Array:
	var keep := {}
	var by_best := fish_storage.filter(func(f): return FishData.is_adult(f))
	by_best.sort_custom(func(a, b): return int(a["stars"]) > int(b["stars"]))
	var out: Array = []
	for f in by_best:
		var key := "%s:%s:%s" % [f["species"], f["variety"], f["sex"]]
		if not keep.has(key):
			keep[key] = true
			continue
		if int(f["stars"]) <= max_stars and int(f.get("ribbon", 0)) == 0:
			out.append(f)
	return out


# --- Staff ----------------------------------------------------------------------------

func hire(role: String) -> Dictionary:
	var r: Dictionary = Data.STAFF[role]
	var used := staff.map(func(s): return s["name"])
	var names := Data.STAFF_NAMES.filter(func(n): return not used.has(n))
	if names.is_empty():
		names = Data.STAFF_NAMES
	var person := {"id": _next_staff_id, "role": role, "name": names[randi() % names.size()], "wage": int(r["wage"])}
	_next_staff_id += 1
	staff.append(person)
	notify.emit("Hired %s the %s ($%d/month)" % [person["name"], r["name"], person["wage"]])
	staff_changed.emit()
	return person


func fire(id: int) -> void:
	for i in staff.size():
		if int(staff[i]["id"]) == id:
			notify.emit("%s has left the shop" % staff[i]["name"])
			staff.remove_at(i)
			staff_changed.emit()
			return


func staff_count(role: String) -> int:
	return staff.filter(func(s): return s["role"] == role).size()


func wage_bill() -> int:
	var w := 0
	for s in staff:
		w += int(s["wage"])
	return w


# --- Expansion ----------------------------------------------------------------------------

func buy_plot(id: String) -> bool:
	if owned_plots.has(id):
		return false
	var p: Dictionary = Data.PLOTS[id]
	if not spend(int(p["cost"]), "expansion"):
		return false
	owned_plots.append(id)
	notify.emit("Bought the %s! Rent goes up $%d a month." % [p["name"], p["rent"]])
	plots_changed.emit()
	return true


func rent() -> int:
	var r: int = Data.RENT
	for id in owned_plots:
		r += int(Data.PLOTS[id]["rent"])
	return r


# --- Start and loans ---------------------------------------------------------------------

## Pick how the shop starts (see Data.STARTS). Unpauses the game.
func choose_start(id: String) -> void:
	start_choice = id
	var loan: String = Data.STARTS[id]["loan"]
	if loan != "":
		_add_loan(loan)
	started.emit()
	set_speed(1)


func loan_total_owed(id: String) -> int:
	var l: Dictionary = Data.LOANS[id]
	return int(round(float(l["amount"]) * (1.0 + float(l["interest"]))))


func loan_monthly(id: String) -> int:
	return int(ceil(float(loan_total_owed(id)) / float(Data.LOANS[id]["months"])))


func _add_loan(id: String) -> void:
	var l: Dictionary = Data.LOANS[id]
	loans.append({"id": _next_loan_id, "name": l["name"], "amount": int(l["amount"]),
		"owed": loan_total_owed(id), "monthly": loan_monthly(id)})
	_next_loan_id += 1
	money += int(l["amount"])
	stats["income"]["loans"] = int(stats["income"].get("loans", 0)) + int(l["amount"])
	money_changed.emit()
	loans_changed.emit()


## Months the bank still wants you to trade before it lends again (0 = it will now).
func months_until_loan() -> int:
	return maxi(0, Data.LOAN_WAIT_MONTHS - history.size())


func can_take_loan() -> bool:
	return extra_loans_taken < Data.EXTRA_LOANS and months_until_loan() == 0


func take_loan(id: String) -> bool:
	if not can_take_loan():
		return false
	extra_loans_taken += 1
	_add_loan(id)
	notify.emit("The bank lent you $%d" % Data.LOANS[id]["amount"])
	return true


func total_debt() -> int:
	var d := 0
	for l in loans:
		d += int(l["owed"])
	return d


## Pay the rest of a loan off now (if you have the money).
func pay_off(loan_id: int) -> bool:
	for l in loans:
		if int(l["id"]) == loan_id:
			if not spend(int(l["owed"]), "loan_repayments"):
				return false
			loans.erase(l)
			totals["loans_paid"] = int(totals["loans_paid"]) + 1
			notify.emit("%s paid off!" % l["name"])
			loans_changed.emit()
			return true
	return false


func _repay_loans() -> void:
	var finished: Array = []
	for l in loans:
		var pay: int = mini(int(l["monthly"]), int(l["owed"]))
		_force_spend(pay, "loan_repayments")
		l["owed"] = int(l["owed"]) - pay
		if int(l["owed"]) <= 0:
			finished.append(l)
	for l in finished:
		loans.erase(l)
		totals["loans_paid"] = int(totals["loans_paid"]) + 1
		notify.emit("%s paid off!" % l["name"])
	loans_changed.emit()


# --- Orders --------------------------------------------------------------------------

func order_supplies(product: String, boxes: int = 1) -> bool:
	var p: Dictionary = Data.PRODUCTS[product]
	var units: int = int(p["box"]) * boxes
	if not spend(int(p["cost"]) * units, "supplies"):
		return false
	pending_orders.append({"product": product, "units": units, "arrives": abs_day + 1})
	notify.emit("Ordered %d x %s, arriving tomorrow" % [units, p["name"]])
	return true


func order_fish(species: String, variety: String, sex: String, stars: int) -> bool:
	if not spend(Data.wholesale_price(species, variety, stars), "fish_orders"):
		return false
	pending_orders.append({"species": species, "variety": variety, "sex": sex, "stars": stars, "units": 1, "arrives": abs_day + 1})
	var f := {"species": species, "variety": variety}
	notify.emit("Ordered a %s %s, arriving tomorrow" % [FishData.full_name(f, Data.SPECIES[species]["name"]), "♂" if sex == "m" else "♀"])
	return true


func units_ordered(product: String) -> int:
	var n := 0
	for o in pending_orders:
		if o.get("product", "") == product:
			n += int(o["units"])
	return n


func _deliver_orders() -> void:
	var still: Array = []
	var stock_came := false
	var arrived: Array = []
	for o in pending_orders:
		if int(o["arrives"]) > abs_day:
			still.append(o)
		elif o.has("product"):
			stockroom[o["product"]] = int(stockroom.get(o["product"], 0)) + int(o["units"])
			stock_came = true
		else:
			for i in int(o["units"]):
				arrived.append(new_fish(o["species"], int(o["stars"]), o.get("variety", ""), o.get("sex", "")))
	pending_orders = still
	if stock_came:
		notify.emit("Supplies delivered to the back room")
		stock_changed.emit()
	if not arrived.is_empty():
		if fish_delivered.get_connections().is_empty():
			fish_storage.append_array(arrived)
			notify.emit("Fish delivered to the back room")
		else:
			fish_delivered.emit(arrived)
		fish_changed.emit()


## Fish ordered from the market that haven't arrived yet.
func fish_on_order() -> int:
	var n := 0
	for o in pending_orders:
		if not o.has("product"):
			n += int(o["units"])
	return n


## Take up to `units` of `product` out of the stockroom; returns how many were taken.
func take_stock(product: String, units: int) -> int:
	var have := int(stockroom.get(product, 0))
	var n := mini(have, units)
	if n > 0:
		stockroom[product] = have - n
		stock_changed.emit()
	return n


# --- Month end -----------------------------------------------------------------------

func set_marketing(id: String) -> void:
	if id == marketing:
		return
	var cost: int = Data.MARKETING[id]["cost"]
	if cost > 0 and not spend(cost, "marketing"):
		return
	marketing = id
	notify.emit("Marketing: " + Data.MARKETING[id]["name"])
	money_changed.emit()


## Showcased tanks are counted by the world and passed in so their upkeep is billed.
var showcase_count := 0


func _end_month() -> void:
	# Bills for the month just finished.
	_force_spend(rent(), "rent")
	if not staff.is_empty():
		_force_spend(wage_bill(), "wages")
	if not loans.is_empty():
		_repay_loans()
	if showcase_count > 0:
		_force_spend(Data.SHOWCASE_UPKEEP * showcase_count, "showcase")
	var report := stats.duplicate(true)
	report["title"] = "%s, Year %d" % [MONTHS[month], year]
	report["balance"] = money
	report["debt"] = total_debt()
	report["reputation"] = reputation
	var income := 0
	for k in report["income"]:
		if k != "loans":  # borrowed money isn't profit
			income += int(report["income"][k])
	var expenses := 0
	for v in report["expenses"].values():
		expenses += int(v)
	report["total_income"] = income
	report["total_expenses"] = expenses
	report["profit"] = income - expenses
	# Operating profit (for goals): leaves out building, expansion and loan repayments.
	var op := income - int(report["income"].get("refunds", 0))
	for k in report["expenses"]:
		if not ["construction", "expansion", "loan_repayments"].has(k):
			op -= int(report["expenses"][k])
	report["operating_profit"] = op
	totals["profit"] = int(totals["profit"]) + op
	last_report = report
	history.append(report)
	day = 1
	month += 1
	if month >= MONTHS.size():
		month = 0
		year += 1
	_reset_stats()
	# Next month's marketing is paid up front.
	if marketing != "":
		var cost: int = Data.MARKETING[marketing]["cost"]
		if money >= cost:
			_force_spend(cost, "marketing")
		else:
			marketing = ""
			notify.emit("Marketing stopped: not enough money")
	month_ended.emit(report)
	autosave_wanted.emit()


## Bills that must be paid even if it takes you into debt.
func _force_spend(amount: int, category: String) -> void:
	money -= amount
	stats["expenses"][category] = int(stats["expenses"].get(category, 0)) + amount
	money_changed.emit()


func _reset_stats() -> void:
	stats = {
		"income": {}, "expenses": {},
		"customers": 0, "happy": 0, "unhappy": 0, "gave_up": 0, "tanks_cleaned": 0, "fish_sold": 0, "items_sold": 0, "fish_bred": 0,
	}



# --- Fish shows -------------------------------------------------------------------------
## A show every SHOW_EVERY days; every 4th is a Grand Show. Enter one adult fish that fits
## the show's class. You compete against five rival breeders who get better as the shows
## go on. Prizes: money for the top three; a win also brings a prize fish, and winning a
## Grand Show unlocks the next locked variety (and gives you a pair of it).

const SHOW_EVERY := 14
const SHOW_CLASSES := {
	"open": {"name": "Open Class", "desc": "Any adult fish"},
	"quality": {"name": "Quality Class", "desc": "3★ or better"},
	"rare": {"name": "Rare Varieties", "desc": "Bred varieties and mutations only"},
	"guppy": {"name": "Guppy Class", "desc": "Guppies only"},
	"goldfish": {"name": "Goldfish Class", "desc": "Goldfish only"},
}
const SHOW_ORDER := ["open", "guppy", "quality", "goldfish", "rare"]
const SHOW_PRIZES := [200, 100, 50]


func next_show_day() -> int:
	return show_number * SHOW_EVERY


func show_class(n: int = -1) -> String:
	if n < 0:
		n = show_number
	return SHOW_ORDER[(n - 1) % SHOW_ORDER.size()]


func is_grand(n: int = -1) -> bool:
	if n < 0:
		n = show_number
	return n % 4 == 0


func show_title(n: int = -1) -> String:
	if n < 0:
		n = show_number
	return ("Grand Show: " if is_grand(n) else "") + SHOW_CLASSES[show_class(n)]["name"]


func can_enter(f: Dictionary, cls: String = "") -> bool:
	if cls == "":
		cls = show_class()
	if not FishData.is_adult(f):
		return false
	match cls:
		"quality":
			return int(f["stars"]) >= 3
		"rare":
			return FishData.variety(f["species"], f["variety"])["kind"] != "common"
		"guppy", "goldfish":
			return f["species"] == cls
	return true


func show_score(f: Dictionary) -> float:
	var v := FishData.variety(f["species"], f["variety"])
	return float(f["stars"]) * 18.0 + float(v["mult"]) * 9.0


## Enter a fish (taken from storage) in the next show; the previous entry goes back.
func enter_show(f: Dictionary) -> void:
	withdraw_show()
	show_entry = f
	notify.emit("Entered in the %s on day %d" % [show_title(), next_show_day()])
	fish_changed.emit()


func withdraw_show() -> void:
	if not show_entry.is_empty():
		fish_storage.append(show_entry)
		show_entry = {}
		fish_changed.emit()


func _run_show() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var n := show_number
	show_number += 1
	var grand := is_grand(n)
	var result := {"title": show_title(n), "grand": grand, "placings": [], "prize": "", "place": 0}
	if show_entry.is_empty():
		notify.emit("The %s went ahead without you" % show_title(n))
		return
	# Rivals improve every show but top out where your best fish (5 stars, a rare variety)
	# can still win a Grand Show.
	var strength := minf(98.0, 64.0 + 2.5 * (n - 1)) + (12.0 if grand else 0.0)
	var entries: Array = []
	var rivals := ["Mabel's Guppies", "Aqua Bros", "Finley Farms", "The Koi Club", "Reef & Co"]
	for r in rivals:
		entries.append({"name": r, "score": strength + rng.randf_range(-18.0, 18.0), "you": false})
	var mine := show_entry
	entries.append({"name": "You: " + fish_label(mine), "score": show_score(mine) + rng.randf_range(-5.0, 5.0), "you": true})
	entries.sort_custom(func(a, b): return a["score"] > b["score"])
	var place := 0
	for i in entries.size():
		if entries[i]["you"]:
			place = i + 1
	result["placings"] = entries
	result["place"] = place
	var prizes: Array[String] = []
	if place <= 3:
		var cash: int = SHOW_PRIZES[place - 1] * (3 if grand else 1)
		earn(cash, "show_prizes")
		prizes.append("$%d" % cash)
		change_reputation([6.0, 3.0, 1.5][place - 1] * (2.0 if grand else 1.0))
		mine["ribbon"] = int(mine.get("ribbon", 0)) + 1
		awards.append({"title": show_title(n), "place": place, "grand": grand, "day": abs_day,
			"fish": FishData.full_name(mine, Data.SPECIES[mine["species"]]["name"])})
		prizes.append("a %s trophy" % ["gold", "silver", "bronze"][place - 1])
	if place == 1:
		totals["shows_won"] = int(totals["shows_won"]) + 1
		if grand:
			totals["grand_won"] = int(totals["grand_won"]) + 1
			var next := _next_locked()
			if not next.is_empty():
				unlocked.append(next[0] + ":" + next[1])
				for sex in ["m", "f"]:
					fish_storage.append(new_fish(next[0], 3, next[1], sex))
				prizes.append("unlocked %s (a pair is in storage)" % FishData.full_name({"species": next[0], "variety": next[1]}, Data.SPECIES[next[0]]["name"]))
		if rng.randf() < 0.6 or grand:
			var gift := _prize_fish(rng)
			fish_storage.append(gift)
			prizes.append("a prize fish: " + fish_label(gift))
	result["prize"] = ", ".join(prizes) if not prizes.is_empty() else "nothing this time"
	# The entry comes home.
	fish_storage.append(mine)
	show_entry = {}
	last_show = result
	fish_changed.emit()
	if place <= 3:
		awards_changed.emit()
	show_result.emit(result)


func _next_locked() -> Array:
	for l in FishData.LOCKED:
		if not unlocked.has(l[0] + ":" + l[1]):
			return l
	return []


## A good fish of a bred (non-common, unlocked) guppy or goldfish variety.
func _prize_fish(rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array = []
	for sp in ["guppy", "goldfish"]:
		for v in FishData.VARIETIES[sp]:
			var d: Dictionary = FishData.VARIETIES[sp][v]
			if d["kind"] == "recipe" and int(d.get("gen", 1)) >= 2 and Genetics.is_unlocked(sp, v, unlocked):
				pool.append([sp, v])
	var pick: Array = pool[rng.randi() % pool.size()]
	return new_fish(pick[0], rng.randi_range(3, 4), pick[1])


func fish_label(f: Dictionary) -> String:
	return Data.fish_label(f)


# --- Goals and achievements -----------------------------------------------------------------

## The world reports these (they live in the scene).
var showcase_peak := 0
## Ids of the "First steps" checklist done so far (see hud.gd FIRST_STEPS).
var first_steps: Array = []


func stat_value(key: String) -> float:
	match key:
		"varieties":
			return discovered.size()
		"plots":
			return owned_plots.size()
		"staff":
			return staff.size()
		"showcases":
			return maxi(showcase_count, showcase_peak)
		"reputation":
			return reputation
		"money":
			return money
	return float(totals.get(key, 0))


func check_goals() -> void:
	showcase_peak = maxi(showcase_peak, showcase_count)
	for a in Goals.ACHIEVEMENTS:
		if not achievements_done.has(a[0]) and stat_value(a[3]) >= float(a[4]):
			achievements_done.append(a[0])
			notify.emit("🏆 Achievement: %s (%s)" % [a[1], a[2]])
			goals_changed.emit()
	while stars_earned < Goals.STARS.size():
		var star: Dictionary = Goals.STARS[stars_earned]
		for g in star["goals"]:
			if stat_value(g[0]) < float(g[1]):
				return
		stars_earned += 1
		earn(int(star["reward"]), "goal_rewards")
		notify.emit("⭐ %s! Reward: $%d" % [star["name"], star["reward"]])
		goals_changed.emit()
