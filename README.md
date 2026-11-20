# Fig Tree Fish Store

A management sim about running a fish shop, viewed from an angled overhead camera.
Customers come into the showroom to look at tanks and buy fish or supplies; the back room
is where you breed new fish (rated 1 to 5 stars). Time passes in days and months, and
every month ends with a report.

Version **0.6.1** (Godot 4.7.2, Forward+). This is the base system.

## Controls

| | |
|---|---|
| WASD / arrow keys, or right-drag | Pan the camera |
| Q / E, or middle-drag | Turn the camera |
| Mouse wheel, + / - | Zoom |
| Left click | Select something (or place what you're building) |
| R | Turn what you're placing |
| Right click / Esc | Stop placing |
| Delete | Sell the selected thing (in edit mode: what's under the mouse) |
| M | Edit mode: click anything to pick it up and move it, R turns what's under the mouse, M or Esc to finish |
| Space, 1, 2, 3 | Pause, 1x, 2x, 4x speed |
| B / O / F / H / G | Build, Order, Fish, Staff and Goals panels |
| V | Walls down (or back to auto cut-away) |

## How it works

- **Build** tanks (small, medium, large, breeding), supply shelves, a till counter, decor
  and back-room props. Click anything you've built to move, turn or sell it (half price back),
  or use **Edit mode** (M, or the Edit button) to pick things up and rearrange the shop.
- **Fish close-up**: click any fish's picture (storage, a tank's list, the breeding forecast)
  for a big picture and all its stats (variety, sex, stars, age, price, where it came from,
  ribbons), and put it straight into any tank from there.
- **Selling surplus**: the fish market buys grown fish from storage at 40% of the shop
  price (far below what it charges, so it's only for clearing extras). Sell one from its
  close-up, or in bulk from Fish storage (1★, 1–2★ or 1–3★). Bulk selling keeps your
  best male and female of each variety and any show winners.
- **Tanks**: select one to put fish in from back-room storage or take them out.
  A tank's **appeal** comes from its size, decor within 4 m, the stars of its fish and
  whether it is **showcased** (spotlight, appeal x1.5, $60/month). Higher appeal means
  more sales and up to +50% on the price.
- **Fish** have a species, a variety, a sex (♂/♀) and 1-5 stars. Fry grow up in 3 days
  (stars show once they're adults) and can't be sold until then.
- **Breeding tanks** (back room only, 6 fish): only adults of one species breed; different
  species never cross. Each male fathers broods with up to 3 females, so broods =
  min(females, males x 3); more males than females halves it. A brood is 2-4 fry, every
  4 days, into storage. Putting a fish in pops up a **Breeding forecast** with pictures
  of the parents, the spawn rate and the chance of each baby variety.
- **Genetics** (as in the guppy breeding game): a 1.5% chance of a mutation, else a 30%
  chance of the recipe child when the parents' varieties make one (e.g. Red x Yellow
  guppies make Orange, Comet x Fantail goldfish make Ryukin), else the mother's or
  father's variety. Stars are the parents' average nudged -1/0/+1, better in clean water.
  Guppies have 33 varieties over 3 generations plus mutations; goldfish have 15. Each new
  variety earns a bonus. The **Breeding book** (Fish panel) shows them all, with recipe hints.
- **Fish market** (Order > Fish): adults of the common varieties (and a few first-generation
  ones), your choice of sex and 1-3 stars. Market fish cost more than customers pay.
- **Fish shows** (Show): every 14 days, every 4th is a Grand Show, with rotating classes
  (Open, Guppy, Quality 3★+, Goldfish, Rare varieties). Enter one fish from storage; rival
  breeders get better over time. Prizes: money for the top 3 (x3 at Grand Shows); a win
  can bring a prize fish; winning a Grand Show unlocks the next **locked variety** (Galaxy
  guppy, Lionhead, Pearlscale, Dragon guppy, Celestial) and gives you a pair.
- **Shelves** have limited room: a supply shelf has 3 slots of 6, a small shelf 2 slots of 4.
  Pick a product for each slot; a stocker fills them from the stockroom.
  **Order** boxes of supplies (they arrive the next day). Wholesale fish cost more than
  customers pay, so profit comes from breeding.
- **Staff** (H): hire and fire from the Staff panel; wages are paid at the end of the month.
  - **Cashier** stands behind the till. Without one, customers wait, then give up, put
    everything back and leave disappointed.
  - **Stocker** carries boxes from the back room (by the pallet rack or stock boxes) to
    shelf slots that are half empty. Shelves no longer fill themselves.
  - **Fish Keeper** cleans tanks. Tanks get dirtier every day (faster with more fish); the
    water turns murky green, appeal drops by up to 60%, and breeding stops above 60% dirt
    (a warning pops up when it does). Keepers clean breeding tanks with a pair in them
    first, then showroom tanks, then the dirtiest.
  - You start with a cashier and a stocker. Idle staff wait by the back-room desk.
- **New game**: a bare shop with the till, one display tank of guppies, one supply shelf
  and one breeding tank (a red and yellow guppy trio), plus a comet and fantail goldfish
  pair in storage. Build the rest yourself. A **First steps** checklist (top left) pays
  $250 for each of: hire a Fish Keeper, put a bred fish on display, breed the goldfish,
  build a second display tank.
- **Marketing** (flyers, newspaper, radio) brings in more customers for a monthly fee.
- **Monthly report**: customers, happy/disappointed, sales, costs (rent $350 plus $120-150
  per plot bought) and profit. Reputation settles at about the share of customers who
  leave happy (each visit pulls it 2% of the way); new varieties and show wins lift it
  for a while.
- **Start**: no debt ($5,000), a small loan (+$8,000) or a large loan (+$25,000), repaid
  monthly. After 3 months of trading the **Bank** lends up to 2 more loans; pay any off early.
- **Expand**: the lot is a grid of 2.5 m bays. Buy the west wing, east wing and rear
  extension (yellow FOR SALE grids) to grow the building. The street, neighbours, a fence,
  alleys and a park surround the lot.
- **Goals (G)**: three star ratings, each a set of targets (customers, fish bred, new
  varieties, operating profit, show wins, a 5★ fish) with a cash reward, plus 24 achievements.

## Saving

**Menu** (top bar) has Save (F5), Load (F9), Load autosave, New game and Quit. The game
autosaves at the end of every month, and the start screen offers Continue. Saves are JSON
files in Godot's user folder (`%APPDATA%/Godot/app_userdata/Fig Tree Fish Store/`).

## Art

Synty Polygon Shops, Polygon City and Polygon Office models, plus the Synty animation
clips, the same packs as Fig Tree Fish Breeder 3D. They are licensed, so `assets/Synty/` is
git-ignored: copy it from `fig-tree-fish-breeder-sim-3d/assets/Synty/`, then run
`godot --headless --path . --import`.

Guppies use the hand-drawn sprite sheet from the guppy breeding game
(`assets/fish/guppy_sheet.png`, one picture per variety; a few rare varieties reuse a
close picture with a tint), in the menus and swimming in the tanks.

Goldfish are pixel art (side view, facing right): one per variety in `assets/fish/goldfish_pixel/`,
packed into `assets/fish/goldfish_pixel_sheet.png` by `tools/build_goldfish_pixel.py` (which also writes
`scripts/goldfish_pixel_cells.gd`). They come from the shared set in
`G:/Game Ideas/_shared-assets/fish/goldfish-pixel/` (30 fish, numbered); to swap a variety's picture,
change its number in `PICKS` and run `python tools/build_goldfish_pixel.py --from-shared`.

The earlier goldfish photos (Wikimedia Commons, credits in `assets/fish/CREDITS.md`) are still in
`assets/fish/goldfish_photos/` and `goldfish_sheet.png` (built by `tools/build_goldfish_photos.py`),
but the game no longer shows them.

## Screenshots

```
godot --path . --resolution 1600x900 -- --screenshot=res://screenshots/layout.png --wait=16
```

Extra options: `--cam=x,z,distance,yaw`, `--fast` (4x speed), `--select=x,z`, `--place=item_id`.
