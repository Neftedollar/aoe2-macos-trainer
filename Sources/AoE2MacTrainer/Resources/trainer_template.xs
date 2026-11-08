// AoE2 Mac Trainer - GENERATED FILE TEMPLATE
// The app replaces the setup marker with a selected JSON build order.
// Runs only in matches where a custom RMS/scenario explicitly loads this XS.
// No process injection, file telemetry, or enemy-player inspection.

const int trainerWindowSeconds = 60;
const int trainerHistorySize = 64;

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

int trainerStepCount = 0;
int trainerStepTimes = -1;
int trainerStepVillagers = -1;
int trainerStepLabels = -1;
int trainerBuildNames = -1;

void trainerLoadPlan() {
    // @PLAN_SETUP@
}

void main() {
    trainerSampleTimes = xsArrayCreateInt(trainerHistorySize, -1, "trainer_sample_times");
    trainerTotalsFood = xsArrayCreateInt(trainerHistorySize, 0, "trainer_food_totals");
    trainerTotalsWood = xsArrayCreateInt(trainerHistorySize, 0, "trainer_wood_totals");
    trainerTotalsGold = xsArrayCreateInt(trainerHistorySize, 0, "trainer_gold_totals");
    trainerTotalsStone = xsArrayCreateInt(trainerHistorySize, 0, "trainer_stone_totals");
    trainerWorkersFood = xsArrayCreateInt(trainerHistorySize, 0, "trainer_workers_food");
    trainerWorkersWood = xsArrayCreateInt(trainerHistorySize, 0, "trainer_workers_wood");
    trainerWorkersGold = xsArrayCreateInt(trainerHistorySize, 0, "trainer_workers_gold");
    trainerWorkersStone = xsArrayCreateInt(trainerHistorySize, 0, "trainer_workers_stone");
    trainerVillagerIDs = xsArrayCreateInt(0, 0, "trainer_villager_ids");
    trainerBuildNames = xsArrayCreateString(1, "", "trainer_build_name");
    trainerLoadPlan();
}

// Observes villagers' current task target. The target is sometimes a drop-off
// building or absent; counts are APPROXIMATE, not guaranteed exact.
void trainerCountWorkers(int player) {
    infiniteLoopLimit 1000;
    int ids = xsGetPlayerUnitIds(cVillagerClass, player, trainerVillagerIDs);
    int workers = xsArrayGetSize(ids);
    int food = 0;
    int wood = 0;
    int gold = 0;
    int stone = 0;
    for (int i = 0; i < workers; i = i + 1) {
        int villager = xsArrayGetInt(ids, i);
        int target = xsGetUnitTargetUnitId(villager);
        int unitClass = -1;
        if (target >= 0 && xsDoesUnitExist(target)) {
            unitClass = xsGetUnitClass(target);
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
        } else if (xsGetUnitAttributeHeld(villager, cAttributeFood) > 0) {
            food = food + 1;
        }
    }

    xsArraySetInt(trainerWorkersFood, trainerWriteIndex, food);
    xsArraySetInt(trainerWorkersWood, trainerWriteIndex, wood);
    xsArraySetInt(trainerWorkersGold, trainerWriteIndex, gold);
    xsArraySetInt(trainerWorkersStone, trainerWriteIndex, stone);
}

int trainerRate(int totalsArray, int baselineIndex, int elapsed, int nowTotal) {
    if (baselineIndex < 0 || elapsed <= 0) {
        return -1;
    }
    int previous = xsArrayGetInt(totalsArray, baselineIndex);
    int gained = nowTotal - previous;
    if (gained < 0) {
        return -1;
    }
    return gained * 60 / elapsed;
}

int trainerAverageWorkers(int arrayID, int earliestTime) {
    int sum = 0;
    int sampleCount = 0;
    for (int i = 0; i < trainerSampleCount; i = i + 1) {
        int sampledAt = xsArrayGetInt(trainerSampleTimes, i);
        if (sampledAt >= earliestTime) {
            sum = sum + xsArrayGetInt(arrayID, i);
            sampleCount = sampleCount + 1;
        }
    }
    if (sampleCount == 0) {
        return 0;
    }
    return sum / sampleCount;
}

string trainerRateLine(string label, int rate, int workers) {
    if (rate < 0) {
        return label + " --/min";
    }
    string line = label + " " + rate + "/min | ~" + workers + " vils";
    if (workers > 0) {
        line = line + " | " + (rate / workers) + "/vil";
    }
    return line;
}

