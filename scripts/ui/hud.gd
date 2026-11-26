extends CanvasLayer
## The on-screen interface: top bar (money, date, reputation, speed), the toolbar and its
## panels (Build, Order, Fish, Marketing, Reports), the panel for whatever is selected,
## pop-up messages and the end-of-month report.

const Data := preload("res://scripts/data.gd")
const Tank := preload("res://scripts/world/tank.gd")
const Shelf := preload("res://scripts/world/shelf.gd")
const FishData := preload("res://scripts/fish_data.gd")
const L := preload("res://scripts/world/layout.gd")
const WallAward := preload("res://scripts/world/wall_award.gd")
const Genetics := preload("res://scripts/genetics.gd")
const Goals := preload("res://scripts/goals.gd")
const FishIcon := preload("res://scripts/ui/fish_icon.gd")
const SaveGame := preload("res://scripts/save_game.gd")

const C_PANEL := Color("#16323f")
const C_PANEL2 := Color("#1f4656")
const C_ACCENT := Color("#f5a524")
const C_GOOD := Color("#7ee08a")
const C_BAD := Color("#ff7a6b")
const C_TEXT := Color("#f2f7f8")

var world: Node

var _money: Label
var _date: Label
var _day_bar: ProgressBar
var _rep: Label
var _speed_buttons: Array[Button] = []
var _walls_btn: Button
var _side: PanelContainer  # the left-hand panel (build, order, fish, marketing, reports)
var _side_box: VBoxContainer
var _side_mode := ""
var _build_cat := "Tanks"
var _order_tab := "Supplies"
var _fish_tab := "Storage"
## Fish market picks per species: {"variety", "sex", "stars"}.
var _market := {}
var _modal: PanelContainer
var _sel_panel: PanelContainer
var _sel_box: VBoxContainer
var _status: Label
var _toasts: VBoxContainer
var _report: PanelContainer
var _start: Control
var _refresh_t := 0.0
var _edit_btn: Button
## Pop-ups that open by themselves (month report, show results) wait here while another
## pop-up is open, so they come one at a time.
var _popup_queue: Array = []
var _steps: PanelContainer
var _steps_box: VBoxContainer

## The "First steps" checklist for a new shop: [id, text, reward]. Each pays out once.
const FIRST_STEPS := [
	["keeper", "Hire a Fish Keeper (Staff) so your breeding tank stays clean", 250],
	["bred_on_show", "Put a fish you bred into a display tank (Fish, then click its picture)", 250],
	["goldfish", "Breed your goldfish pair: build a second Breeding Tank and put them in", 250],
	["second_tank", "Build a second display tank in the showroom", 250],
]


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	add_child(root)
	_top_bar(root)
	_toolbar(root)
	_side = _panel(root, Control.PRESET_LEFT_WIDE)
	_side.offset_top = 64
	_side.offset_bottom = -78
	_side.offset_left = 12
	_side.custom_minimum_size.x = 380
	_side_box = _scroll_box(_side)
	_side.visible = false
	_sel_panel = _panel(root, Control.PRESET_RIGHT_WIDE)
	_sel_panel.offset_top = 64
	_sel_panel.offset_bottom = -78
	_sel_panel.offset_right = -12
	_sel_panel.offset_left = -372
	_sel_box = _scroll_box(_sel_panel)
	_sel_panel.visible = false
	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status.offset_top = -112
	_status.offset_bottom = -84
	_status.offset_left = -400
	_status.offset_right = 400
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 6)
	root.add_child(_status)
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toasts.offset_top = 70
	_toasts.offset_left = -260
	_toasts.offset_right = 260
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(_toasts)
	_report = _panel(root, Control.PRESET_CENTER)
	_report.custom_minimum_size = Vector2(460, 0)
	_report.visible = false
	_modal = _panel(root, Control.PRESET_CENTER)
	_modal.custom_minimum_size = Vector2(560, 0)
	_modal.visible = false
	Game.show_result.connect(func(r): _auto_pop(_show_show_result.bind(r)))
	Game.goals_changed.connect(_on_goals_changed)
	Game.money_changed.connect(_update_top)
	Game.speed_changed.connect(_update_top)
	Game.day_passed.connect(_update_top)
	Game.notify.connect(toast)
	Game.month_ended.connect(func(r): _auto_pop(_show_report.bind(r)))
	Game.stock_changed.connect(_refresh_side)
	Game.fish_changed.connect(_refresh_side)
	Game.fish_changed.connect(_refresh_selection)
	Game.staff_changed.connect(_refresh_side)
	Game.loans_changed.connect(_refresh_side)
	Game.plots_changed.connect(_refresh_side)
	Game.money_changed.connect(_on_money_for_bank)
	Game.started.connect(func(): _start.visible = false)
	_steps_panel(root)
	_start_screen(root)
	_start.visible = Game.start_choice == ""
	world.tool.selection_changed.connect(func(_o): _refresh_selection())
	world.tool.mode_changed.connect(_on_tool_mode)
	_update_top()


func _process(delta: float) -> void:
	_day_bar.value = Game.day_fraction() * 100.0
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.5
		_rep.text = "Reputation %d%%" % int(Game.reputation)
		_update_steps()
		if not _popup_queue.is_empty() and not _modal.visible and not _report.visible:
			(_popup_queue.pop_front() as Callable).call()
		if _side_mode == "staff" and _side.visible:
			for n in world.staff_nodes():
				var l := _side_box.find_child("Task%d" % int(n.info["id"]), true, false) as Label
				if l != null:
					l.text = n.task_text()
		if _sel_panel.visible:
			var info := _sel_box.get_node_or_null("Info") as Label
			var sel: Node = world.tool.selected
			if info != null and sel != null and is_instance_valid(sel):
				info.text = sel.info_text()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _start.visible:
		get_viewport().set_input_as_handled()
		return
	match (event as InputEventKey).physical_keycode:
		KEY_SPACE:
			Game.set_speed(1 if Game.speed == 0 else 0)
		KEY_1:
			Game.set_speed(1)
		KEY_2:
			Game.set_speed(2)
		KEY_3:
			Game.set_speed(3)
		KEY_M:
			world.tool.toggle_edit()
		KEY_B:
			_open("build")
		KEY_O:
			_open("order")
		KEY_F:
			_open("fish")
		KEY_H:
			_open("staff")
		KEY_G:
			_open("goals")
		KEY_V:
			_toggle_walls()
		KEY_F5:
			world.save_game()
		KEY_F9:
			if SaveGame.exists(SaveGame.MANUAL):
				world.load_game()
		KEY_ESCAPE:
			if _modal.visible:
				_modal.visible = false
			elif _report.visible:
				_report.visible = false
			elif not world.tool.is_busy():
				_side.visible = false
				_side_mode = ""


# --- Top bar and toolbar -----------------------------------------------------------------

func _on_tool_mode() -> void:
	_status.text = world.tool.status_text()
	_edit_btn.set_pressed_no_signal(world.tool.edit_mode)
	if world.tool.edit_mode:
		_sel_panel.visible = false


func _auto_pop(show: Callable) -> void:
	if _modal.visible or _report.visible:
		_popup_queue.append(show)
	else:
		show.call()


# --- First steps checklist ----------------------------------------------------------------

func _steps_panel(root: Control) -> void:
	_steps = _panel(root, Control.PRESET_TOP_LEFT)
	_steps.offset_left = 12
	_steps.offset_top = 70
	_steps.custom_minimum_size = Vector2(330, 0)
	_steps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_steps_box = VBoxContainer.new()
	_steps_box.add_theme_constant_override("separation", 4)
	_steps.add_child(_steps_box)
	_steps.visible = false


