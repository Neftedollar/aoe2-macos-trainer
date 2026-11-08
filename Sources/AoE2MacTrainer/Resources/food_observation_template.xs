// Starting-food observations for the local trainer, standard AoE2 DE data.
// Presentation only: never issue orders, change world state, or reveal fog.
// Counts mean unique LIVE animals observed near the first own Town Center.
// They are historical lower bounds, NOT current remaining food or safety.
// Zero means not observed/unknown, never "this food does not exist".

const int trainerFoodSpeciesCount = 13;
const int trainerFoodSeenCapacity = 512;
const int trainerFoodCandidatesPerSpecies = 256;
const int trainerFoodOpeningSeconds = 600;
const float trainerFoodRadiusSquared = 576.0; // 24 map tiles, X/Y plane.

bool trainerFoodInitialized = false;
bool trainerFoodInitializationFailed = false;
bool trainerFoodHasAnchor = false;
bool trainerFoodObservationIncomplete = false;
// 0 waiting for own TC; 1 observing; 2 opening ended;
// 3 incomplete (visible observation storage or query error); 4 invalid context.
int trainerFoodObservationStatus = 0;
int trainerObservedPushableHuntCount = 0;
int trainerObservedSmallGameCount = 0;
int trainerFoodPlayer = -1;
int trainerFoodLastTime = -1;
int trainerFoodSeenCount = 0;
float trainerFoodAnchorX = -1.0;
float trainerFoodAnchorY = -1.0;
int trainerFoodSpeciesIDs = -1;
int trainerFoodSpeciesCursors = -1;
int trainerFoodSeenUnitIDs = -1;
int trainerFoodCandidateIDs = -1;
int trainerFoodTownCenterIDs = -1;

void trainerFoodReset() {
    trainerFoodHasAnchor = false;
    trainerFoodObservationIncomplete = trainerFoodInitializationFailed;
    trainerFoodObservationStatus = 0;
    if (trainerFoodInitializationFailed) {
        trainerFoodObservationStatus = 3;
    }
    trainerObservedPushableHuntCount = 0;
    trainerObservedSmallGameCount = 0;
    trainerFoodPlayer = -1;
    trainerFoodLastTime = -1;
    trainerFoodSeenCount = 0;
    trainerFoodAnchorX = -1.0;
    trainerFoodAnchorY = -1.0;
    if (trainerFoodInitialized) {
        for (cursorIndex = 0; < trainerFoodSpeciesCount) {
            xsArraySetInt(trainerFoodSpeciesCursors, cursorIndex, 0);
        }
    }
    // The old array entries are outside trainerFoodSeenCount and ignored.
    // Reuse allocations rather than allocating a new array each match/tick.
}

void trainerFoodInitialize() {
    if (trainerFoodInitialized || trainerFoodInitializationFailed) {
        return;
    }
    trainerFoodSpeciesIDs = xsArrayCreateInt(trainerFoodSpeciesCount, -1,
        "trainer_food_species");
    trainerFoodSpeciesCursors = xsArrayCreateInt(trainerFoodSpeciesCount, 0,
        "trainer_food_species_cursors");
    trainerFoodSeenUnitIDs = xsArrayCreateInt(trainerFoodSeenCapacity, -1,
        "trainer_food_seen_units");
    trainerFoodCandidateIDs = xsArrayCreateInt(1, -1,
        "trainer_food_candidates");
    trainerFoodTownCenterIDs = xsArrayCreateInt(1, -1,
        "trainer_food_town_centers");
    if (trainerFoodSpeciesIDs < 0 || trainerFoodSpeciesCursors < 0 ||
        trainerFoodSeenUnitIDs < 0 || trainerFoodCandidateIDs < 0 ||
        trainerFoodTownCenterIDs < 0) {
        // Do not retry partial allocations each tick or count without a cache.
        trainerFoodInitializationFailed = true;
        trainerFoodObservationIncomplete = true;
        trainerFoodObservationStatus = 3;
        return;
    }

    // Pushable regular hunt: deer, zebra, ostrich, ibex, gazelle, argali.
    xsArraySetInt(trainerFoodSpeciesIDs, 0, 65);
    xsArraySetInt(trainerFoodSpeciesIDs, 1, 1019);
    xsArraySetInt(trainerFoodSpeciesIDs, 2, 1026);
    xsArraySetInt(trainerFoodSpeciesIDs, 3, 1239);
    xsArraySetInt(trainerFoodSpeciesIDs, 4, 1796);
    xsArraySetInt(trainerFoodSpeciesIDs, 5, 1896);
    // Wild chickens, two hares, arctic hare and pheasant. Not herdable chickens.
    xsArraySetInt(trainerFoodSpeciesIDs, 6, 2084);
    xsArraySetInt(trainerFoodSpeciesIDs, 7, 2086);
    xsArraySetInt(trainerFoodSpeciesIDs, 8, 2088);
    xsArraySetInt(trainerFoodSpeciesIDs, 9, 2098);
    xsArraySetInt(trainerFoodSpeciesIDs, 10, 2099);
    xsArraySetInt(trainerFoodSpeciesIDs, 11, 2100);
    xsArraySetInt(trainerFoodSpeciesIDs, 12, 2739);
    trainerFoodInitialized = true;
    trainerFoodReset();
}

