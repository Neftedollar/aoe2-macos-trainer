# Starting food: observations, not hidden-map knowledge

This observer supports food-sensitive training builds without OCR, process
inspection, game orders, or world-state effects. It is designed for the standard
AoE2: Definitive Edition data set and an explicitly loaded custom RMS/scenario.
It is not proof of runtime compatibility with the current native Mac release.
The integration still needs a real-game smoke test.

## What the facts mean

`trainerObservedPushableHuntCount` and `trainerObservedSmallGameCount` are counts
of distinct live animal **instance IDs first observed** in the opening, within
24 map tiles of the first own Town Center reported by the engine. They are
historical lower bounds, not a current inventory, initial map-generation count,
remaining-food amount, or a statement that the hunt is safe to use.

- Only the local player's current visibility is accepted, with `allowInFog`
  explicitly `false`. No enemy player's observations are queried.
- Observation continues through game second 600, rather than taking an incomplete
  snapshot at game second zero. A scout can discover eligible food later.
- The first Town Center position is fixed; building another TC does not move the
  search area. Without an own TC, food remains unknown. In unusual scenarios or
  Nomad, the first TC returned may be a foundation; no completion claim is made.
- A live animal first seen outside the radius can qualify if later seen inside
  it. Thus this is an opening-area observation, not proof of its original spawn.
- Once a unique animal has qualified, its observation is retained after it moves,
  dies, is consumed, or disappears into fog. Its live position or remaining food
  is not refreshed through fog. A consumed animal cannot make an active opening
  suddenly ineligible.
- A count of zero means **not observed / unknown**, never “there are no deer.”
  Seeing small game does not imply that regular hunt is absent, or vice versa.
- Proximity is planar distance, not a pathfinding, wall, elevation, threat, or
  reachability check. Species pushability does not show whether the user can or
  wants to push it, or whether pushing has succeeded.

Use these as positive prerequisites for *offering* appropriate variants. Keep a
non-pushing fallback available, and never silently replace a build that is
already selected. Civ applicability and the user's pushing preference remain
separate from these observations. An unobserved animal should not expose a build
by inference from the map name.

## Exact species allowlist

| Category | Standard object/master IDs |
| --- | --- |
| Regular pushable hunt | Deer `65`, zebra `1019`, ostrich `1026`, ibex `1239`, gazelle `1796`, argali `1896` |
| Small unpushable game | Wild chickens `2084`, `2086`, `2088`; hares `2098`, `2099`; arctic hare `2100`; pheasant `2739` |

These are **master IDs for classification**, not the instance IDs used to avoid
double counting. Herdable chickens `2083`, `2085`, `2087` are deliberately not
classified as wild small game. Boar-type lure animals, livestock, berries, fish,
pastures, and unknown/modded species are outside these two facts.

Do not substitute the whole prey-animal class: red and arctic foxes `1955` and
`1958` are huntable **gold** sources. Generic carcasses also do not reliably
identify their original live species. The observer requires positive HP and a
known live master ID; it does not infer a subtype from a corpse or a worker task.
The separate approximate worker classifier likewise checks these live fox IDs
before its broader food-prey category, and only reads a task target's object or
class while currently visible. Carried resources remain an approximate fallback
for the player's own villagers, not evidence about unseen animals. Generic
corpse `43`, shared by food hunt and gold foxes, does not get a food classification
from its class alone: until the own villager carries an identifiable resource,
that sample can remain unclassified.