func _step_done(id: String) -> bool:
	var shows: Array = world.objects().filter(func(o): return o is Tank and o.room() == "show" and not o.is_breeding())
	match id:
		"keeper":
			return Game.staff_count("keeper") > 0
		"bred_on_show":
			for t in shows:
				for f in t.fish:
					if f.get("bred", false):
						return true
		"goldfish":
			for o in world.objects():
				if o is Tank and o.is_breeding():
					var p: Dictionary = o.breeding_plan()
					if p["ok"] and p["species"] == "goldfish":
						return true
		"second_tank":
			return shows.size() >= 2
	return false


func _update_steps() -> void:
	if Game.first_steps.size() >= FIRST_STEPS.size():
		_steps.visible = false
		return
	for s in FIRST_STEPS:
		if not Game.first_steps.has(s[0]) and _step_done(s[0]):
			Game.finish_step(s[0], s[1].get_slice(" (", 0).get_slice(":", 0), int(s[2]))
			if Game.first_steps.size() >= FIRST_STEPS.size():
				toast("All first steps done. Your shop is up and running!")
	_steps.visible = Game.first_steps.size() < FIRST_STEPS.size() and not _side.visible and not _start.visible
	if not _steps.visible:
		return
	var key := str(Game.first_steps) + str(Game.steps_minimized)
	if _steps.get_meta("key", "") == key:
		return
	_steps.set_meta("key", key)
	_clear(_steps_box)
	var head := HBoxContainer.new()
	_steps_box.add_child(head)
	var h := Label.new()
	h.text = "First steps" + ("  %d/%d" % [Game.first_steps.size(), FIRST_STEPS.size()] if Game.steps_minimized else "")
	h.add_theme_color_override("font_color", C_ACCENT)
	h.add_theme_font_size_override("font_size", 17)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h)
	var fold := _button(head, "+" if Game.steps_minimized else "–", func():
		Game.steps_minimized = not Game.steps_minimized
		_update_steps())
	fold.tooltip_text = "Show the checklist" if Game.steps_minimized else "Minimize the checklist"
	fold.custom_minimum_size = Vector2(30, 26)
	_steps.custom_minimum_size.x = 0 if Game.steps_minimized else 330
	if Game.steps_minimized:
		_steps.reset_size()
		return
	for s in FIRST_STEPS:
		var done: bool = Game.first_steps.has(s[0])
		var l := Label.new()
		l.text = "%s %s  +$%d" % ["✔" if done else "☐", s[1], s[2]]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 310
		l.add_theme_font_size_override("font_size", 13)
		if done:
			l.add_theme_color_override("font_color", Color(C_GOOD, 0.7))
		_steps_box.add_child(l)
	_steps.reset_size()


func _top_bar(root: Control) -> void:
	var bar := _panel(root, Control.PRESET_TOP_WIDE)
	bar.offset_left = 12
	bar.offset_right = -12
	bar.offset_top = 8
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	bar.add_child(h)
	var title := Label.new()
	title.text = "Fig Tree Fish Store"
	title.add_theme_color_override("font_color", C_ACCENT)
	title.add_theme_font_size_override("font_size", 20)
	h.add_child(title)
	_money = Label.new()
	_money.add_theme_font_size_override("font_size", 20)
	h.add_child(_money)
	var datebox := VBoxContainer.new()
	datebox.add_theme_constant_override("separation", 0)
	_date = Label.new()
	datebox.add_child(_date)
	_day_bar = ProgressBar.new()
	_day_bar.show_percentage = false
	_day_bar.custom_minimum_size = Vector2(180, 5)
	datebox.add_child(_day_bar)
	h.add_child(datebox)
	_rep = Label.new()
	_rep.mouse_filter = Control.MOUSE_FILTER_PASS
	_rep.tooltip_text = "Settles at the share of customers who leave happy.
New varieties and show wins lift it for a while."
	h.add_child(_rep)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	_button(h, "Menu", _game_menu)
	_walls_btn = _button(h, "Walls: auto", _toggle_walls)
	for i in 4:
		var b := _button(h, ["❚❚", "▶", "▶▶", "▶▶▶"][i], func(): Game.set_speed(i))
		b.toggle_mode = true
		b.custom_minimum_size.x = 52
		_speed_buttons.append(b)


func _toolbar(root: Control) -> void:
	var bar := _panel(root, Control.PRESET_CENTER_BOTTOM)
	bar.offset_bottom = -10
	bar.offset_top = -70
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	bar.add_child(h)
	_edit_btn = _button(h, "Edit (M)", func(): world.tool.toggle_edit())
	_edit_btn.toggle_mode = true
	_edit_btn.custom_minimum_size = Vector2(104, 44)
	_edit_btn.tooltip_text = "Edit mode: click things to pick them up and move them"
	for spec in [["Build (B)", "build"], ["Order (O)", "order"], ["Fish (F)", "fish"], ["Show", "show"], ["Staff (H)", "staff"], ["Expand", "expand"], ["Bank", "bank"], ["Marketing", "marketing"], ["Goals (G)", "goals"], ["Reports", "reports"]]:
		var b := _button(h, spec[0], _open.bind(spec[1]))
		b.custom_minimum_size = Vector2(104, 44)


func _update_top() -> void:
	_money.text = "$%s" % _commas(Game.money)
	_money.add_theme_color_override("font_color", C_GOOD if Game.money >= 0 else C_BAD)
	_date.text = Game.date_text()
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(i == Game.speed)
	if _side_mode == "build":
		_refresh_side()


func _toggle_walls() -> void:
	world.walls_down = not world.walls_down
	_walls_btn.text = "Walls: down" if world.walls_down else "Walls: auto"


# --- Left panel -------------------------------------------------------------------------

func _open(mode: String) -> void:
	if _side.visible and _side_mode == mode:
		_side.visible = false
		_side_mode = ""
		return
	_side_mode = mode
	_side.visible = true
	_refresh_side()


func _refresh_side() -> void:
	if not _side.visible:
		return
	_clear(_side_box)
	match _side_mode:
		"build":
			_build_panel()
		"order":
			_order_panel()
		"fish":
			_fish_panel()
		"staff":
			_staff_panel()
		"bank":
			_bank_panel()
		"expand":
			_expand_panel()
		"show":
			_show_panel()
		"goals":
			_goals_panel()
		"marketing":
			_marketing_panel()
		"reports":
			_reports_panel()


func _build_panel() -> void:
	_heading(_side_box, "Build")
	var tabs := HFlowContainer.new()
	_side_box.add_child(tabs)
	for cat in Data.CATEGORIES:
		var b := _button(tabs, cat, func():
			_build_cat = cat
			_refresh_side())
		b.toggle_mode = true
		b.set_pressed_no_signal(cat == _build_cat)
	for id in Data.ITEMS:
		var def: Dictionary = Data.ITEMS[id]
		if def["cat"] != _build_cat:
			continue
		var row := HBoxContainer.new()
		_side_box.add_child(row)
		var b := _button(row, "%s   $%d" % [def["name"], def["cost"]], func(): world.tool.start_place(id))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not Game.can_afford(int(def["cost"]))
		b.tooltip_text = _item_blurb(def)
		_small(_side_box, _item_blurb(def))
	_small(_side_box, "\nClick to place, R to turn, right click to stop.\nClick anything you've built to move, turn or sell it.")