int trainerFoodCategory(int objectID = -1) {
    if (objectID == 65 || objectID == 1019 || objectID == 1026 ||
        objectID == 1239 || objectID == 1796 || objectID == 1896) {
        return (1);
    }
    if (objectID == 2084 || objectID == 2086 || objectID == 2088 ||
        objectID == 2098 || objectID == 2099 || objectID == 2100 ||
        objectID == 2739) {
        return (2);
    }
    // Never classify all prey as food: some foxes supply gold. Generic
    // carcasses cannot reliably identify the original animal species.
    return (0);
}

bool trainerFoodWasObserved(int unitID = -1) {
    for (seenIndex = 0; < trainerFoodSeenCount) {
        if (xsArrayGetInt(trainerFoodSeenUnitIDs, seenIndex) == unitID) {
            return (true);
        }
    }
    return (false);
}

void trainerFoodRemember(int unitID = -1, int category = 0) {
    if (unitID < 0 || category < 1 || category > 2) {
        return;
    }
    // Re-sighting a stored animal needs no new capacity, even when the cache
    // is exactly full. Only an unseen qualifying instance makes it incomplete.
    if (trainerFoodWasObserved(unitID)) {
        return;
    }
    if (trainerFoodSeenCount >= trainerFoodSeenCapacity) {
        trainerFoodObservationIncomplete = true;
        trainerFoodObservationStatus = 3;
        return;
    }
    if (xsArraySetInt(trainerFoodSeenUnitIDs, trainerFoodSeenCount, unitID) == false) {
        trainerFoodObservationIncomplete = true;
        trainerFoodObservationStatus = 3;
        return;
    }
    trainerFoodSeenCount = trainerFoodSeenCount + 1;
    if (category == 1) {
        trainerObservedPushableHuntCount = trainerObservedPushableHuntCount + 1;
    } else {
        trainerObservedSmallGameCount = trainerObservedSmallGameCount + 1;
    }
}

void trainerFoodFindAnchor(int player = -1) {
    if (trainerFoodHasAnchor) {
        return;
    }
    // 109 is the standard Town Center master ID, not an enemy/global query.
    int ids = xsGetPlayerUnitIds(player, 109, trainerFoodTownCenterIDs);
    if (ids < 0) {
        trainerFoodObservationIncomplete = true;
        return;
    }
    int count = xsArrayGetSize(ids);
    if (count < 0) {
        trainerFoodObservationIncomplete = true;
        return;
    }
    for (tcIndex = 0; < count) {
        int tc = xsArrayGetInt(ids, tcIndex);
        if (xsDoesUnitExist(tc) && xsGetUnitOwner(tc) == player) {
            vector position = xsGetUnitPosition(tc);
            float x = xsVectorGetX(position);
            float y = xsVectorGetY(position);
            if (x >= 0.0 && y >= 0.0) {
                trainerFoodAnchorX = x;
                trainerFoodAnchorY = y;
                trainerFoodHasAnchor = true;
                return;
            }
        }
    }
}

