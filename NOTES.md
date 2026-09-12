# BoilerGrub — Notes

Running log of decisions and anything surprising about the upstream API.

---

## Step 1 — API reconnaissance (2026-09-11)

**Headline: the menu endpoint contains no nutrition data. Macros require a second
call, per item, to a separate item-detail endpoint.** Details below.

### Endpoints found

| Endpoint | Purpose |
|---|---|
| `GET /menus/v2/locations` | All dining locations w/ hours, coords, logos |
| `GET /menus/v2/locations/{Name}/{MM-DD-YYYY}/` | One day's menu for one location — **no nutrition** |
| `GET /menus/v2/items/{ID}` | Per-item nutrition + ingredients — **this is where macros live** |

Notes on the base URL:

- `http://` returns **301** to `https://`. Use `https://` directly; `URLSession`
  follows it anyway, but skipping the redirect saves a round trip.
- The path segment is the **display name** (`Earhart`), *not* the `LocationId`
  (`ERHT`) returned by `/locations`. Mixing these up 500s.
- Trailing slash on the menu path is what the app uses; it works without one too.

### `/locations` — exactly five dining courts

`Types: ["Dining Courts", "Quick Bites", "On-the-GO!"]`. Filtering on
`Type == "Dining Courts"` yields exactly the five named in the brief:

| LocationId | Name |
|---|---|
| ERHT | Earhart |
| FORD | Ford |
| HILL | Hillenbrand |
| WILY | Wiley |
| WIND | Windsor |

The other seven (`BOWL`, `EOTG`, `LWSN`, `PZZA`, `@TGP`, …) are retail/grab-and-go
and are out of scope for v1. Since the set is small, fixed, and the URL needs the
display name anyway, **v1 hardcodes the five** rather than fetching `/locations`
at launch — one less network dependency on the critical path.

### Menu response shape

```
{ Location: String, Date: "9/11/2026", IsPublished: Bool, Notes: String?,
  Meals: [ { ID, Name, Order: Int, Status: "Open"|"Closed", Type,
             Hours: { StartTime: "07:00:00", EndTime: "10:00:00" }?,
             Notes: String?,
             Stations: [ { Name, IconUrl, ForegroundColor, BackgroundColor, Notes,
                           Items: [ { ID, Name, IsVegetarian, NutritionReady,
                                      Allergens: [{Name, Value: Bool}]  // may be absent
                                    } ] } ] } ] }
```

Surprises worth coding against:

1. **`Meals[].Name` is not limited to Breakfast/Lunch/Dinner.** Across just six
   fixtures I saw `Breakfast`, `Lunch`, `Dinner`, **`Brunch`** (Hillenbrand) and
   **`Late Lunch`**. Worse, `Type` doesn't rescue you — `Brunch` reports
   `Type: "Unknown"` and `Late Lunch` reports `Type: "Snack"`. So the meal model
   must treat the name as open-ended and **sort by `Order`**, not by a fixed enum.