func _item_blurb(def: Dictionary) -> String:
	var rooms := " / ".join(PackedStringArray(def["rooms"].map(func(r): return L.room_name(r).capitalize() if r != "hall" else "Hall of Fame")))
	match def["kind"]:
		"tank":
			return "Holds %d fish. Base appeal %d. %s" % [def["capacity"], int(def["appeal"]), rooms]
		"breeding":
			return "Breeds a pair of fish into fry. %s only" % rooms
		"holding":
			return "Holds %d fish. Fish you buy from the market arrive here; nothing breeds in it. %s only" % [def["capacity"], rooms]
		"shelf":
			return "Sells one supply, holds %d. %s" % [def["capacity"], rooms]
		"counter":
			return "Customers pay here. %s" % rooms
		"trophies":
			return "Shows up to 9 of your fish show trophies; each adds prestige. %s only" % rooms
		_:
			if float(def.get("appeal", 0.0)) > 0.0:
				return "+%d appeal to tanks nearby. %s" % [int(def["appeal"]), rooms]
			return rooms


func _order_panel() -> void:
	_heading(_side_box, "Order")
	var tabs := HBoxContainer.new()
	_side_box.add_child(tabs)
	for tab in ["Supplies", "Fish"]:
		var b := _button(tabs, tab, func():
			_order_tab = tab
			_refresh_side())
		b.toggle_mode = true
		b.set_pressed_no_signal(tab == _order_tab)
	if _order_tab == "Supplies":
		_small(_side_box, "Boxes arrive in the back room tomorrow; shelves fill themselves from there.")
		for id in Data.PRODUCTS:
			var p: Dictionary = Data.PRODUCTS[id]
			var box := _card(_side_box)
			var on_shelves := 0
			for o in world.objects():
				if o is Shelf:
					on_shelves += o.units_of(id)
			var l := Label.new()
			l.text = "%s  (sells $%d)\nStockroom %d · on shelves %d · coming %d" % [
				p["name"], p["price"], int(Game.stockroom.get(id, 0)), on_shelves, Game.units_ordered(id)]
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.add_child(l)
			var cost: int = int(p["cost"]) * int(p["box"])
			var b := _button(box, "Box of %d\n$%d" % [p["box"], cost], func(): Game.order_supplies(id))
			b.disabled = not Game.can_afford(cost)
	else:
		_small(_side_box, "The fish market delivers adults tomorrow, into your holding tank in the back room. Market fish cost more than customers pay: the money is in breeding them.")
		var space: int = world.holding_space()
		var hl := Label.new()
		if world.holding_tanks().is_empty():
			hl.text = "No holding tank: deliveries will wait in storage. Build one (Tanks)."
		else:
			hl.text = "Holding tank space: %d free%s" % [maxi(space, 0), "  (%d on order)" % Game.fish_on_order() if Game.fish_on_order() > 0 else ""]
			if space <= 0:
				hl.text += ". Full: more fish will wait in storage."
		hl.add_theme_color_override("font_color", C_BAD if space <= 0 else C_GOOD)
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_side_box.add_child(hl)
		for sp in FishData.MARKET:
			if not _market.has(sp):
				_market[sp] = {"variety": FishData.MARKET[sp][0], "sex": "f", "stars": 2}
			var pick: Dictionary = _market[sp]
			var card := PanelContainer.new()
			card.theme_type_variation = "CardPanel"
			_side_box.add_child(card)
			var v := VBoxContainer.new()
			card.add_child(v)
			var top := HBoxContainer.new()
			v.add_child(top)
			top.add_child(FishIcon.make({"species": sp, "variety": pick["variety"], "sex": pick["sex"], "stars": pick["stars"]}))
			var name_l := Label.new()
			name_l.text = Data.SPECIES[sp]["name"]
			name_l.add_theme_font_size_override("font_size", 17)
			top.add_child(name_l)
			var row := HBoxContainer.new()
			v.add_child(row)
			var vsel := OptionButton.new()
			vsel.focus_mode = Control.FOCUS_NONE
			for vid in FishData.MARKET[sp]:
				var vn: String = FishData.variety(sp, vid)["name"]
				vsel.add_item(vn if vn != "" else Data.SPECIES[sp]["name"])
				if vid == pick["variety"]:
					vsel.select(vsel.item_count - 1)
			vsel.item_selected.connect(func(i):
				pick["variety"] = FishData.MARKET[sp][i]
				_refresh_side())
			row.add_child(vsel)
			for sx in ["m", "f"]:
				var sb := _button(row, "♂" if sx == "m" else "♀", func():
					pick["sex"] = sx
					_refresh_side())
				sb.toggle_mode = true
				sb.set_pressed_no_signal(pick["sex"] == sx)
			for st in [1, 2, 3]:
				var tb := _button(row, "★".repeat(st), func():
					pick["stars"] = st
					_refresh_side())
				tb.toggle_mode = true
				tb.set_pressed_no_signal(pick["stars"] == st)
			var cost := Data.wholesale_price(sp, pick["variety"], int(pick["stars"]))
			var buy := _button(v, "Buy for $%d   (customers pay ~$%d)" % [cost, Data.fish_price({"species": sp, "variety": pick["variety"], "stars": pick["stars"]})],
				func(): Game.order_fish(sp, pick["variety"], pick["sex"], int(pick["stars"])))
			buy.disabled = not Game.can_afford(cost)


func _fish_panel() -> void:
	var tabs := HBoxContainer.new()
	_side_box.add_child(tabs)
	for tab in ["Storage", "Breeding book"]:
		var b := _button(tabs, tab, func():
			_fish_tab = tab
			_refresh_side())
		b.toggle_mode = true
		b.set_pressed_no_signal(tab == _fish_tab)
	if _fish_tab == "Breeding book":
		_book_panel()
		return
	_heading(_side_box, "Fish storage (back room)")
	if Game.fish_storage.is_empty():
		_small(_side_box, "No fish waiting. Order some, or breed them in a breeding tank.")
	_small(_side_box, "Click a fish's picture for a closer look and to put it in a tank. Fry grow up in %d days." % FishData.ADULT_AGE)
	_market_sell_row()
	var sorted := Game.fish_storage.duplicate()
	sorted.sort_custom(func(a, b): return _fish_sort(a) < _fish_sort(b))
	for f in sorted:
		var r := _card(_side_box)
		r.add_child(_fish_pic(f))
		var l := Label.new()
		l.text = Data.fish_label(f) + ("" if not FishData.is_adult(f) else "\n$%d" % Data.fish_price(f))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		if Game.can_enter(f):
			_button(r, "Enter\nshow", func():
				Game.enter_show(Game.take_stored_fish(int(f["id"])))
				_refresh_side())


## Bulk-sell surplus grown fish to the market by quality (never 4-5 stars; the best
## male and female of each variety and anything with a ribbon stay).
func _market_sell_row() -> void:
	var any := false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for max_stars in [1, 2, 3]:
		var fish: Array = Game.market_surplus(max_stars)
		if fish.is_empty():
			continue
		any = true
		var total := 0
		for f in fish:
			total += Data.market_buy_price(f)
		var b := _button(row, "%s
%d fish, $%d" % ["1★" if max_stars == 1 else "1–%d★" % max_stars, fish.size(), total], func():
			var got := 0
			for f in fish:
				got += Game.sell_to_market(int(f["id"]))
			toast("Sold %d fish to the market for $%d" % [fish.size(), got])
			_refresh_side())
		b.tooltip_text = "Sell these to the fish market at %d%% of the shop price" % int(Data.MARKET_BUY_MULT * 100)
	if not any:
		row.queue_free()
		return
	_heading(_side_box, "Too many fish? Sell to the market", 15)
	_small(_side_box, "The market pays %d%% of the shop price. It keeps back your best ♂ and ♀ of each variety and any show winners." % int(Data.MARKET_BUY_MULT * 100))
	_side_box.add_child(row)