IDs are documented in the current
[AoE2ScenarioParser unit dataset](https://github.com/KSneijders/AoE2ScenarioParser/blob/master/AoE2ScenarioParser/datasets/units.py).
The [official August 2025 update](https://www.ageofempires.com/news/age-of-empires-ii-definitive-edition-update-153015/)
explicitly introduces the three hare IDs as small unpushable hunt and the foxes
as gold hunt. The
[official content preview](https://www.ageofempires.com/news/a-sneak-peek-at-new-content-coming-to-age-of-empires-ii-definitive-edition/)
distinguishes wild from herdable chicken IDs and describes wild chickens'
limited movement. The
[October 2026 update](https://www.ageofempires.com/news/age-of-empires-ii-definitive-edition-update-188329/)
closes the chicken/rabbit long-distance “funneling” exploit. Modified data sets
can change these behaviors; the whitelist is not a dynamic mechanics verifier.

The [September 2026 update](https://www.ageofempires.com/news/age-of-empires-ii-definitive-edition-update-185872/)
explicitly calls the pheasant a small unpushable prey animal. Newer ordinary
prey such as guanaco `2591`, rhea `2597`, and seal `2735` are deliberately not yet
classified as pushable: their existence and IDs are documented, but their actual
pushing behavior has not been independently verified for this observer. Unknown
species must not unlock a push-dependent build merely from their shared class.

## XS contract and information boundary

`food_observation_template.xs` has no `main` function or rule. The exporter embeds
it into the generated trainer before its callers. Initialize once, reset when
the player/session changes, and call the observer from the trainer's local
sampling path:

```text
trainerFoodInitialize()
trainerFoodReset()
trainerObserveStartingFood(player, gameTimeSeconds)
```

The observer also resets its own knowledge if its player changes or game time
moves backward. Reusing a process for a new game with the same player and no
observable backward time jump requires the caller's explicit reset. The intended
host call supplies the game's elapsed seconds, not real elapsed wall-clock time.

| API | Purpose and restriction |
| --- | --- |
| `xsUnsyncGetLocalPlayerId()` | Require an actual local player; reject other players and observer/Gaia contexts. |
| `xsGetPlayerUnitIds(player, 109, arrayID)` | Reuse an array to find own TC candidates only. |
| `xsGetPlayerUnitIds(0, objectID, arrayID)` | Enumerate Gaia instance IDs for a whitelisted species; this query itself is **not visibility-filtered**. Never publish its size or hidden candidates. |
| `xsDoesUnitExist(unitID)` | Validate a candidate before checking visibility. |
| `xsUnsyncIsUnitVisible(unitID, false, player)` | Mandatory boundary before reading an animal's species, HP or current position. Explored-but-currently-hidden is insufficient. |
| `xsGetUnitObjectId(unitID)` | Recheck the actual master ID against the species allowlist. |
| `xsGetUnitHitpoints(unitID)` | Accept live animals only; no remaining-food estimate is made. |
| `xsGetUnitPosition(unitID)` | Read only own TC or currently visible animal positions. |
| `xsVectorGetX` / `xsVectorGetY` | Planar map distance. Do not use X/Z or include elevation in the radius. |

The [developer XS reference](https://www.forgottenempires.net/age-of-empires-ii-definitive-edition/xs-scripting-in-age-of-empires-ii-definitive-edition)
documents `xsGetPlayerUnitIds` with player first and examples mapping
`vector(4, 4, -1)` to map position `(4, 4)`. The
[official September 2026 update](https://www.ageofempires.com/news/age-of-empires-ii-definitive-edition-update-185872/)
adds `xsUnsyncIsUnitVisible`; its player argument only works for the local
player. Current signatures/defaults are also in the
[XS Check prelude](https://github.com/Divy1211/xs-check/blob/main/xsc-core/prelude.xs).

Visibility-derived observations are unsynchronized local presentation state.
They must not be used to mutate units, resources, triggers, AI orders or other
synchronized gameplay. This code does not claim multiplayer/replay reliability.

## Bounds and diagnostic states

The observer stores at most 512 unique qualifying instance IDs. A sampling pass
checks at most 256 candidates per species, at most 3328 across the 13 whitelisted
species. Each species has its own round-robin cursor so a large deer population
cannot permanently starve small-game observations. Queries reuse arrays. This
internal scan budget does not expose a diagnostic based on hidden map-wide
animal counts; it can delay or miss brief observations in unusually large games.

Reaching the 512 already-visible qualifying-ID storage limit when another
qualifying observation is processed, or an invalid query result, latches
`trainerFoodObservationIncomplete = true`; retained counts stay lower bounds and
must not be presented as exhaustive. Repeated instance IDs do not increase
counts or trigger a false storage-overflow warning when the cache is exactly
full. Invalid instance IDs are never stored. Array allocation, query/array-size,
and dedup-cache write failures also fail closed. A
failed initialization is latched instead of repeatedly leaking partial
allocations on each sample; that script instance needs a fresh start.

| `trainerFoodObservationStatus` | Meaning |
| --- | --- |
| `0` | Waiting for an own TC anchor; food is unknown. |
| `1` | Observing the opening; counts describe positive observations only. |
| `2` | Opening observation window ended; retain the observed facts. |
| `3` | Incomplete because visible-observation storage is full or initialization/query/cache writing failed; report this explicitly. |
| `4` | Invalid local-player/time context; counts have been cleared. |

Status `1` or `2` never means that the area was exhaustively scouted. The
`trainerFoodHasAnchor` flag states only whether a fixed own-TC origin is known.
The 24-tile radius is a trainer policy, not a guarantee that every starting
resource on every map lies within it. In particular, standard map generation can
place regular hunt farther away. Unsupported species and missed short-lived
observations can also undercount. Unit-ID reuse or animal transformations in
custom scripted scenarios are not supported as a precise resource inventory.

## Why RMS metadata is not used as a shortcut

RMS loads the XS script, but merely wrapping a stock RMS does not expose the
random branch that generated a particular herd. `xsGetMapName`, `xsGetMapID` and
`xsGetMapSeed` describe the map, not observed local food. Even rules such as
[Arabia's matching near/far hunt type](https://www.ageofempires.com/news/age-of-empires-ii-definitive-edition-update-169123/)
are map/version-specific and should not reveal an unscouted patch. An explicitly
authored training map could provide a declared food profile in a future protocol;
this implementation does not pretend that such a generic metadata channel exists.

## Hunt-first does not mean “never eat sheep”

The [official food guide](https://www.ageofempires.com/learn-to-play/control-resources-aoe2/)
describes regular and aggressive hunt as fast food sources. A hunt-first variant
can use earlier boar lures and pushed regular hunt, while retaining sheep as a
bridge to avoid idle TC time or idle villagers. Small-game variants need their
own walk/drop-off/mill plan rather than instructions to push unpushable animals.

Raw collection speed alone does not include walking, crowding, drop-off trips,
decay, mill wood/build time, scout attention, or the cost of a missed villager.
Civilization rules also matter: [Briton shepherds work faster](https://www.forgottenempires.net/age-of-empires-ii-definitive-edition/civilizations/britons),
[Tatar herdables contain more food](https://www.forgottenempires.net/age-of-empires-ii-definitive-edition/civilizations/tatars),
and Gurjaras can keep livestock in mills for passive food, as reflected in the
[current extracted game strings](https://github.com/SiegeEngineers/aoe2techtree/blob/master/data/locales/en/strings.json).
These are reasons to author civ-aware openings, not to impose a universal zero-
sheep target. Exact numerical gather-rate targets and actual Mac behavior still
need in-game calibration; the trainer's measured rolling game-minute income is
the practical feedback signal.

## Required runtime checks

Before describing food-sensitive selection as in-game verified, test: unseen vs
currently visible vs explored-and-hidden hunt; ordinary and wild chickens; hares;
mixed food; repeated sightings; consumption and death; no TC and a second TC;
exact 24-tile and 600-second boundaries; player changes/time rollback; and capacity
diagnostics. Check that scouting suggestions never reveal the existence, amount,
type or current position of an animal that the player has not observed.