// The active build step follows its reference TIME. Numeric goals are assessed,
// but building placement/actual command completion cannot be inferred here.
string trainerPlanLine(int now, int villagers) {
    if (trainerStepCount <= 0) {
        return "No build selected";
    }
    int step = 0;
    for (int i = 0; i < trainerStepCount; i = i + 1) {
        int at = xsArrayGetInt(trainerStepTimes, i);
        if (at <= now && at >= 0) {
            step = i;
        }
    }
    int goal = xsArrayGetInt(trainerStepVillagers, step);
    string label = xsArrayGetString(trainerStepLabels, step);
    string state = "";
    if (goal >= 0) {
        if (villagers >= goal) {
            state = " [VILS OK]";
        } else {
            state = " [VILS " + villagers + "/" + goal + "]";
        }
    }
    return "STEP " + (step + 1) + "/" + trainerStepCount + ": " + label + state;
}

rule trainerMetrics
    active
    minInterval 2
{
    infiniteLoopLimit 1000;
    if (trainerSampleTimes < 0) {
        return;
    }
    // Only local player's state is read, and only for local UI output.
    // The unsynced player ID must NEVER be used for synchronized game effects.
    int player = xsUnsyncGetLocalPlayerId();
    if (player < 1) {
        return;
    }
    int now = xsGetGameTime();
    int foodTotal = xsPlayerAttribute(player, 166);
    int woodTotal = xsPlayerAttribute(player, 167);
    int stoneTotal = xsPlayerAttribute(player, 168);
    int goldTotal = xsPlayerAttribute(player, 169);
    int villagers = xsPlayerAttribute(player, 38);

    // Existing player attributes count total gathered, not resource STOCKPILES.
    xsArraySetInt(trainerSampleTimes, trainerWriteIndex, now);
    xsArraySetInt(trainerTotalsFood, trainerWriteIndex, foodTotal);
    xsArraySetInt(trainerTotalsWood, trainerWriteIndex, woodTotal);
    xsArraySetInt(trainerTotalsGold, trainerWriteIndex, goldTotal);
    xsArraySetInt(trainerTotalsStone, trainerWriteIndex, stoneTotal);
    trainerCountWorkers(player);

    if (trainerSampleCount < trainerHistorySize) {
        trainerSampleCount = trainerSampleCount + 1;
    }
    trainerWriteIndex = (trainerWriteIndex + 1) % trainerHistorySize;

    int baselineIndex = -1;
    int baselineTime = -1;
    int cutoff = now - trainerWindowSeconds;
    for (int i = 0; i < trainerSampleCount; i = i + 1) {
        int sampledAt = xsArrayGetInt(trainerSampleTimes, i);
        if (sampledAt >= 0 && sampledAt <= cutoff && sampledAt > baselineTime) {
            baselineTime = sampledAt;
            baselineIndex = i;
        }
    }

    int elapsed = now - baselineTime;
    int rateFood = trainerRate(trainerTotalsFood, baselineIndex, elapsed, foodTotal);
    int rateWood = trainerRate(trainerTotalsWood, baselineIndex, elapsed, woodTotal);
    int rateGold = trainerRate(trainerTotalsGold, baselineIndex, elapsed, goldTotal);
    int rateStone = trainerRate(trainerTotalsStone, baselineIndex, elapsed, stoneTotal);
    int windowStart = now - trainerWindowSeconds;

    string text = "TRAINER | " + (now / 60) + "m " + (now % 60) + "s | " + xsArrayGetString(trainerBuildNames, 0);
    text = text + "\n" + trainerPlanLine(now, villagers);
    text = text + "\n" + trainerRateLine("FOOD", rateFood, trainerAverageWorkers(trainerWorkersFood, windowStart));
    text = text + "\n" + trainerRateLine("WOOD", rateWood, trainerAverageWorkers(trainerWorkersWood, windowStart));
    text = text + "\n" + trainerRateLine("GOLD", rateGold, trainerAverageWorkers(trainerWorkersGold, windowStart));
    text = text + "\n" + trainerRateLine("STONE", rateStone, trainerAverageWorkers(trainerWorkersStone, windowStart));

    // Top instruction panel: native AoE2 UI, no desktop overlay or OCR.
    // The game controls panel placement, approximately 13% below screen top.
    xsDisplayInstructions(text, 3, player, -1, 0, false, false, "", player);
}