func _fish_sort(f: Dictionary) -> String:
	return "%s|%s|%d|%s" % [f["species"], f["variety"], 9 - int(f["stars"]), f["sex"]]


## Every variety: bred ones in colour, recipes you could try as hints, locked ones marked.
func _book_panel() -> void:
	_heading(_side_box, "Breeding book")
	_small(_side_box, "%d new varieties bred. Mutations are a %d%% chance in any brood; recipes work %d%% of the time." % [
		Game.discovered.size(), int(FishData.MUTATION_CHANCE * 100.0), int(FishData.RECIPE_CHANCE * 100.0)])
	for sp in ["guppy", "goldfish"]:
		_heading(_side_box, Data.SPECIES[sp]["name"], 17)
		var flow := HFlowContainer.new()
		_side_box.add_child(flow)
		for vid in FishData.VARIETIES[sp]:
			var v: Dictionary = FishData.VARIETIES[sp][vid]
			var known: bool = v["kind"] == "common" or Game.discovered.has(sp + ":" + vid)
			var locked := not Genetics.is_unlocked(sp, vid, Game.unlocked)
			var cell := VBoxContainer.new()
			cell.custom_minimum_size.x = 104
			flow.add_child(cell)
			if known:
				cell.add_child(FishIcon.make({"species": sp, "variety": vid, "sex": "m", "stars": 3}))
			else:
				var q := Label.new()
				q.text = "🔒" if locked else "?"
				q.add_theme_font_size_override("font_size", 22)
				q.custom_minimum_size = Vector2(58, 34)
				cell.add_child(q)
			var hint := ""
			if known:
				hint = v["name"]
			elif locked:
				hint = "%s\nWin a Grand Show" % v["name"]
			elif v["kind"] == "mutation":
				hint = "Mutation"
			else:
				for r in FishData.RECIPES[sp]:
					if r[2] == vid:
						hint = "%s × %s" % [FishData.variety(sp, r[0])["name"], FishData.variety(sp, r[1])["name"]]
			var l := Label.new()
			l.text = hint
			l.add_theme_font_size_override("font_size", 12)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cell.add_child(l)


func _staff_panel() -> void:
	_heading(_side_box, "Staff")
	_small(_side_box, "Wages this month: $%d (paid at the end of the month)." % Game.wage_bill())
	if Game.staff.is_empty():
		_small(_side_box, "Nobody works here yet.")
	var nodes := {}
	for n in world.staff_nodes():
		nodes[int(n.info["id"])] = n
	for person in Game.staff:
		var r: Dictionary = Data.STAFF[person["role"]]
		var box := _card(_side_box)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 0)
		box.add_child(v)
		var name_l := Label.new()
		name_l.text = "%s  ·  %s  ·  $%d/mo" % [person["name"], r["name"], person["wage"]]
		name_l.add_theme_color_override("font_color", r["color"])
		v.add_child(name_l)
		var task := Label.new()
		task.name = "Task%d" % int(person["id"])
		task.add_theme_font_size_override("font_size", 13)
		task.add_theme_color_override("font_color", Color("#a9c6cf"))
		var node: Node = nodes.get(int(person["id"]))
		task.text = node.task_text() if node != null else ""
		v.add_child(task)
		var id := int(person["id"])
		var who: Node = node
		_button(box, "Find", func():
			if who != null and is_instance_valid(who):
				world.rig.look_at_point(who.global_position))
		_button(box, "Fire", func(): Game.fire(id))
	_heading(_side_box, "Hire", 16)
	for role in Data.STAFF:
		var r: Dictionary = Data.STAFF[role]
		var b := _button(_side_box, "Hire %s   $%d/month" % [r["name"], r["wage"]], func(): Game.hire(role))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_small(_side_box, r["desc"])


func _on_goals_changed() -> void:
	if _side_mode == "goals":
		_refresh_side()


func _on_money_for_bank() -> void:
	if _side_mode == "bank" or _side_mode == "expand":
		_refresh_side()


func _expand_panel() -> void:
	_heading(_side_box, "Expand the shop")
	_small(_side_box, "Buy plots to grow the shop (the grids on the grass). Rent is now $%d a month." % Game.rent())
	for id in Data.PLOTS:
		var p: Dictionary = Data.PLOTS[id]
		var box := _card(_side_box)
		var lab := Label.new()
		lab.text = "%s\n%s\n+$%d rent a month" % [p["name"], p["desc"], p["rent"]]
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(lab)
		if id == "hall" and Game.owned_plots.has(id):
			lab.text += "\nPrestige %d: +%d%% customers" % [world.hall_prestige(), int(world.hall_bonus() * 100.0)]
		if Game.owned_plots.has(id):
			var done := Label.new()
			done.text = "Owned"
			done.add_theme_color_override("font_color", C_GOOD)
			box.add_child(done)
		else:
			var b := _button(box, "Buy\n$%s" % _commas(int(p["cost"])), func(): Game.buy_plot(id))
			b.disabled = not Game.can_afford(int(p["cost"]))
	_button(_side_box, "Look at the plots", func(): world.rig.look_at_point(Vector3(0, 0, 4), 42.0, 20.0))


func _bank_panel() -> void:
	_heading(_side_box, "Bank")
	if Game.loans.is_empty():
		_small(_side_box, "You don't owe the bank anything.")
	else:
		_small(_side_box, "Repayments come out at the end of every month. Total owed: $%s" % _commas(Game.total_debt()))
	for l in Game.loans:
		var box := _card(_side_box)
		var lab := Label.new()
		var months := int(ceil(float(l["owed"]) / float(l["monthly"])))
		lab.text = "%s ($%s)
