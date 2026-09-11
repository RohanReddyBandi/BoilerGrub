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
2. **`Status` can be `"Closed"`** (4 of 19 meals in the fixtures). Closed meals
   still carry a full item list — worth showing, but visually de-emphasised.
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
plus Earhart on a past date), an unpublished-date menu, `locations.json`, eight
item details (one `NutritionReady: false` stub among them), and a captured 500
error body for testing the failure path.
