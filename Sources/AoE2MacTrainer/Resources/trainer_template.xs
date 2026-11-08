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
int trainerStepFood = -1;
int trainerStepWood = -1;
int trainerStepGold = -1;
int trainerStepStone = -1;
int trainerStepDoneTimes = -1;
int trainerStepLabels = -1;
int trainerBuildNames = -1;
int trainerUnitGoalCount = 0;
int trainerUnitGoalSteps = -1;
int trainerUnitGoalObjects = -1;
int trainerUnitGoalCounts = -1;
int trainerUnitGoalLabels = -1;

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

// Goals are lower bounds, not exact counts. A step with no numeric goals is
// manual-only: timing cannot prove that the requested action occurred.
bool trainerHasGoal(int step) {
    if (xsArrayGetInt(trainerStepVillagers, step) >= 0 ||
        xsArrayGetInt(trainerStepFood, step) > 0 ||
        xsArrayGetInt(trainerStepWood, step) > 0 ||
        xsArrayGetInt(trainerStepGold, step) > 0 ||
        xsArrayGetInt(trainerStepStone, step) > 0) {
        return true;
    }
    for (int i = 0; i < trainerUnitGoalCount; i = i + 1) {
        if (xsArrayGetInt(trainerUnitGoalSteps, i) == step) {
            return true;
        }
    }
    return false;
}

bool trainerGoalIsMet(int step, int player, int villagers,
                      int foodWorkers, int woodWorkers, int goldWorkers, int stoneWorkers) {
    int target = xsArrayGetInt(trainerStepVillagers, step);
    if (target >= 0 && villagers < target) {
        return false;
    }
    target = xsArrayGetInt(trainerStepFood, step);
    if (target > 0 && foodWorkers < target) {
        return false;
    }
    target = xsArrayGetInt(trainerStepWood, step);
    if (target > 0 && woodWorkers < target) {
        return false;
    }
    target = xsArrayGetInt(trainerStepGold, step);
    if (target > 0 && goldWorkers < target) {
        return false;
    }
    target = xsArrayGetInt(trainerStepStone, step);
    if (target > 0 && stoneWorkers < target) {
        return false;
    }
    for (int i = 0; i < trainerUnitGoalCount; i = i + 1) {
        if (xsArrayGetInt(trainerUnitGoalSteps, i) == step &&
            xsGetObjectCount(player, xsArrayGetInt(trainerUnitGoalObjects, i)) <
            xsArrayGetInt(trainerUnitGoalCounts, i)) {
            return false;
        }
    }
    return true;
}

// Remember the *first* time the full numeric target was observed, so a late
// completion stays late, even after the player surpasses the goal.
void trainerTrackGoals(int player, int now, int villagers,
                       int foodWorkers, int woodWorkers, int goldWorkers, int stoneWorkers) {
    infiniteLoopLimit 1000;
    for (int i = 0; i < trainerStepCount; i = i + 1) {
        if (xsArrayGetInt(trainerStepDoneTimes, i) < 0 && trainerHasGoal(i) &&
            trainerGoalIsMet(i, player, villagers, foodWorkers, woodWorkers, goldWorkers, stoneWorkers)) {
            xsArraySetInt(trainerStepDoneTimes, i, now);
        }
    }
}

int trainerActiveStep(int now) {
    int selected = 0;
    for (int i = 0; i < trainerStepCount; i = i + 1) {
        int deadline = xsArrayGetInt(trainerStepTimes, i);
        if (deadline >= 0 && deadline <= now) {
            selected = i;
        }
    }
    return selected;
}

string trainerStepStatus(int step, int now) {
    if (!trainerHasGoal(step)) {
        return "MANUAL ACTION";
    }
    int deadline = xsArrayGetInt(trainerStepTimes, step);
    int achieved = xsArrayGetInt(trainerStepDoneTimes, step);
    if (achieved >= 0) {
        if (deadline < 0) {
            return "GOAL MET";
        }
        int offset = achieved - deadline;
        if (offset <= 0) {
            return "MET EARLY " + (0 - offset) + "s";
        }
        return "MET LATE +" + offset + "s";
    }
    if (deadline >= 0 && now > deadline) {
        return "LATE +" + (now - deadline) + "s";
    }
    if (deadline >= 0) {
        return "DUE IN " + (deadline - now) + "s";
    }
    return "WAITING";
}

string trainerGoalProgress(int step, int player, int villagers,
                           int foodWorkers, int woodWorkers, int goldWorkers, int stoneWorkers) {
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
    for (int i = 0; i < trainerUnitGoalCount; i = i + 1) {
        if (xsArrayGetInt(trainerUnitGoalSteps, i) == step) {
            int id = xsArrayGetInt(trainerUnitGoalObjects, i);
            int minimum = xsArrayGetInt(trainerUnitGoalCounts, i);
            line = line + " " + xsArrayGetString(trainerUnitGoalLabels, i) + " " +
                   xsGetObjectCount(player, id) + "/" + minimum;
        }
    }
    return line;
}

int trainerMissedCheckpoints(int now) {
    int missed = 0;
    for (int i = 0; i < trainerStepCount; i = i + 1) {
        int deadline = xsArrayGetInt(trainerStepTimes, i);
        int achieved = xsArrayGetInt(trainerStepDoneTimes, i);
        if (deadline >= 0 && deadline < now && trainerHasGoal(i) &&
            (achieved < 0 || achieved > deadline)) {
            missed = missed + 1;
        }
    }
    return missed;
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
    int lastIndex = (trainerWriteIndex + trainerHistorySize - 1) % trainerHistorySize;
    int foodWorkers = xsArrayGetInt(trainerWorkersFood, lastIndex);
    int woodWorkers = xsArrayGetInt(trainerWorkersWood, lastIndex);
    int goldWorkers = xsArrayGetInt(trainerWorkersGold, lastIndex);
    int stoneWorkers = xsArrayGetInt(trainerWorkersStone, lastIndex);
    trainerTrackGoals(player, now, villagers, foodWorkers, woodWorkers, goldWorkers, stoneWorkers);

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
    int step = trainerActiveStep(now);
    text = text + "\nSTEP " + (step + 1) + "/" + trainerStepCount +
           " " + trainerStepStatus(step, now) + ": " + xsArrayGetString(trainerStepLabels, step);
    text = text + "\n" + trainerGoalProgress(step, player, villagers,
                           foodWorkers, woodWorkers, goldWorkers, stoneWorkers);
    text = text + "\nMISSED CHECKPOINTS: " + trainerMissedCheckpoints(now);
    text = text + "\n" + trainerRateLine("FOOD", rateFood, trainerAverageWorkers(trainerWorkersFood, windowStart));
    text = text + "\n" + trainerRateLine("WOOD", rateWood, trainerAverageWorkers(trainerWorkersWood, windowStart));
    text = text + "\n" + trainerRateLine("GOLD", rateGold, trainerAverageWorkers(trainerWorkersGold, windowStart));
    text = text + "\n" + trainerRateLine("STONE", rateStone, trainerAverageWorkers(trainerWorkersStone, windowStart));

    // Top instruction panel: native AoE2 UI, no desktop overlay or OCR.
    // The game controls panel placement, approximately 13% below screen top.
    xsDisplayInstructions(text, 3, player, -1, 0, false, false, "", player);
}