$%s left · $%s/month · %d months to go" % [
			l["name"], _commas(int(l["amount"])), _commas(int(l["owed"])), _commas(int(l["monthly"])), months]
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(lab)
		var id := int(l["id"])
		var b := _button(box, "Pay off
$%s" % _commas(int(l["owed"])), func(): Game.pay_off(id))
		b.disabled = not Game.can_afford(int(l["owed"]))
	_heading(_side_box, "Borrow more", 16)
	var left := Data.EXTRA_LOANS - Game.extra_loans_taken
	if left <= 0:
		_small(_side_box, "The bank won't lend you any more.")
		return
	if Game.months_until_loan() > 0:
		_small(_side_box, "The bank wants to see %d more month%s of trading before it lends to you." % [
			Game.months_until_loan(), "" if Game.months_until_loan() == 1 else "s"])
	else:
		_small(_side_box, "You can take out %d more loan%s." % [left, "" if left == 1 else "s"])
	for id in Data.LOANS:
		var l: Dictionary = Data.LOANS[id]
		var b := _button(_side_box, "%s: get $%s, pay $%s/month for %d months" % [
			l["name"], _commas(int(l["amount"])), _commas(Game.loan_monthly(id)), l["months"]], func(): Game.take_loan(id))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not Game.can_take_loan()


# --- Start screen ----------------------------------------------------------------------------

func _start_screen(root: Control) -> void:
	_start = ColorRect.new()
	(_start as ColorRect).color = Color(0.03, 0.08, 0.11, 0.55)
	_start.set_anchors_preset(Control.PRESET_FULL_RECT)
	_start.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_start)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_start.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	_heading(v, "Fig Tree Fish Store", 30)
	_small(v, "You've taken on an empty-ish fish shop with $%s of savings, a cashier and a stocker. How do you want to start?" % _commas(Data.START_MONEY))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	for id in Data.STARTS:
		var st: Dictionary = Data.STARTS[id]
		var card := PanelContainer.new()
		card.theme_type_variation = "CardPanel"
		card.custom_minimum_size = Vector2(250, 0)
		row.add_child(card)
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", 6)
		card.add_child(c)
		_heading(c, st["name"], 20)
		var loan: String = st["loan"]
		var cash := Data.START_MONEY + (int(Data.LOANS[loan]["amount"]) if loan != "" else 0)
		var money := Label.new()
		money.text = "Start with $%s" % _commas(cash)
		money.add_theme_color_override("font_color", C_GOOD)
		money.add_theme_font_size_override("font_size", 18)
		c.add_child(money)
		if loan != "":
			var l: Dictionary = Data.LOANS[loan]
			_small(c, "Loan of $%s at %d%% interest.
Pay back $%s a month for %d months ($%s in all)." % [
				_commas(int(l["amount"])), int(float(l["interest"]) * 100.0), _commas(Game.loan_monthly(loan)),
				l["months"], _commas(Game.loan_total_owed(loan))])
		else:
			_small(c, "No loan, nothing to pay back.
")
		_small(c, st["desc"])
		var gap := Control.new()
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.add_child(gap)
		var b := _button(c, "Start", func(): Game.choose_start(id))
		b.custom_minimum_size.y = 40
	for spec in [[SaveGame.MANUAL, "Continue saved game"], [SaveGame.AUTO, "Continue from autosave"]]:
		var desc := SaveGame.describe(spec[0])
		if desc != "":
			var cb := _button(v, "%s   (%s)" % [spec[1], desc], func(): world.load_game(spec[0]))
			cb.custom_minimum_size.y = 36
	_small(v, "Whichever you pick, the bank will consider lending you more (up to %d more loans) once you've traded for %d months." % [Data.EXTRA_LOANS, Data.LOAN_WAIT_MONTHS])


func _marketing_panel() -> void:
	_heading(_side_box, "Marketing")
	_small(_side_box, "Brings more customers. Paid each month while it runs.")
	for id in Data.MARKETING:
		var m: Dictionary = Data.MARKETING[id]
		var text: String = m["name"] if id == "" else "%s   $%d/month   +%d%% customers" % [m["name"], m["cost"], int(float(m["boost"]) * 100.0)]
		var b := _button(_side_box, text, func(): Game.set_marketing(id); _refresh_side())
		b.toggle_mode = true
		b.set_pressed_no_signal(Game.marketing == id)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_small(_side_box, "\nShowcase a tank (select it) to light it up: appeal x%.1f, $%d/month each." % [Data.SHOWCASE_MULT, Data.SHOWCASE_UPKEEP])
	_small(_side_box, "Customers right now: about %.1fx a plain shop." % world.customer_rate())


func _reports_panel() -> void:
	_heading(_side_box, "Reports")
	if Game.history.is_empty():
		_small(_side_box, "Your first monthly report comes at the end of %s." % Game.MONTHS[Game.month])
	_small(_side_box, "This month so far: %d customers, %d fish and %d supplies sold." % [
		Game.stats["customers"], Game.stats["fish_sold"], Game.stats["items_sold"]])
	for i in range(Game.history.size() - 1, -1, -1):
		var r: Dictionary = Game.history[i]
		_button(_side_box, "%s   profit $%s" % [r["title"], _commas(int(r["profit"]))], _show_report.bind(r))


# --- Selected object ---------------------------------------------------------------------

func _refresh_selection() -> void:
	var obj: Node = world.tool.selected
	if obj == null or not is_instance_valid(obj):
		_sel_panel.visible = false
		return
	_sel_panel.visible = true
	_clear(_sel_box)
	_heading(_sel_box, obj.display_name())
	var info := Label.new()
	info.name = "Info"
	info.text = obj.info_text()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sel_box.add_child(info)
	var row := HBoxContainer.new()
	_sel_box.add_child(row)
	_button(row, "Move", func(): world.tool.start_move(obj))
	_button(row, "Turn", func():
		var old: int = obj.rot
		obj.set_rot(old + 1)
		if not world.can_place(obj.item_id, obj.rect(), obj)["ok"]:
			obj.set_rot(old)
			toast("No room to turn it there")
		else:
			world.objects_changed())
	_button(row, "Sell ($%d)" % obj.refund(), func(): world.sell(obj))
	if obj is Tank:
		_tank_section(obj)
	elif obj is Shelf:
		_shelf_section(obj)


func _tank_section(tank: Node) -> void:
	if not tank.is_breeding() and not tank.is_holding() and not tank.in_hall():
		var sc := CheckButton.new()
		sc.text = "Showcase ($%d/month)" % Data.SHOWCASE_UPKEEP
		sc.button_pressed = tank.showcase
		sc.toggled.connect(func(on):
			tank.set_showcase(on)
			world.objects_changed()
			_refresh_selection())
		_sel_box.add_child(sc)
	if tank.is_breeding():
		_button(_sel_box, "Breeding forecast", func(): _breeding_forecast(tank))
	_heading(_sel_box, "In this tank (%d/%d)" % [tank.fish.size(), tank.capacity()], 16)
	_small(_sel_box, "Click a fish's picture for a closer look.")
	for f in tank.fish:
		var r := _card(_sel_box)
		r.add_child(_fish_pic(f))
		var l := Label.new()
		var price := "" if tank.is_breeding() or tank.is_holding() or tank.in_hall() or not FishData.is_adult(f) else "\n$%d" % tank.price_of(f)
		l.text = Data.fish_label(f) + price
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		_button(r, "Take\nout", func():
			Game.store_fish(tank.remove_fish(int(f["id"])))
			_refresh_selection())
	_heading(_sel_box, "Add from storage", 16)
	if Game.fish_storage.is_empty():
		_small(_sel_box, "Storage is empty. Order fish or breed them.")
	var full: bool = tank.fish.size() >= tank.capacity()
	var sorted := Game.fish_storage.duplicate()
	sorted.sort_custom(func(a, b): return _fish_sort(a) < _fish_sort(b))
	for f in sorted:
		var r := _card(_sel_box)
		r.add_child(_fish_pic(f, tank))
		var l := Label.new()
		l.text = Data.fish_label(f)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		var b := _button(r, "Put\nin", func():
			var got := Game.take_stored_fish(int(f["id"]))
			if not got.is_empty() and not tank.add_fish(got):
				Game.store_fish(got)
			_refresh_selection()
			if tank.is_breeding():
				_breeding_forecast(tank))
		b.disabled = full


## Pop-up: who is in the breeding tank, how well they'll spawn, and what the babies may be.
func _breeding_forecast(tank: Node) -> void:
	_clear(_modal)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_modal.add_child(v)
	_heading(v, "Breeding forecast", 22)
	var p: Dictionary = tank.breeding_plan()
	var parents := GridContainer.new()
	parents.columns = 6
	v.add_child(parents)
	for f in tank.fish:
		var cell := VBoxContainer.new()
		cell.add_child(_fish_pic(f, null, Vector2(76, 44)))
		var l := Label.new()
		l.text = "%s\n%s" % [FishData.full_name(f, Data.SPECIES[f["species"]]["name"]), Data.stars_text(int(f["stars"])) if FishData.is_adult(f) else "fry"]
		l.add_theme_font_size_override("font_size", 12)
		cell.add_child(l)
		parents.add_child(cell)
	if p["ok"]:
		var info := Label.new()
		info.text = "%d ♂ : %d ♀  →  %d brood%s of %d-%d fry every %d days" % [p["males"].size(), p["females"].size(), p["broods"],
			"" if p["broods"] == 1 else "s", Genetics.BROOD_SIZE.x, Genetics.BROOD_SIZE.y, Data.BREED_DAYS]
		info.add_theme_color_override("font_color", C_GOOD)
		v.add_child(info)
	_small(v, p["note"])
	if p["ok"]:
		# Average the baby odds over every mother x father pairing.
		var total := {}
		var pairs := 0
		var lo := 5
		var hi := 1
		for mo in p["females"]:
			for fa in p["males"]:
				pairs += 1
				for o in Genetics.odds(p["species"], mo["variety"], fa["variety"], Game.unlocked):
					total[o[0]] = float(total.get(o[0], 0.0)) + float(o[1])
				var avg := roundi((float(mo["stars"]) + float(fa["stars"])) * 0.5)
				lo = mini(lo, maxi(1, avg - 1))
				hi = maxi(hi, mini(5, avg + 1))
		_heading(v, "Possible babies (%d★ to %d★)" % [lo, hi], 16)
		var rows: Array = []
		var unknown_mut := 0.0
		for k in total:
			var kv: Dictionary = FishData.variety(p["species"], k)
			if kv["kind"] == "mutation" and not Game.discovered.has(p["species"] + ":" + k):
				unknown_mut += float(total[k]) / pairs
			else:
				rows.append([k, float(total[k]) / pairs])
		if unknown_mut > 0.0:
			rows.append(["?mutation", unknown_mut])
		rows.sort_custom(func(a, b): return a[1] > b[1])
		var flow := GridContainer.new()
		flow.columns = 5
		v.add_child(flow)
		for r in rows:
			var cell := VBoxContainer.new()
			cell.custom_minimum_size.x = 96
			var vk: Dictionary = {"name": "", "kind": "mutation"} if r[0] == "?mutation" else FishData.variety(p["species"], r[0])
			var known: bool = r[0] != "?mutation" and (vk["kind"] == "common" or Game.discovered.has(p["species"] + ":" + r[0]))
			if known:
				cell.add_child(FishIcon.make({"species": p["species"], "variety": r[0], "sex": "m", "stars": 3}, Vector2(76, 44)))
			else:
				var q := Label.new()
				q.text = "?"
				q.add_theme_font_size_override("font_size", 26)
				q.custom_minimum_size = Vector2(76, 44)
				cell.add_child(q)
			var l := Label.new()
			var pct := float(r[1]) * 100.0
			l.text = "%s\n%s%%" % [vk["name"] if known else ("A mutation" if vk["kind"] == "mutation" else "Something new!"),
				("%.1f" % pct) if pct < 10.0 else str(roundi(pct))]
			l.add_theme_font_size_override("font_size", 12)
			cell.add_child(l)
			flow.add_child(cell)
	_small(v, "Clean water gives better odds of a higher star rating. Babies are 50/50 male or female.")
	var ok := _button(v, "Close", func(): _modal.visible = false)
	ok.custom_minimum_size.y = 36
	_pop(_modal)


## A fish's picture you can click for a closer look (`for_tank`: the tank being filled,
## so the close-up offers it first).
func _fish_pic(f: Dictionary, for_tank: Node = null, size: Vector2 = Vector2(58, 34)) -> Control:
	var icon := FishIcon.make(f, size)
	icon.mouse_filter = Control.MOUSE_FILTER_STOP
	icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	icon.tooltip_text = "Click for a closer look"
	var id := int(f["id"])
	icon.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_fish_details(id, for_tank))
	return icon


