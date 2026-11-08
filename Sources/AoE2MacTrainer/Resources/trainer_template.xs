// AoE2 Mac Trainer - GENERATED FILE TEMPLATE
// The app embeds a JSON build catalog here. XS detects the actual local civ.
// Runs only in a custom RMS/scenario that explicitly loads this file.
// No OCR, memory injection, file telemetry, enemy inspection, or world effects.
// Runtime bridge from the macOS overlay/hotkeys is NOT implemented.

const int trainerWindowSeconds = 60;
const int trainerHistorySize = 64;
// At a two-second sampling cadence, larger holes are not interpolated.
const int trainerMaxSampleGap = 6;
int trainerWindowStatus = 0; // 0 warmup, 1 ready, 2 gap, 3 counter/time reset
int trainerWindowBefore = -1;
int trainerWindowAfter = -1;
float trainerWindowFraction = 0.0;
int trainerWindowCoverage = 0;
bool trainerRecentReset = false;

bool trainerCatalogReady = false;
int trainerPlayer = -1;
int trainerCivilization = -1;
int trainerSampleCount = 0;
int trainerWriteIndex = 0;
int trainerSampleTimes = -1;
int trainerTotalsFood = -1;
int trainerTotalsWood = -1;
int trainerTotalsGold = -1;
int trainerTotalsStone = -1;
int trainerWorkersFood = -1;
int trainerWorkersWood = -1;
int trainerWorkersGold = -1;
int trainerWorkersStone = -1;
int trainerVillagerIDs = -1;

// Catalog arrays are allocated once. Switching plans only changes indices.
int trainerBuildCount = 0;
int trainerPreferredBuild = -1;
int trainerBuildNames = -1;
int trainerBuildMaps = -1;
int trainerBuildEnabled = -1;
int trainerAllowedPairCount = 0;
int trainerAllowedBuilds = -1;
int trainerAllowedCivilizations = -1;
int trainerEligibleBuilds = -1;
int trainerEligibleBuildCount = 0;
int trainerSelectedBuildSlot = -1;
int trainerSelectedBuild = -1;
int trainerSelectedSteps = -1;
int trainerSelectedStepCount = 0;
int trainerManualStepSlot = -1;

int trainerStepCount = 0;
int trainerStepBuilds = -1;
int trainerStepEnabled = -1;
int trainerStepUsesIncludeOnly = -1;
int trainerIncludedPairCount = 0;
int trainerIncludedSteps = -1;
int trainerIncludedCivilizations = -1;
int trainerExcludedPairCount = 0;
int trainerExcludedSteps = -1;
int trainerExcludedCivilizations = -1;

int trainerStepTimes = -1;
int trainerStepVillagers = -1;
int trainerStepFood = -1;
int trainerStepWood = -1;
int trainerStepGold = -1;
int trainerStepStone = -1;
int trainerStepDoneTimes = -1;
int trainerStepLabels = -1;
int trainerStepUnitStarts = -1;
int trainerStepUnitCounts = -1;
int trainerUnitGoalObjects = -1;
int trainerUnitGoalCounts = -1;
int trainerUnitGoalLabels = -1;
int trainerStepTechStarts = -1;
int trainerStepTechCounts = -1;
int trainerTechGoalIDs = -1;
int trainerTechGoalLabels = -1;

void trainerInitializeCatalog() {
    // @CATALOG_SETUP@
}

void trainerSelectBuildSlot(int slot = 0) {
    infiniteLoopLimit = 100000;
    trainerSelectedStepCount = 0;
    trainerManualStepSlot = -1;
    trainerSelectedBuildSlot = -1;
    trainerSelectedBuild = -1;
    if (slot < 0 || slot >= trainerEligibleBuildCount) {
        return;
    }
    trainerSelectedBuildSlot = slot;
    trainerSelectedBuild = xsArrayGetInt(trainerEligibleBuilds, slot);
    for (i = 0; < trainerStepCount) {
        if (xsArrayGetInt(trainerStepBuilds, i) == trainerSelectedBuild &&
            xsArrayGetBool(trainerStepEnabled, i)) {
            xsArraySetInt(trainerSelectedSteps, trainerSelectedStepCount, i);
            trainerSelectedStepCount = trainerSelectedStepCount + 1;
        }
    }
    // Do NOT reset completion timestamps here. All applicable plans are
    // observed throughout the match, including plans not currently displayed.
}