2. **`Status` can be `"Closed"`** (4 of 19 meals in the fixtures), and a closed
   meal carries **zero stations and zero items**. *(Corrected: my first pass
   assumed closed meals still listed their food. They don't — I checked.)*
   `Closed` means the court doesn't serve that period on that day at all; it is
   not a "closed at this moment" flag. Hillenbrand has Brunch, Lunch *and* Late
   Lunch closed on the captured day, so a court can legitimately have nothing
   browsable. The menu screen therefore filters empty meals out of the selector
   instead of offering a tab that leads nowhere.
3. **Items with `NutritionReady: false` omit the `Allergens` key entirely.** Not
   an empty array — the key is gone. `Allergens` must decode as optional.
4. `Date` echoes back as `M/D/YYYY`, not the `MM-DD-YYYY` you sent.
5. `IconUrl` / `ForegroundColor` / `BackgroundColor` on stations were `null` in
   every fixture. Present in the schema, unused in practice. Ignored for v1.

### Item detail — where the macros actually are

`GET /menus/v2/items/{ID}` →

```
{ ID, Name, IsVegetarian, NutritionReady,
  Allergens: [...],
  Ingredients: String,          // one long comma-separated blob
  Nutrition: [ { Name, Value: Double?, LabelValue: String?, DailyValue: String?, Ordinal: Int } ] }
```

I pulled 59 distinct items and checked field stability. **All 14 nutrition rows
were present on all 59, at identical `Ordinal`s:**

| Ordinal | Name | has numeric `Value` |
|---|---|---|
| 0 | Serving Size | **no — label only** |
| 1 | Calories | yes |
| 2 | Calories from fat | **no — label only** |
| 3 | Total fat | yes |
| 4 | Saturated fat | yes |
| 5 | Cholesterol | yes |
| 6 | Sodium | yes |
| 7 | Total Carbohydrate | yes |
| 8 | Sugar | yes |
| 9 | Added Sugar | yes (3/59 missing) |
| 10 | Dietary Fiber | yes |
| 11 | Protein | yes |
| 12 | Calcium | yes |
| 13 | Iron | yes |

So all four macros the brief needs — calories, protein, carbs, fat — are here.

**Units.** `Value` is an unrounded number in the unit implied by `LabelValue`
(`Total fat: Value 12.2104, LabelValue "12g"` → grams; `Sodium: Value 376.79,
LabelValue "380mg"` → mg; `Calories: Value 154.54, LabelValue "155"` → kcal).
Sanity-checked against Atwater (4·protein + 4·carb + 9·fat ≈ calories) on 12
items: **12/12 landed within 25%**, several within 2%. Units confirmed. The app
uses `Value` for math and `LabelValue` only for display.

**Match rows by `Name`, not `Ordinal`.** Ordinals were stable across all 59
samples, but `Name` is the more meaningful key and costs nothing to match on. Do
not index positionally into the array.

**`Value` must decode as optional `Double?`.** Two rows never have it, and
`Added Sugar` was missing it on 3/59 items despite being a numeric field.

### Serving size is free text — this constrains the HealthKit design

`Serving Size` has no numeric `Value`, and `LabelValue` is unparseable prose:
`"Ounce"`, `"1/2 Cup"`, `"Pizza"`, `"8x10 Cut Serving"`, `"4 Piece Serving"`,
`"Bagel"`, `"Egg"`, `"12 Cut Serving"`, `"Slice"`, `"Tablespoon"`.

There is no reliable way to convert a serving to grams. **Consequence for the
plate feature:** serving *count* is a plain multiplier over the per-serving
numbers, and the UI shows the court's own serving label verbatim rather than
implying a gram weight the API never gave us.

### Items with `NutritionReady: false` are not dishes

65 of 576 item rows. The detail endpoint returns a stub — no `Nutrition`, no
`Ingredients`, no `Allergens`:

```json
{"ID":"86012f74-...","Name":"Bread and Condiments","IsVegetarian":false,"NutritionReady":false}
```

Every one is a category placeholder: *Bread and Condiments, Deli Bar, Pizza
Toppers, Assorted Donuts, Oatmeal and Pancake Toppers*. These should render as
non-tappable, non-addable rows. Don't waste a network call on them — filter on
`NutritionReady` before fetching.

### Item IDs are near-stable, and that's good enough

Comparing Earhart on 2026-03-04 vs 2026-09-11: of 43 items appearing on both
dates, **40 shared an ID and 3 did not** (same dish name, new ID — presumably a
recipe revision). An ID therefore always maps to one fixed nutrition payload,
even though a *name* may not. **Cache item details by ID, permanently** — a given
ID's macros never change. The 3 revisions naturally become fresh cache entries.

### Error behaviour is hostile — plan for it

| Request | Result |
|---|---|
| Unknown location | **HTTP 500**, .NET stack trace, `"Sequence contains no matching element"` |
| Unknown item ID | **HTTP 500**, .NET stack trace, `"Source sequence doesn't contain any elements"` |
| Date far in the future | **HTTP 200**, `IsPublished: false`, `Meals: []` |
| ISO date (`2026-09-11`) instead of `MM-DD-YYYY` | **HTTP 200** — parser is lenient, returns the right day |

Two things follow. First, **a 500 here means "not found", not "the server is
broken"** — it must surface as a calm empty state, never a crash or a scary
alert. Second, `IsPublished: false` with an empty `Meals` array is the *normal*
answer for a date the court hasn't posted yet, and deserves its own "menu not
posted yet" state distinct from a network failure.

Also: responses set `Cache-Control: public, max-age=600` and hand out tracking
cookies (`api_gac`, a BigIP session cookie). The app uses an ephemeral,
cookie-less `URLSession` — no reason to carry an identifier around.

### Fixtures saved

`/fixtures` holds real unedited responses: six menus (five courts on 2026-09-11,
plus Earhart on a past date), an unpublished-date menu (`menu-Earhart-12-25-2026.json`), `locations.json`, eight
item details (one `NutritionReady: false` stub among them), and a captured 500
error body for testing the failure path.

---

## Step 2 — the app (2026-09-11)

### Design direction: the tray line

The brief ruled out the obvious build — gold header, white cards, rounded
corners, grey shadows — so the direction here is a **cafeteria tray line printed
as a meal ticket**, and it commits hard enough that the rest can stay quiet.

**The one structural idea** is a gold hairline *rail* running down the leading
edge of the content, notched with a tick where each station begins. Stacked down
the screen, the notches read as stations along a serving line. It carries the
station list, and it reappears in today's log to bracket each saved plate.

Everything else follows one rule: **the app has no cards and no shadows.** Every
separation is a line, and there are exactly three:

| Device | Means |
|---|---|
| Hairline rule | a minor break between rows |
| Perforation (dashed) | a tear-off between major sections |
| Double rule | everything below this is a total |

That vocabulary is the whole visual system. Because it's so small, the rare
filled element — the gold `add to plate` and `save to apple health` buttons —
carries real weight without needing a shadow or a gradient to announce itself.

**Type is two families, each with one job.** Dish names, court names and
headings are set in **New York** (serif) — the menu-board voice. Every number,
and every small metadata label, is **SF Mono**. Monospaced digits are what let a
column of macros line up like a register tape, and the tape is the idea.
Nothing in the app uses the default UI sans, which is the fastest way for an
iOS app to look like every other iOS app.

**The numbers carry it**, as asked. The calorie figure on a dish is 72pt mono
light; the plate and daily totals are 44pt. On the detail screen it's the first
thing your eye lands on, sitting directly under a double rule with nothing
competing. Item rows connect name to figure with leader dots, the way a printed
menu connects a dish to its price.

**Colour**: Purdue black (warmed a touch off pure #000 so it doesn't glare on
OLED), old gold #CEB888 for rules, ticks and accents, and bone rather than white
for type. The app is dark-only — `UIUserInterfaceStyle = Dark` — which is a
deliberate commitment, not an oversight: a chalkboard doesn't have a light mode.
One non-Purdue hue exists, a muted ember, reserved solely for destructive
actions so "remove" never has to borrow gold's authority.

Explicitly avoided, per the brief: identical rounded cards, a shared shadow,
ALL-CAPS eyebrow labels (labels are lowercase mono with tracking, which reads as
stamped ticket furniture instead of a heading), gradients, and fade-up-on-scroll
animations.

### Screens

- **Menu** — court name opens a picker; a strip of tear-off day stubs; meal
  names underlined in gold; stations hung off the rail. Nutrition is *not* shown
  inline, by request, so browsing costs exactly zero extra network calls.
- **Dish** — the nutrition ticket. Hero calorie figure, a three-up macro row,
  then the remaining ten rows the API returns as a register tape. Every figure
  reflects the serving count dialled in at the bottom, so the number on screen
  is the number that will land in Health.
- **Plate** — a register tape with a pinned footer. The total belongs at the
  *end* of a tape, but a plate you're still editing needs its running figure
  visible at all times, so the tape's ending is pinned to the bottom of the
  screen rather than the bottom of the list.
- **Today** — the day's total at the top, then each saved plate bracketed by the
  rail, with its Health sync state stamped at the right.

The plate itself lives in a bar pinned under the menu rather than in a tab: it's
something you accumulate while walking the line, so it belongs underfoot.

### Decisions worth recording

**Nutrition is fetched on tap, never prefetched.** Since macros aren't shown in
the menu list, browsing a full court-day costs one request. Tapping a dish costs
one more, cached permanently. Had calories been shown inline it would have cost
30–75 requests per court-day (Earhart alone has 75 distinct nutrition-ready
items in a day).

**Local write first, Health second.** `PlateScreen.save()` commits to SwiftData
and only then attempts HealthKit. A denied permission, a restricted device, or
an iPad with no Health app then costs the reader nothing but the sync — and the
daily view offers a retry. This ordering is the single most important line in
that file.

**Write-only HealthKit.** The app requests `toShare` for the four quantity types
plus the food correlation, and reads nothing. The daily view is built from what
BoilerGrub itself logged, so there's no reason to ask for read access — and
asking for less makes the prompt easier to say yes to. Permission is requested
on the first actual save, not at launch.

**One food entry per dish, not one per plate.** Each plate item is saved as its
own `HKCorrelation` with `HKMetadataKeyFoodType` set to the dish name, so the
Health app shows "Blackened Tilapia" rather than an anonymous lump of calories.

**Logged items copy their macros rather than referencing an item id.** The
upstream API is unofficial and dishes get revised or vanish; a record of what you
ate in March must not be able to change in September.

**Serving counts move in half-steps.** A quarter of a "Pizza" or an "8x10 Cut
Serving" isn't something anyone can estimate, and since the API gives no numeric
serving weight there's nothing to estimate *from*.

**Two scaling rules that took a second pass to get right.** At exactly one
serving, rows pass through untouched — including `% Daily Value`, which is only
meaningful against the serving the label was computed for. Above or below one
serving, daily values are dropped, and **label-only rows are blanked** rather
than left alone: `Calories from fat` has no numeric `Value`, so leaving its
"108" sitting next to doubled neighbours would quietly misreport it. Separately,
`Calcium` and `Iron` come back with a numeric `Value` but a *null* `LabelValue`,
so the raw number is printed without an invented unit, with the `%` beside it
supplying the context.

### Tests

57 tests, all running off the bundled fixtures — no network, and nothing that
starts failing in November when a dining court changes its menu. They cover
decoding every captured court, meal ordering, the open-ended meal names, closed
and unpublished days, placeholder rows, the Atwater unit check, both scaling
rules, plate arithmetic, the cache policy (past days and item nutrition cached
permanently, unpublished days never cached, stale cache served when the network
fails), and the transport layer's 500-means-not-found mapping via a stubbed
`URLProtocol`.

### Known limits

- **No numeric serving weight exists anywhere in the API**, so a "serving" is
  whatever the court means by it. This is the single biggest caveat on any
  number this app writes to Health.
- **The five courts are hardcoded.** `/locations` confirms the set is fixed and
  the menu URL needs the display name anyway; if Purdue opens a sixth court it's
  a one-line change.
- **Deleting a logged plate doesn't remove it from Health.** Anything already
  written belongs to the reader and is theirs to manage in the Health app;
  silently deleting their health data from under them would be the worse
  default.
- **Upstream will break eventually.** When it does, it should surface as a calm
  empty state, because every DTO field is optional and every failure path lands
  in `MenuServiceError`. `HFSMenuClient` is the only file that would need work.

---

## Step 3 — all food spots, not just the five courts (2026-09-11)

Rebuilding the landing page around every campus food location meant probing
again rather than assuming the other eight behaved like the dining courts.

### Every location has a menu at the same endpoint

All twelve locations in `/locations` answer `GET /locations/{Name}/{date}/`
with a published menu — Quick Bites and On-the-GO! included. The path segment is
still the display `Name`, which for these includes spaces, apostrophes and
exclamation marks (`Pete's Za at Tarkington Hall`, `Earhart On-the-GO!`) and has
to be percent-encoded.

### But two of them have no nutrition at all

| Location | Type | Nutrition-ready items | Placeholder rows |
|---|---|---|---|
| Earhart / Ford / Hillenbrand / Wiley / Windsor | Dining Courts | 30–75 | some |
| Pete's Za at Tarkington Hall | Quick Bites | 37 | 0 |
| Windsor On-the-GO! | On-the-GO! | 18 | 0 |
| Lawson On-the-GO! | On-the-GO! | 12 | 2 |
| Earhart On-the-GO! | On-the-GO! | 11 | 0 |
| Ford On-the-GO! | On-the-GO! | 9 | 1 |
| **1bowl at Meredith Hall** | Quick Bites | **0** | 8 |
| **Sushi Boss at South Hall** | Quick Bites | **0** | 30 |

**1bowl and Sushi Boss publish menus where every single row is
`NutritionReady: false`.** They're browsable, but nothing in them can be added
to a plate or logged to Health. The app says so on the location row rather than
letting someone tap in and discover a dead end.

### Open/closed comes from `UpcomingMeals`

Each location carries `UpcomingMeals`: service windows with **absolute**
timestamps including a timezone offset (`2026-09-11T17:00:00-04:00`). Comparing
those against the current time is the reliable open/closed test, and it needs no
timezone guessing of our own.

Two caveats found by inspection:

1. **The list includes windows that have already passed.** Several locations had
   every entry in the past, so "no current window" is common and must not be
   mistaken for "this place doesn't exist".
2. **It's short** — between 1 and 5 entries depending on location, so it often
   can't answer "when does this open next".

So `NormalHours` is the fallback for the next opening time: a weekly schedule
keyed by `DayOfWeek` (0 = Sunday), which the app walks forward up to seven days.
A location can legitimately be missing days from that schedule — 1bowl lists
only six — which means closed all day, not missing data.

### Design revisions this round

- **Strictly black and gold.** The warm bone and olive-grey secondary tones are
  gone; every non-white value in the palette is now Purdue gold at some opacity
  against near-black. The hero calorie and total figures are set *in gold*,
  which puts the identity colour on the most important data on screen. The one
  remaining non-Purdue hue, the destructive ember, was removed too — "remove"
  and "delete" are distinguished by wording and weight instead.
- **Leader dots are gone.** Rows now resolve into fixed, right-aligned columns.
- **The nutrition tape is properly columnar.** Previously the value column was
  ragged and rows without a `% Daily Value` ran into the space where the
  percentage should sit, which is what made the percentages look misaligned.
  Value and daily-value are now fixed-width columns, and a row with no
  percentage leaves that column empty rather than expanding into it.
- **The date control is now a single quiet line** with previous/next arrows and
  a tap-through to a picker, instead of a full-width scrolling strip of day
  stubs. Picking a day is occasional; it shouldn't dominate the screen.