## Where a fish is: [fish, tank] (tank null when it's in storage), or [] if it's gone.
func _find_fish(id: int) -> Array:
	for f in Game.fish_storage:
		if int(f["id"]) == id:
			return [f, null]
	for o in world.objects():
		if o is Tank:
			for f in o.fish:
				if int(f["id"]) == id:
					return [f, o]
	return []


## "Medium Tank 2 (showroom)": tanks are numbered when there's more than one of a kind.
func _tank_name(tank: Node) -> String:
	var same := 0
	var n := 0
	for o in world.objects():
		if o is Tank and o.item_id == tank.item_id:
			same += 1
			if o == tank:
				n = same
	var name: String = tank.display_name() + (" %d" % n if same > 1 else "")
	return "%s (%s)" % [name, L.room_name(tank.room())]


## Pop-up: a big picture of the fish, everything about it, and where it can go.
func _fish_details(id: int, for_tank: Node = null) -> void:
	var found := _find_fish(id)
	if found.is_empty():
		_modal.visible = false
		return
	var f: Dictionary = found[0]
	var home: Node = found[1]
	var sp: Dictionary = Data.SPECIES[f["species"]]
	var v: Dictionary = FishData.variety(f["species"], f.get("variety", ""))
	var adult := FishData.is_adult(f)
	var fname := FishData.full_name(f, sp["name"])
	_clear(_modal)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_modal.add_child(box)
	_heading(box, fname, 24)
	var pic_bg := PanelContainer.new()
	pic_bg.theme_type_variation = "CardPanel"
	box.add_child(pic_bg)
	pic_bg.add_child(FishIcon.make(f, Vector2(500, 250)))
	var stars := Label.new()
	stars.text = Data.stars_text(int(f["stars"])) if adult else "Fry"
	stars.add_theme_font_size_override("font_size", 26)
	stars.add_theme_color_override("font_color", C_ACCENT)
	stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(stars)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	box.add_child(grid)
	var kind := "Common"
	if v["kind"] == "recipe":
		kind = "Bred variety (generation %d)" % int(v.get("gen", 1))
	elif v["kind"] == "mutation":
		kind = "Mutation"
	var age := int(f.get("age", 0))
	var sells := "Not until it's grown"
	var in_hall: bool = home != null and home.in_hall()
	if in_hall:
		sells = "Not for sale (Hall of Fame)"
	elif adult:
		sells = "$%d" % (home.price_of(f) if home != null and not home.is_breeding() and not home.is_holding() else Data.fish_price(f))
	var life := ""
	if in_hall:
		life = ", never grows old (Hall of Fame)"
	elif adult:
		var left := FishData.days_left(f)
		life = (", %d days left" % left) + ("  ⏳ old!" if left <= FishData.OLD_WARN_DAYS else "")
	var origin := "Bought from the market"
	if f.get("bred", false):
		origin = "Bred in your shop" + (" (generation %d)" % int(f["gen"]) if int(f.get("gen", 0)) > 0 else "")
	var rows := [
		["Species", sp["name"]],
		["Variety", "%s  ·  %s" % [v["name"] if v["name"] != "" else "Normal", kind]],
		["Sex", "Male ♂" if f.get("sex", "m") == "m" else "Female ♀"],
		["Quality", "%d of 5 stars" % int(f["stars"])],
		["Age", ("%d days%s" % [age, life]) if adult else ("%d days, grows up in %d" % [age, FishData.ADULT_AGE - age])],
		["Sells for", sells],
		["Market price", "$%d to buy one like it, pays $%d for this one" % [Data.wholesale_price(f["species"], f.get("variety", ""), int(f["stars"])), Data.market_buy_price(f)]],
		["Where from", origin],
		["Show ribbons", str(int(f.get("ribbon", 0)))],
		["Now in", "Storage (back room)" if home == null else _tank_name(home)],
	]
	for row in rows:
		var k := Label.new()
		k.text = row[0]
		k.add_theme_color_override("font_color", Color("#a9c6cf"))
		grid.add_child(k)
		var val := Label.new()
		val.text = row[1]
		grid.add_child(val)
	# Where it can go: the tank being filled first, then the rest.
	var tanks: Array = []
	if for_tank != null and is_instance_valid(for_tank) and for_tank != home:
		tanks.append(for_tank)
	for o in world.objects():
		if o is Tank and o != home and not tanks.has(o):
			tanks.append(o)
	_heading(box, "Put it in a tank", 16)
	if tanks.is_empty():
		_small(box, "No other tanks yet. Build one from the Build menu.")
	var list := GridContainer.new()
	list.columns = 2
	box.add_child(list)
	for t in tanks:
		var full: bool = t.fish.size() >= t.capacity()
		var b := _button(list, "%s  %d/%d%s" % [_tank_name(t), t.fish.size(), t.capacity(), "  full" if full else ""], func():
			_move_fish(id, t))
		b.disabled = full
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	box.add_child(row2)
	if home != null:
		_button(row2, "Take out to storage", func():
			Game.store_fish(home.remove_fish(id))
			_after_fish_move(fname + " moved to storage", id))
	elif adult:
		_button(row2, "Sell to the market ($%d)" % Data.market_buy_price(f), func():
			var got := Game.sell_to_market(id)
			toast("%s sold to the market for $%d" % [fname, got])
			_modal.visible = false
			_refresh_side())
	if home == null and Game.can_enter(f) and Game.show_entry.is_empty():
		_button(row2, "Enter it in the show", func():
			Game.enter_show(Game.take_stored_fish(id))
			_modal.visible = false
			_refresh_side())
	var close := _button(row2, "Close", func(): _modal.visible = false)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.custom_minimum_size.y = 36
	_pop(_modal)