bool trainerRefreshContext() {
    infiniteLoopLimit = 100000;
    if (trainerCatalogReady == false) {
        return (false);
    }
    int player = xsUnsyncGetLocalPlayerId();
    if (player < 1) {
        trainerPlayer = -1;
        trainerCivilization = -1;
        trainerEligibleBuildCount = 0;
        trainerSelectBuildSlot(-1);
        return (false);
    }
    int civilization = xsGetPlayerCivilization(player);
    if (player == trainerPlayer && civilization == trainerCivilization) {
        return (true);
    }

    trainerPlayer = player;
    trainerCivilization = civilization;
    trainerSampleCount = 0;
    trainerWriteIndex = 0;
    trainerRecentReset = false;
    trainerWindowStatus = 0;
    trainerEligibleBuildCount = 0;
    for (buildIndex = 0; < trainerBuildCount) {
        xsArraySetBool(trainerBuildEnabled, buildIndex, false);
    }
    // A strict allowlist: an unknown or unsupported civ enables no build.
    for (allowedIndex = 0; < trainerAllowedPairCount) {
        if (xsArrayGetInt(trainerAllowedCivilizations, allowedIndex) == civilization) {
            xsArraySetBool(trainerBuildEnabled,
                xsArrayGetInt(trainerAllowedBuilds, allowedIndex), true);
        }
    }

    for (stepIndex = 0; < trainerStepCount) {
        int stepBuild = xsArrayGetInt(trainerStepBuilds, stepIndex);
        bool enabled = xsArrayGetBool(trainerBuildEnabled, stepBuild) &&
                       xsArrayGetBool(trainerStepUsesIncludeOnly, stepIndex) == false;
        xsArraySetBool(trainerStepEnabled, stepIndex, enabled);
        xsArraySetInt(trainerStepDoneTimes, stepIndex, -1);
    }
    for (includedIndex = 0; < trainerIncludedPairCount) {
        if (xsArrayGetInt(trainerIncludedCivilizations, includedIndex) == civilization) {
            int includedStep = xsArrayGetInt(trainerIncludedSteps, includedIndex);
            int ownerBuild = xsArrayGetInt(trainerStepBuilds, includedStep);
            xsArraySetBool(trainerStepEnabled, includedStep,
                xsArrayGetBool(trainerBuildEnabled, ownerBuild));
        }
    }
    // Exclusion is applied last, so it always wins over an include.
    for (excludedIndex = 0; < trainerExcludedPairCount) {
        if (xsArrayGetInt(trainerExcludedCivilizations, excludedIndex) == civilization) {
            xsArraySetBool(trainerStepEnabled,
                xsArrayGetInt(trainerExcludedSteps, excludedIndex), false);
        }
    }

    int preferredSlot = -1;
    for (eligibleIndex = 0; < trainerBuildCount) {
        if (xsArrayGetBool(trainerBuildEnabled, eligibleIndex)) {
            xsArraySetInt(trainerEligibleBuilds, trainerEligibleBuildCount, eligibleIndex);
            if (eligibleIndex == trainerPreferredBuild) {
                preferredSlot = trainerEligibleBuildCount;
            }
            trainerEligibleBuildCount = trainerEligibleBuildCount + 1;
        }
    }
    if (preferredSlot >= 0) {
        trainerSelectBuildSlot(preferredSlot);
    } else if (trainerEligibleBuildCount > 0) {
        trainerSelectBuildSlot(0);
    } else {
        trainerSelectBuildSlot(-1);
    }
    return (true);
}

// Optional Scenario Editor Script Call entry points. No keyboard binding or
// connection to Ctrl+Option+B in the external macOS application is implied.
void trainerNextBuild() {
    if (trainerRefreshContext() == false || trainerEligibleBuildCount == 0) {
        return;
    }
    trainerSelectBuildSlot((trainerSelectedBuildSlot + 1) % trainerEligibleBuildCount);
}