void trainerFoodObserveSpecies(int player = -1, int objectID = -1,
    int speciesSlot = 0) {
    int ids = xsGetPlayerUnitIds(0, objectID, trainerFoodCandidateIDs);
    if (ids < 0) {
        trainerFoodObservationIncomplete = true;
        return;
    }
    int count = xsArrayGetSize(ids);
    if (count < 0) {
        trainerFoodObservationIncomplete = true;
        return;
    }
    if (count == 0) {
        xsArraySetInt(trainerFoodSpeciesCursors, speciesSlot, 0);
        return;
    }
    // Round-robin independently per species: a large hidden deer population
    // cannot permanently starve visible small game. Throttling is internal;
    // never expose a diagnostic derived from unseen map-wide animal counts.
    int start = xsArrayGetInt(trainerFoodSpeciesCursors, speciesSlot) % count;
    int checks = count;
    if (checks > trainerFoodCandidatesPerSpecies) {
        checks = trainerFoodCandidatesPerSpecies;
    }
    for (foodOffset = 0; < checks) {
        int foodIndex = (start + foodOffset) % count;
        int animal = xsArrayGetInt(ids, foodIndex);
        if (xsDoesUnitExist(animal)) {
            // Critical information boundary: do not read a Gaia animal's
            // current position, HP, species or resource amount through fog.
            // Even explored-but-not-visible objects must not pass this gate.
            if (xsUnsyncIsUnitVisible(animal, false, player)) {
                int category = trainerFoodCategory(xsGetUnitObjectId(animal));
                if (category > 0 && xsGetUnitHitpoints(animal) > 0.0) {
                    vector position = xsGetUnitPosition(animal);
                    float x = xsVectorGetX(position);
                    float y = xsVectorGetY(position);
                    if (x >= 0.0 && y >= 0.0) {
                        float dx = x - trainerFoodAnchorX;
                        float dy = y - trainerFoodAnchorY;
                        if (dx * dx + dy * dy <= trainerFoodRadiusSquared) {
                            trainerFoodRemember(animal, category);
                        }
                    }
                }
            }
        }
    }
    xsArraySetInt(trainerFoodSpeciesCursors, speciesSlot, (start + checks) % count);
}

void trainerObserveStartingFood(int player = -1, int now = 0) {
    infiniteLoopLimit = 1000000;
    trainerFoodInitialize();
    if (trainerFoodInitialized == false) {
        trainerFoodObservationIncomplete = true;
        trainerFoodObservationStatus = 3;
        return;
    }
    int localPlayer = xsUnsyncGetLocalPlayerId();
    if (player < 1 || localPlayer < 1 || player != localPlayer || now < 0) {
        trainerFoodReset();
        trainerFoodObservationStatus = 4;
        return;
    }
    if (trainerFoodPlayer != player ||
        (trainerFoodLastTime >= 0 && now < trainerFoodLastTime)) {
        trainerFoodReset();
        trainerFoodPlayer = player;
    }
    trainerFoodLastTime = now;
    if (now > trainerFoodOpeningSeconds) {
        trainerFoodObservationStatus = 2;
        if (trainerFoodObservationIncomplete) {
            trainerFoodObservationStatus = 3;
        }
        return;
    }
    trainerFoodFindAnchor(player);
    if (trainerFoodHasAnchor == false) {
        trainerFoodObservationStatus = 0;
        if (trainerFoodObservationIncomplete) {
            trainerFoodObservationStatus = 3;
        }
        return;
    }
    for (speciesIndex = 0; < trainerFoodSpeciesCount) {
        trainerFoodObserveSpecies(player,
            xsArrayGetInt(trainerFoodSpeciesIDs, speciesIndex), speciesIndex);
    }
    trainerFoodObservationStatus = 1;
    if (trainerFoodObservationIncomplete) {
        trainerFoodObservationStatus = 3;
    }
}