func _move_fish(id: int, to: Node) -> void:
	var found := _find_fish(id)
	if found.is_empty() or to.fish.size() >= to.capacity():
		return
	var f: Dictionary = found[0]
	var got: Dictionary = Game.take_stored_fish(id) if found[1] == null else found[1].remove_fish(id)
	if got.is_empty():
		return
	if not to.add_fish(got):
		Game.store_fish(got)
		return
	_after_fish_move("%s moved to %s" % [FishData.full_name(f, Data.SPECIES[f["species"]]["name"]), _tank_name(to)], id)


func _after_fish_move(msg: String, id: int) -> void:
	toast(msg)
	_refresh_selection()
	_refresh_side()
	_fish_details(id)


## Pop-up: a show award up close (a slowly turning 3D view you can read) and its details.
func show_award(a: Dictionary) -> void:
	_clear(_modal)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_modal.add_child(box)
	_heading(box, WallAward.kind_name(a), 22)
	var stage := PanelContainer.new()
	stage.theme_type_variation = "CardPanel"
	box.add_child(stage)
	var pics := HBoxContainer.new()
	pics.alignment = BoxContainer.ALIGNMENT_CENTER
	pics.add_theme_constant_override("separation", 40)
	stage.add_child(pics)
	for pair in [[WallAward.wall_sprite(a), "On the wall"], [WallAward.cabinet_sprite(a), "In the trophy cabinet"]]:
		var col := VBoxContainer.new()
		pics.add_child(col)
		var pic := TextureRect.new()
		pic.texture = load(WallAward.SPRITE % pair[0])
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(230, 300) if pair[1] == "On the wall" else Vector2(150, 300)
		col.add_child(pic)
		var cap := Label.new()
		cap.text = pair[1]
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_theme_color_override("font_color", Color("#a9c6cf"))
		col.add_child(cap)
	# The engraving on its nameplate.
	var plate := Label.new()
	plate.text = "%s\n%s%s" % [WallAward.title(a), a.get("fish", ""), ("  ·  " + WallAward.date(a)) if WallAward.date(a) != "" else ""]
	plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_theme_color_override("font_color", Color("#ffd45c"))
	plate.add_theme_font_size_override("font_size", 18)
	box.add_child(plate)
	var close := _button(box, "Close", func(): _modal.visible = false)
	close.custom_minimum_size.y = 36
	_pop(_modal)


## Show a centred pop-up. Wrapped text only knows its height once laid out at its real
## width, so size it again after a couple of frames.
func _pop(p: Control) -> void:
	p.visible = true
	for i in 3:
		p.reset_size()
		p.size = Vector2(p.custom_minimum_size.x, 0)
		p.reset_size()
		p.position = ((p.get_parent_area_size() - p.size) * 0.5).max(Vector2(0, 70))
		await get_tree().process_frame


# --- Fish shows ---------------------------------------------------------------------------

func _show_panel() -> void:
	_heading(_side_box, "Fish shows")
	_small(_side_box, "A show every %d days, and every 4th is a Grand Show. Win money, prize fish, and at Grand Shows the locked varieties." % Game.SHOW_EVERY)
	var cls: String = Game.show_class()
	_heading(_side_box, "%s  (day %d, in %d days)" % [Game.show_title(), Game.next_show_day(), maxi(0, Game.next_show_day() - Game.abs_day)], 16)
	_small(_side_box, "Entry: " + Game.SHOW_CLASSES[cls]["desc"] + ". Judges score stars first, then how rare the variety is.")
	if Game.show_entry.is_empty():
		_small(_side_box, "You haven't entered a fish yet.")
	else:
		var r := _card(_side_box)
		r.add_child(FishIcon.make(Game.show_entry))
		var l := Label.new()
		l.text = "Your entry:\n" + Data.fish_label(Game.show_entry)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		_button(r, "Withdraw", func():
			Game.withdraw_show()
			_refresh_side())
	_heading(_side_box, "Eligible fish in storage", 16)
	var any := false
	var sorted := Game.fish_storage.filter(func(f): return Game.can_enter(f))
	sorted.sort_custom(func(a, b): return Game.show_score(a) > Game.show_score(b))
	for f in sorted:
		any = true
		var r := _card(_side_box)
		r.add_child(FishIcon.make(f))
		var l := Label.new()
		l.text = "%s\njudges' score ~%d" % [Data.fish_label(f), int(Game.show_score(f))]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		_button(r, "Enter", func():
			Game.enter_show(Game.take_stored_fish(int(f["id"])))
			_refresh_side())
	if not any:
		_small(_side_box, "None. Take fish out of their tanks into storage to enter them.")
	if not Game.last_show.is_empty():
		_button(_side_box, "Last show's results", func(): _show_show_result(Game.last_show))


func _show_show_result(r: Dictionary) -> void:
	_clear(_modal)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_modal.add_child(v)
	_heading(v, r["title"], 22)
	var place: int = r["place"]
	var head := Label.new()
	head.text = ["", "🥇 You won!", "🥈 Second place!", "🥉 Third place!"][place] if place <= 3 else "You came %d%s." % [place, "th"]
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", C_ACCENT if place <= 3 else C_TEXT)
	v.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	v.add_child(grid)
	for i in r["placings"].size():
		var e: Dictionary = r["placings"][i]
		var a := Label.new()
		a.text = "%d. %s" % [i + 1, e["name"]]
		if e["you"]:
			a.add_theme_color_override("font_color", C_GOOD)
		grid.add_child(a)
		var b := Label.new()
		b.text = str(int(e["score"]))
		grid.add_child(b)
	_small(v, "Prize: " + r["prize"])
	var ok := _button(v, "Close", func(): _modal.visible = false)
	ok.custom_minimum_size.y = 36
	_pop(_modal)


# --- Goals and achievements -------------------------------------------------------------------