void trainerPreviousBuild() {
    if (trainerRefreshContext() == false || trainerEligibleBuildCount == 0) {
        return;
    }
    trainerSelectBuildSlot((trainerSelectedBuildSlot + trainerEligibleBuildCount - 1) %
                           trainerEligibleBuildCount);
}

void main() {
    if (trainerCatalogReady) {
        return;
    }
    trainerSampleTimes = xsArrayCreateInt(trainerHistorySize, -1, "trainer_sample_times");
    trainerTotalsFood = xsArrayCreateFloat(trainerHistorySize, 0.0, "trainer_food_totals");
    trainerTotalsWood = xsArrayCreateFloat(trainerHistorySize, 0.0, "trainer_wood_totals");
    trainerTotalsGold = xsArrayCreateFloat(trainerHistorySize, 0.0, "trainer_gold_totals");
    trainerTotalsStone = xsArrayCreateFloat(trainerHistorySize, 0.0, "trainer_stone_totals");
    trainerWorkersFood = xsArrayCreateInt(trainerHistorySize, 0, "trainer_workers_food");
    trainerWorkersWood = xsArrayCreateInt(trainerHistorySize, 0, "trainer_workers_wood");
    trainerWorkersGold = xsArrayCreateInt(trainerHistorySize, 0, "trainer_workers_gold");
    trainerWorkersStone = xsArrayCreateInt(trainerHistorySize, 0, "trainer_workers_stone");
    trainerVillagerIDs = xsArrayCreateInt(1, -1, "trainer_villager_ids");
    trainerInitializeCatalog();
    trainerCatalogReady = true;
}

// Observes villagers' current task target and carried resource. Drop-off,
// idle/building tasks, and special food sources such as Khitan pastures can
// be misclassified; these counts and per-villager rates are APPROXIMATE.
void trainerCountWorkers(int player = 0) {
    infiniteLoopLimit = 100000;
    int ids = xsGetPlayerUnitIds(player, cVillagerClass, trainerVillagerIDs);
    int workers = xsArrayGetSize(ids);
    int food = 0;
    int wood = 0;
    int gold = 0;
    int stone = 0;
    for (i = 0; < workers) {
        int villager = xsArrayGetInt(ids, i);
        int target = xsGetUnitTargetUnitId(villager);
        int unitClass = -1;
        if (target >= 0 && xsDoesUnitExist(target)) {
            unitClass = xsGetUnitClass(target);
            // Object-class selectors use 900 + the raw data class. Accept
            // either representation; both occur across XS API descriptions.
            if (unitClass >= 0 && unitClass <= 64) {
                unitClass = unitClass + 900;
            }
        }

        if (unitClass == cTreeClass) {
            wood = wood + 1;
        } else if (unitClass == cGoldMine) {
            gold = gold + 1;
        } else if (unitClass == cStoneMineClass) {
            stone = stone + 1;
        } else if (unitClass == cFarmClass || unitClass == cForageBushClass ||
                   unitClass == cPreyAnimalClass || unitClass == cDomesticAnimalClass ||
                   unitClass == cLivestockClass || unitClass == cShoreFish ||
                   unitClass == cSeaFishClass || unitClass == cDeepSeaFishClass) {
            food = food + 1;
        } else if (xsGetUnitAttributeHeld(villager, cAttributeWood) > 0) {
            wood = wood + 1;
        } else if (xsGetUnitAttributeHeld(villager, cAttributeGold) > 0) {
            gold = gold + 1;
        } else if (xsGetUnitAttributeHeld(villager, cAttributeStone) > 0) {
            stone = stone + 1;
        } else if (xsGetUnitAttributeHeld(villager, cAttributeFood) > 0 ||
                   xsGetUnitAttributeHeld(villager, cAttributeMeat) > 0 ||
                   xsGetUnitAttributeHeld(villager, cAttributeBerries) > 0 ||
                   xsGetUnitAttributeHeld(villager, cAttributeFish) > 0) {
            food = food + 1;
        }
    }

    xsArraySetInt(trainerWorkersFood, trainerWriteIndex, food);
    xsArraySetInt(trainerWorkersWood, trainerWriteIndex, wood);
    xsArraySetInt(trainerWorkersGold, trainerWriteIndex, gold);
    xsArraySetInt(trainerWorkersStone, trainerWriteIndex, stone);
}

// Chronological ring indexing, including when the fixed-size buffer wraps.
int trainerHistoryIndex(int offset = 0) {
    return ((trainerWriteIndex + trainerHistorySize - trainerSampleCount + offset) % trainerHistorySize);
}

// Validate complete coverage of [now - 60, now]. Small boundary intervals
// use linear cumulative-counter interpolation; gaps >6s are explicitly unknown.
void trainerPrepareWindow(int now = 0) {
    trainerWindowStatus = 0;
    trainerWindowBefore = -1;
    trainerWindowAfter = -1;
    trainerWindowFraction = 0.0;
    trainerWindowCoverage = 0;
    if (trainerRecentReset) {
        trainerWindowStatus = 3;
    }
    if (trainerSampleCount < 2) {
        return;
    }
    int oldest = trainerHistoryIndex(0);
    trainerWindowCoverage = now - xsArrayGetInt(trainerSampleTimes, oldest);
    if (trainerWindowCoverage < trainerWindowSeconds) {
        return;
    }
    int cutoff = now - trainerWindowSeconds;
    int intervalCount = trainerSampleCount - 1;
    for (interval = 0; < intervalCount) {
        int before = trainerHistoryIndex(interval);
        int after = trainerHistoryIndex(interval + 1);
        int beforeTime = xsArrayGetInt(trainerSampleTimes, before);
        int afterTime = xsArrayGetInt(trainerSampleTimes, after);
        int gap = afterTime - beforeTime;
        if (afterTime > cutoff && beforeTime < now) {
            if (gap <= 0 || gap > trainerMaxSampleGap) {
                trainerWindowStatus = 2;
                return;
            }
        }
        if (beforeTime <= cutoff && afterTime >= cutoff && gap > 0) {
            trainerWindowBefore = before;
            trainerWindowAfter = after;
            trainerWindowFraction = 1.0 * (cutoff - beforeTime) / gap;
        }
    }
    if (trainerWindowBefore < 0) {
        trainerWindowStatus = 2;
        return;
    }
    trainerRecentReset = false;
    trainerWindowStatus = 1;
}

float trainerRate(int totalsArray = 0, float nowTotal = 0.0) {
    if (trainerWindowStatus != 1) {
        return (-1.0);
    }
    float before = xsArrayGetFloat(totalsArray, trainerWindowBefore);
    float after = xsArrayGetFloat(totalsArray, trainerWindowAfter);
    float baseline = before + (after - before) * trainerWindowFraction;
    float gained = nowTotal - baseline;
    if (after < before || gained < 0.0) {
        return (-1.0);
    }
    // The window is exactly 60 GAME seconds, so gain equals resources/game-minute.
    return (gained);
}

float trainerAverageWorkers(int arrayID = 0, int now = 0) {
    if (trainerWindowStatus != 1) {
        return (-1.0);
    }
    int cutoff = now - trainerWindowSeconds;
    int intervalCount = trainerSampleCount - 1;
    float workerSeconds = 0.0;
    for (interval = 0; < intervalCount) {
        int before = trainerHistoryIndex(interval);
        int after = trainerHistoryIndex(interval + 1);
        int start = xsArrayGetInt(trainerSampleTimes, before);
        int end = xsArrayGetInt(trainerSampleTimes, after);
        if (start < cutoff) {
            start = cutoff;
        }
        if (end > now) {
            end = now;
        }
        if (end > start) {
            // Sample-and-hold, time-weighted; never truncate the average to int.
            // Actual reassignment between samples and task classification remain approximate.
            workerSeconds = workerSeconds + 1.0 * xsArrayGetInt(arrayID, before) * (end - start);
        }
    }
    return (workerSeconds / trainerWindowSeconds);
}