func _goals_panel() -> void:
	_heading(_side_box, "Goals  %s" % ("⭐".repeat(Game.stars_earned) + "☆".repeat(Goals.STARS.size() - Game.stars_earned)))
	for i in Goals.STARS.size():
		var star: Dictionary = Goals.STARS[i]
		var done := i < Game.stars_earned
		_heading(_side_box, "%s %s  (reward $%s)" % ["⭐" if done else "☆", star["name"], _commas(int(star["reward"]))], 16)
		for g in star["goals"]:
			var have := Game.stat_value(g[0])
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", 0)
			_side_box.add_child(row)
			var l := Label.new()
			l.text = "%s  %s / %s" % [g[2], _commas(int(minf(have, g[1]))), _commas(int(g[1]))]
			l.add_theme_font_size_override("font_size", 13)
			if have >= float(g[1]):
				l.add_theme_color_override("font_color", C_GOOD)
			row.add_child(l)
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.custom_minimum_size.y = 6
			bar.max_value = float(g[1])
			bar.value = clampf(have, 0.0, float(g[1]))
			row.add_child(bar)
	_heading(_side_box, "Achievements  %d / %d" % [Game.achievements_done.size(), Goals.ACHIEVEMENTS.size()], 16)
	for a in Goals.ACHIEVEMENTS:
		var got: bool = Game.achievements_done.has(a[0])
		var l := Label.new()
		l.text = "%s %s: %s" % ["🏆" if got else "▫", a[1], a[2]]
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", C_ACCENT if got else Color("#7f9ba5"))
		_side_box.add_child(l)


func _shelf_section(shelf: Node) -> void:
	_small(_sel_box, "Each slot sells one product and holds %d. Changing a slot sends its stock back to the stockroom." % shelf.capacity())
	for i in shelf.slot_count():
		_heading(_sel_box, "Slot %d" % (i + 1), 16)
		var pick := OptionButton.new()
		pick.focus_mode = Control.FOCUS_NONE
		pick.add_item("Empty")
		pick.set_item_metadata(0, "")
		var ids: Array = Data.PRODUCTS.keys()
		for k in ids.size():
			var id: String = ids[k]
			pick.add_item("%s  (%d in stockroom)" % [Data.PRODUCTS[id]["name"], int(Game.stockroom.get(id, 0))])
			pick.set_item_metadata(k + 1, id)
			if shelf.product(i) == id:
				pick.select(k + 1)
		pick.item_selected.connect(func(idx):
			shelf.set_product(str(pick.get_item_metadata(idx)), i)
			_refresh_selection())
		_sel_box.add_child(pick)


# --- Report and toasts ---------------------------------------------------------------------

func _show_report(r: Dictionary) -> void:
	_clear(_report)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_report.add_child(v)
	_heading(v, "Monthly report: " + r["title"], 22)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	v.add_child(grid)
	var rows := [
		["Customers", str(r["customers"])], ["Happy / disappointed", "%d / %d" % [r["happy"], r["unhappy"]]],
		["Gave up at the till", str(r.get("gave_up", 0))],
		["Fish sold", str(r["fish_sold"])], ["Tanks cleaned", str(r.get("tanks_cleaned", 0))], ["Supplies sold", str(r["items_sold"])], ["Fish bred", str(r["fish_bred"])],
		["", ""],
	]
	var names := {"fish_sales": "Fish sales", "supply_sales": "Supply sales", "refunds": "Things sold back",
		"construction": "Building", "supplies": "Supply orders", "fish_orders": "Fish orders", "rent": "Rent",
		"marketing": "Marketing", "showcase": "Showcase upkeep", "wages": "Staff wages", "loans": "Loan money received", "loan_repayments": "Loan repayments", "expansion": "Expansion", "discoveries": "New variety bonuses", "show_prizes": "Show prizes", "goal_rewards": "Goal rewards", "market_sales": "Fish sold to the market"}
	for k in r["income"]:
		rows.append([names.get(k, k), "+$" + _commas(int(r["income"][k]))])
	for k in r["expenses"]:
		rows.append([names.get(k, k), "-$" + _commas(int(r["expenses"][k]))])
	rows.append(["", ""])
	rows.append(["Profit", ("+$" if int(r["profit"]) >= 0 else "-$") + _commas(absi(int(r["profit"])))])
	rows.append(["Bank balance", "$" + _commas(int(r["balance"]))])
	if int(r.get("debt", 0)) > 0:
		rows.append(["Still owed on loans", "$" + _commas(int(r["debt"]))])
	rows.append(["Reputation", "%d%%" % int(r["reputation"])])
	for row in rows:
		var a := Label.new()
		a.text = row[0]
		grid.add_child(a)
		var b := Label.new()
		b.text = row[1]
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if row[1].begins_with("+"):
			b.add_theme_color_override("font_color", C_GOOD)
		elif row[1].begins_with("-"):
			b.add_theme_color_override("font_color", C_BAD)
		grid.add_child(b)
	var ok := _button(v, "Carry on", func():
		_report.visible = false
		if Game.speed == 0:
			Game.set_speed(1))
	ok.custom_minimum_size.y = 40
	_report.visible = true
	_report.reset_size()
	_report.position = (_report.get_parent_area_size() - _report.size) * 0.5
	if _start.visible or Game.autoplay:
		return
	if Game.history.size() > 0 and r == Game.history.back():
		Game.set_speed(0)


func toast(text: String) -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_PANEL, 0.92)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	_toasts.add_child(p)
	while _toasts.get_child_count() > 4:
		_toasts.get_child(0).free()
	var tw := p.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


# --- Building blocks -----------------------------------------------------------------------

func _theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(C_PANEL, 0.94)
	panel.set_corner_radius_all(12)
	panel.set_content_margin_all(12)
	panel.border_color = Color("#2f6b7f")
	panel.set_border_width_all(2)
	t.set_stylebox("panel", "PanelContainer", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = C_PANEL2
	btn.set_corner_radius_all(8)
	btn.content_margin_left = 10
	btn.content_margin_right = 10
	btn.content_margin_top = 5
	btn.content_margin_bottom = 5
	var hover := btn.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#2b6377")
	var pressed := btn.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#c77d12")
	var disabled := btn.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("#1a2f38")
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_disabled_color", "Button", Color("#6f8b95"))
	t.set_color("font_color", "Label", C_TEXT)
	var card := StyleBoxFlat.new()
	card.bg_color = Color("#1b3d4b")
	card.set_corner_radius_all(8)
	card.set_content_margin_all(8)
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", card)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#0e2129")
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = C_ACCENT
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	return t


func _panel(parent: Control, preset: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(preset)
	parent.add_child(p)
	return p


func _scroll_box(panel: PanelContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	return v


func _card(parent: Control) -> HBoxContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "CardPanel"
	parent.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	return h


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _heading(parent: Control, text: String, size: int = 20) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", C_ACCENT)
	parent.add_child(l)


func _small(parent: Control, text: String) -> void:
	var l := Label.new()
	l.custom_minimum_size.x = 200
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color("#a9c6cf"))
	parent.add_child(l)


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out



# --- Game menu ------------------------------------------------------------------------------

func _game_menu() -> void:
	_clear(_modal)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_modal.add_child(v)
	_heading(v, "Menu", 22)
	var save := _button(v, "Save game  (F5)", func():
		world.save_game()
		_modal.visible = false)
	save.custom_minimum_size.y = 40
	for spec in [[SaveGame.MANUAL, "Load saved game  (F9)"], [SaveGame.AUTO, "Load autosave"]]:
		var desc := SaveGame.describe(spec[0])
		var b := _button(v, "%s%s" % [spec[1], "   (" + desc + ")" if desc != "" else ""], func(): world.load_game(spec[0]))
		b.disabled = desc == ""
		b.custom_minimum_size.y = 40
	_small(v, "The game autosaves at the end of every month.")
	var ng := _button(v, "New game", world.new_game)
	ng.custom_minimum_size.y = 40
	var q := _button(v, "Quit to desktop", func(): get_tree().quit())
	q.custom_minimum_size.y = 40
	var close := _button(v, "Back to the shop", func(): _modal.visible = false)
	close.custom_minimum_size.y = 40
	_pop(_modal)