string trainerOneDecimal(float value = 0.0) {
    int tenths = value * 10.0 + 0.5;
    return ("" + (tenths / 10) + "." + (tenths % 10));
}

string trainerWindowCaption() {
    if (trainerWindowStatus == 1) {
        return ("ECONOMY | trailing 60 game seconds | sampled estimates ~");
    }
    if (trainerWindowStatus == 2) {
        return ("ECONOMY | DATA GAP: need 60s of continuous samples");
    }
    int remaining = trainerWindowSeconds - trainerWindowCoverage;
    if (trainerWindowStatus == 3) {
        return ("ECONOMY | COUNTER/TIME RESET: warmup " + remaining + "s");
    }
    return ("ECONOMY | WARMUP: " + remaining + " game seconds remaining");
}

string trainerRateLine(string resourceName = "", float rate = 0.0, float workers = 0.0) {
    if (rate < 0.0 || workers < 0.0) {
        return (resourceName + " --/min | avg -- vils | --/vil/min");
    }
    string line = resourceName + " ~" + trainerOneDecimal(rate) + "/min | avg ~" +
                  trainerOneDecimal(workers) + " vils";
    if (workers > 0.0) {
        line = line + " | ~" + trainerOneDecimal(rate / workers) + "/vil/min";
    } else {
        line = line + " | --/vil/min";
    }
    return (line);
}

// A time deadline or an imperative instruction is not evidence of completion.
// Technology goals require the COMPLETED state (3), not queued/researching.
bool trainerHasGoal(int step = 0) {
    return (xsArrayGetInt(trainerStepVillagers, step) >= 0 ||
           xsArrayGetInt(trainerStepFood, step) > 0 ||
           xsArrayGetInt(trainerStepWood, step) > 0 ||
           xsArrayGetInt(trainerStepGold, step) > 0 ||
           xsArrayGetInt(trainerStepStone, step) > 0 ||
           xsArrayGetInt(trainerStepUnitCounts, step) > 0 ||
           xsArrayGetInt(trainerStepTechCounts, step) > 0);
}

bool trainerGoalIsMet(int step = 0, int player = 0, int villagers = 0,
                      int foodWorkers = 0, int woodWorkers = 0, int goldWorkers = 0, int stoneWorkers = 0) {
    int target = xsArrayGetInt(trainerStepVillagers, step);
    if (target >= 0 && villagers < target) {
        return (false);
    }
    target = xsArrayGetInt(trainerStepFood, step);
    if (target > 0 && foodWorkers < target) {
        return (false);
    }
    target = xsArrayGetInt(trainerStepWood, step);
    if (target > 0 && woodWorkers < target) {
        return (false);
    }
    target = xsArrayGetInt(trainerStepGold, step);
    if (target > 0 && goldWorkers < target) {
        return (false);
    }
    target = xsArrayGetInt(trainerStepStone, step);
    if (target > 0 && stoneWorkers < target) {
        return (false);
    }

    int unitStart = xsArrayGetInt(trainerStepUnitStarts, step);
    int unitEnd = unitStart + xsArrayGetInt(trainerStepUnitCounts, step);
    for (unitIndex = unitStart; < unitEnd) {
        if (xsGetObjectCount(player, xsArrayGetInt(trainerUnitGoalObjects, unitIndex)) <
            xsArrayGetInt(trainerUnitGoalCounts, unitIndex)) {
            return (false);
        }
    }
    int techStart = xsArrayGetInt(trainerStepTechStarts, step);
    int techEnd = techStart + xsArrayGetInt(trainerStepTechCounts, step);
    for (techIndex = techStart; < techEnd) {
        if (xsGetTechState(xsArrayGetInt(trainerTechGoalIDs, techIndex), player) != 3) {
            return (false);
        }
    }
    return (true);
}

// Track every civ-eligible plan, not just the selected one. Switching plans
// then retains their true first OBSERVED achievement times. If this script
// starts late, it cannot reconstruct achievements that happened beforehand.
void trainerTrackGoals(int player = 0, int now = 0, int villagers = 0,
                       int foodWorkers = 0, int woodWorkers = 0, int goldWorkers = 0, int stoneWorkers = 0) {
    infiniteLoopLimit = 100000;
    for (i = 0; < trainerStepCount) {
        if (xsArrayGetBool(trainerStepEnabled, i) &&
            xsArrayGetInt(trainerStepDoneTimes, i) < 0 && trainerHasGoal(i) &&
            trainerGoalIsMet(i, player, villagers, foodWorkers, woodWorkers, goldWorkers, stoneWorkers)) {
            xsArraySetInt(trainerStepDoneTimes, i, now);
        }
    }
}

// A deadline is not a start time. Show upcoming incomplete checkpoints before
// they are due. Past unmet targets remain in MISSED CHECKPOINTS; if no future
// target remains, the most recent overdue checkpoint stays visible.
int trainerActiveStepSlot(int now = 0) {
    if (trainerSelectedStepCount == 0) {
        return (-1);
    }
    if (trainerManualStepSlot >= 0 && trainerManualStepSlot < trainerSelectedStepCount) {
        return (trainerManualStepSlot);
    }
    int lastOverdue = -1;
    for (slot = 0; < trainerSelectedStepCount) {
        int step = xsArrayGetInt(trainerSelectedSteps, slot);
        if (xsArrayGetInt(trainerStepDoneTimes, step) < 0) {
            int deadline = xsArrayGetInt(trainerStepTimes, step);
            if (deadline < 0 || now <= deadline) {
                return (slot);
            }
            lastOverdue = slot;
        }
    }
    if (lastOverdue >= 0) {
        return (lastOverdue);
    }
    return (trainerSelectedStepCount - 1);
}

// Optional, UNBOUND Scenario Editor Script Call hooks. These only select
// which instruction to display; they never mark a goal as achieved.
void trainerNextStep() {
    if (trainerRefreshContext() == false || trainerSelectedStepCount == 0) {
        return;
    }
    int next = trainerActiveStepSlot(xsGetGameTime()) + 1;
    if (next >= trainerSelectedStepCount) {
        next = trainerSelectedStepCount - 1;
    }
    trainerManualStepSlot = next;
}

void trainerPreviousStep() {
    if (trainerRefreshContext() == false || trainerSelectedStepCount == 0) {
        return;
    }
    int previous = trainerActiveStepSlot(xsGetGameTime()) - 1;
    if (previous < 0) {
        previous = 0;
    }
    trainerManualStepSlot = previous;
}

void trainerResumeTimeline() {
    trainerManualStepSlot = -1;
}

string trainerStepStatus(int step = 0, int now = 0) {
    if (trainerHasGoal(step) == false) {
        return ("MANUAL ACTION");
    }
    int deadline = xsArrayGetInt(trainerStepTimes, step);
    int achieved = xsArrayGetInt(trainerStepDoneTimes, step);
    if (achieved >= 0) {
        if (deadline < 0) {
            return ("GOAL MET");
        }
        int offset = achieved - deadline;
        if (offset <= 0) {
            return ("MET EARLY " + (0 - offset) + "s");
        }
        return ("MET LATE +" + offset + "s");
    }
    if (deadline >= 0 && now > deadline) {
        return ("LATE +" + (now - deadline) + "s");
    }
    if (deadline >= 0) {
        return ("DUE IN " + (deadline - now) + "s");
    }
    return ("WAITING");
}

string trainerGoalProgress(int step = 0, int player = 0, int villagers = 0,
                           int foodWorkers = 0, int woodWorkers = 0, int goldWorkers = 0, int stoneWorkers = 0) {
    string line = "TARGET:";
    int target = xsArrayGetInt(trainerStepVillagers, step);
    if (target >= 0) {
        line = line + " V " + villagers + "/" + target;
    }
    target = xsArrayGetInt(trainerStepFood, step);
    if (target > 0) {
        line = line + " F ~" + foodWorkers + "/" + target;
    }
    target = xsArrayGetInt(trainerStepWood, step);
    if (target > 0) {
        line = line + " W ~" + woodWorkers + "/" + target;
    }
    target = xsArrayGetInt(trainerStepGold, step);
    if (target > 0) {
        line = line + " G ~" + goldWorkers + "/" + target;
    }
    target = xsArrayGetInt(trainerStepStone, step);
    if (target > 0) {
        line = line + " S ~" + stoneWorkers + "/" + target;
    }
    int unitStart = xsArrayGetInt(trainerStepUnitStarts, step);
    int unitEnd = unitStart + xsArrayGetInt(trainerStepUnitCounts, step);
    for (unitIndex = unitStart; < unitEnd) {
        int id = xsArrayGetInt(trainerUnitGoalObjects, unitIndex);
        int minimum = xsArrayGetInt(trainerUnitGoalCounts, unitIndex);
        line = line + " " + xsArrayGetString(trainerUnitGoalLabels, unitIndex) + " " +
               xsGetObjectCount(player, id) + "/" + minimum;
    }
    int techStart = xsArrayGetInt(trainerStepTechStarts, step);
    int techEnd = techStart + xsArrayGetInt(trainerStepTechCounts, step);
    for (techIndex = techStart; < techEnd) {
        line = line + " " + xsArrayGetString(trainerTechGoalLabels, techIndex);
        if (xsGetTechState(xsArrayGetInt(trainerTechGoalIDs, techIndex), player) == 3) {
            line = line + " DONE";
        } else {
            line = line + " WAIT";
        }
    }
    return (line);
}

int trainerMissedCheckpoints(int now = 0) {
    int missed = 0;
    for (slot = 0; < trainerSelectedStepCount) {
        int step = xsArrayGetInt(trainerSelectedSteps, slot);
        int deadline = xsArrayGetInt(trainerStepTimes, step);
        int achieved = xsArrayGetInt(trainerStepDoneTimes, step);
        if (deadline >= 0 && deadline < now && trainerHasGoal(step) &&
            (achieved < 0 || achieved > deadline)) {
            missed = missed + 1;
        }
    }
    return (missed);
}

rule trainerMetrics
    active
    minInterval 2
{
    infiniteLoopLimit = 100000;
    if (trainerRefreshContext() == false) {
        return;
    }
    // Local, unsynced values ONLY affect local presentation and observations.
    // NEVER use this player-dependent state to drive synchronized world effects.
    int player = trainerPlayer;
    int now = xsGetGameTime();
    float foodTotal = xsPlayerAttribute(player, 166);
    float woodTotal = xsPlayerAttribute(player, 167);
    float stoneTotal = xsPlayerAttribute(player, 168);
    float goldTotal = xsPlayerAttribute(player, 169);
    int villagers = xsPlayerAttribute(player, 38);

    if (foodTotal < 0.0 || woodTotal < 0.0 || goldTotal < 0.0 || stoneTotal < 0.0) {
        trainerSampleCount = 0;
        trainerWriteIndex = 0;
        trainerRecentReset = true;
        xsDisplayInstructions("TRAINER | ECONOMY DATA UNAVAILABLE: invalid resource counter",
                              3, player, -1, 0, false, false, "", player);
        return;
    }

    // A reset/rewind invalidates the measurement window; never report a negative
    // rate or join observations from different time/counter histories.
    if (trainerSampleCount > 0) {
        int previousIndex = trainerHistoryIndex(trainerSampleCount - 1);
        int previousTime = xsArrayGetInt(trainerSampleTimes, previousIndex);
        if (now < previousTime ||
            foodTotal < xsArrayGetFloat(trainerTotalsFood, previousIndex) ||
            woodTotal < xsArrayGetFloat(trainerTotalsWood, previousIndex) ||
            goldTotal < xsArrayGetFloat(trainerTotalsGold, previousIndex) ||
            stoneTotal < xsArrayGetFloat(trainerTotalsStone, previousIndex)) {
            trainerSampleCount = 0;
            trainerWriteIndex = 0;
            trainerRecentReset = true;
            if (now < previousTime) {
                for (resetStep = 0; < trainerStepCount) {
                    xsArraySetInt(trainerStepDoneTimes, resetStep, -1);
                }
            }
        } else if (now == previousTime) {
            // A paused/repeated simulation instant carries no elapsed worker time.
            return;
        }
    }

    // Cumulative collected counters, NOT the current stockpile. Spending is
    // excluded, but non-villager income may contribute to these game counters.
    xsArraySetInt(trainerSampleTimes, trainerWriteIndex, now);
    xsArraySetFloat(trainerTotalsFood, trainerWriteIndex, foodTotal);
    xsArraySetFloat(trainerTotalsWood, trainerWriteIndex, woodTotal);
    xsArraySetFloat(trainerTotalsGold, trainerWriteIndex, goldTotal);
    xsArraySetFloat(trainerTotalsStone, trainerWriteIndex, stoneTotal);
    trainerCountWorkers(player);

    if (trainerSampleCount < trainerHistorySize) {
        trainerSampleCount = trainerSampleCount + 1;
    }
    trainerWriteIndex = (trainerWriteIndex + 1) % trainerHistorySize;
    int lastIndex = (trainerWriteIndex + trainerHistorySize - 1) % trainerHistorySize;
    int foodWorkers = xsArrayGetInt(trainerWorkersFood, lastIndex);
    int woodWorkers = xsArrayGetInt(trainerWorkersWood, lastIndex);
    int goldWorkers = xsArrayGetInt(trainerWorkersGold, lastIndex);
    int stoneWorkers = xsArrayGetInt(trainerWorkersStone, lastIndex);
    trainerTrackGoals(player, now, villagers, foodWorkers, woodWorkers, goldWorkers, stoneWorkers);

    trainerPrepareWindow(now);
    float rateFood = trainerRate(trainerTotalsFood, foodTotal);
    float rateWood = trainerRate(trainerTotalsWood, woodTotal);
    float rateGold = trainerRate(trainerTotalsGold, goldTotal);
    float rateStone = trainerRate(trainerTotalsStone, stoneTotal);

    string text = "TRAINER | " + (now / 60) + "m " + (now % 60) + "s | CIV: " +
                  xsGetPlayerCivName(player, true) + " (#" + trainerCivilization + ")";
    if (trainerSelectedBuild < 0) {
        text = text + "\nNO MATCHING BUILDS for this civilization";
    } else {
        text = text + "\nBUILD " + (trainerSelectedBuildSlot + 1) + "/" + trainerEligibleBuildCount +
               ": " + xsArrayGetString(trainerBuildNames, trainerSelectedBuild) +
               " | " + xsArrayGetString(trainerBuildMaps, trainerSelectedBuild);
        int slot = trainerActiveStepSlot(now);
        if (slot >= 0) {
            int step = xsArrayGetInt(trainerSelectedSteps, slot);
            text = text + "\nSTEP " + (slot + 1) + "/" + trainerSelectedStepCount +
                   " " + trainerStepStatus(step, now) + ": " + xsArrayGetString(trainerStepLabels, step);
            if (trainerHasGoal(step)) {
                text = text + "\n" + trainerGoalProgress(step, player, villagers,
                                       foodWorkers, woodWorkers, goldWorkers, stoneWorkers);
            }
            text = text + "\nMISSED CHECKPOINTS: " + trainerMissedCheckpoints(now);
        } else {
            text = text + "\nNO APPLICABLE STEPS";
        }
    }
    text = text + "\n" + trainerWindowCaption();
    text = text + "\n" + trainerRateLine("FOOD", rateFood, trainerAverageWorkers(trainerWorkersFood, now));
    text = text + "\n" + trainerRateLine("WOOD", rateWood, trainerAverageWorkers(trainerWorkersWood, now));
    text = text + "\n" + trainerRateLine("GOLD", rateGold, trainerAverageWorkers(trainerWorkersGold, now));
    text = text + "\n" + trainerRateLine("STONE", rateStone, trainerAverageWorkers(trainerWorkersStone, now));

    // The game controls panel placement. This is native game UI, not a live
    // data stream into the separate macOS preview window.
    xsDisplayInstructions(text, 3, player, -1, 0, false, false, "", player);
}
