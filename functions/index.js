const {onDocumentUpdated, onDocumentCreated} =
  require("firebase-functions/v2/firestore");
const {setGlobalOptions} = require("firebase-functions/v2");
const admin = require("firebase-admin");
// eslint-disable-next-line new-cap
const anthropic = require("@anthropic-ai/sdk");

admin.initializeApp();
setGlobalOptions({region: "us-central1", maxInstances: 10});

exports.generateNightReport = onDocumentUpdated({
  document: "users/{uid}/night_events/{eventId}",
  secrets: ["CLAUDE_API_KEY"],
}, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  console.log("generateNightReport triggered", {
    hasRequest: !!after.ai_report_requested,
    hadRequest: !!before.ai_report_requested,
    hasReport: !!after.ai_report,
  });

  if (!after.ai_report_requested ||
      before.ai_report_requested ||
      after.ai_report) {
    console.log("Skipping: conditions not met");
    return;
  }

  const d = after.ai_report_request_data;
  if (!d) {
    console.log("Skipping: no request data");
    return;
  }

  console.log("Generating report for event", event.params.eventId);

  const {
    eventName, durationMinutes, drinks,
    peakBac, peakBacTime, minutesAboveLimit,
    waterCount, hydrationLevel, totalCalories,
    recoveryMinutes, userSex, userWeightKg, userAge,
    avgDrinksLast30Days, dayOfWeek,
    stomachState, foodEntryCount,
    avgSipMinutes, paceSummary, drinksPerHourParam,
    fastestDrinkName, slowestDrinkName,
    targetBAC, exceededTarget, minutesOverTarget,
  } = d;

  const totalDrinksCount = drinks.reduce((s, dr) => s + dr.quantity, 0);
  const drinksPerHour = durationMinutes > 0 ?
    (totalDrinksCount / (durationMinutes / 60)).toFixed(1) : "0";

  const drinkList = drinks
      .map((dr) => `${dr.quantity}x ${dr.name}`)
      .join(", ");

  const nightName = eventName || `${dayOfWeek} night`;
  const avg = (avgDrinksLast30Days || 0).toFixed(1);
  const peak = (peakBac || 0).toFixed(3);
  const cals = Math.round(totalCalories || 0);
  const soberNight = totalDrinksCount === 0;
  const drinkSummary = soberNight ?
    "None — non-alcoholic night" :
    `${drinkList} (${drinksPerHour} drinks/hour)`;
  const stomach = stomachState || "empty";
  const foodLogged = parseInt(foodEntryCount || 0);
  const emptyStomach = stomach === "empty" && !soberNight;
  const foodSummary = `Stomach: ${stomach}${foodLogged > 0 ? ` · ${foodLogged} food log${foodLogged > 1 ? "s" : ""} during night` : ""}`;

  // Pace line (from new iOS params)
  const pace = paceSummary || null;
  const paceLine = avgSipMinutes != null ?
    `Pace: ${pace} · ${avgSipMinutes} min avg/drink` +
    (fastestDrinkName ? ` · fastest: ${fastestDrinkName}` : "") +
    (slowestDrinkName && slowestDrinkName !== fastestDrinkName ?
      ` · slowest: ${slowestDrinkName}` : "") : "";

  // Goal line
  const goalLine = targetBAC != null ?
    `Tonight's goal: ${(targetBAC * 100).toFixed(0)}% BAC · ` +
    (exceededTarget ?
      `exceeded (${minutesOverTarget || 0} min over)` :
      "stayed within goal") : "";

  const dominantDrinkType = d.dominantDrinkType || "mixed";
  const nightOutcome = d.nightOutcome || "heavy";

  const drinkContext = {
    beer: "Beer is filling and moderate — the morning is usually manageable.",
    wine: "Wine dehydrates faster than it feels — you'll notice it in your mouth and head when you wake up.",
    agave: "Tequila and mezcal tend to peak the next morning, around 6-8am. That's just how agave spirits work.",
    spirits: "Straight spirits absorb fast — the peak has passed but the morning will remind you it happened.",
    cocktails: "Cocktails are sneaky — the sugar masks how much you actually had.",
    mixed: "Mixing different types tonight means your body is clearing them at different rates — the morning can be unpredictable.",
  };

  const soberPrompt =
    "The user had a sober night. 1-2 sentences: name one real benefit of a sober night for the body " +
    "(sleep, recovery, hydration reset) and tell them it counts. Warm, not preachy.";

  const solidPrompt =
    "The user had a solid night — they paced well or stayed within goal. " +
    "1 sentence of genuine praise naming what worked (drink choice, pacing, hydration, or BAC control). " +
    "1 sentence reinforcing the habit so they repeat it. Warm, not sycophantic.";

  const heavyPrompt =
    `The user had a heavy night. Write 2-3 sentences: ` +
    `(1) Drink-specific right now — what to do before sleep given they drank ${dominantDrinkType} ` +
    `(water? food? timing? nothing generic). ` +
    `(2) One thing to skip or watch for tomorrow morning, specific to ${dominantDrinkType}. ` +
    `(3) One smarter option for next time — a named swap or pacing move, NOT "drink less".`;

  const instruction = nightOutcome === "sober" ? soberPrompt
    : nightOutcome === "solid" ? solidPrompt
    : heavyPrompt;

  const prompt = [
    "You are a knowledgeable friend, not a doctor or a counselor.",
    "Output: 1 paragraph, 2-3 sentences, plain text, second person.",
    "No bullets, no labels, no moralizing. Never tell the user to drink less or cut back.\n",
    `Drink context: ${drinkContext[dominantDrinkType] || drinkContext.mixed}`,
    `Drinks tonight: ${drinkSummary} · Peak BAC: ${peak} · Water: ${waterCount} glasses\n`,
    instruction,
  ].filter(Boolean).join("\n");

  const client = new anthropic.Anthropic({
    apiKey: process.env.CLAUDE_API_KEY,
  });

  const message = await client.messages.create({
    model: "claude-haiku-4-5-20251001",
    max_tokens: 250,
    messages: [{role: "user", content: prompt}],
  });

  const report = message.content[0].text;

  await event.data.after.ref.update({
    ai_report: report,
    ai_report_requested: admin.firestore.FieldValue.delete(),
    ai_report_request_data: admin.firestore.FieldValue.delete(),
  });
});

// ─── AI Coach Report ────────────────────────────────────────────────────────

const coachPersona = [
  "You are a harm-reduction health coach. Your role is to help the user",
  "understand their drinking patterns — not to judge or recommend abstinence.",
  "Focus on patterns, physiology, and strategies for smarter choices.",
  "Be direct, honest, and supportive. 2-3 sentences per paragraph max.",
].join(" ");

// eslint-disable-next-line require-jsdoc
function buildWeeklyPrompt(d) {
  const {
    userSex, userWeightKg, userAge,
    weekStart, weekEnd,
    nightCount, worstNight,
    bestBehaviorType, bestBehaviorNight, bestBehaviorDetail,
    drivingNights, drivingExceededBACLimit,
  } = d;

  const drivingWarning = drivingExceededBACLimit > 0
    ? `SAFETY: On ${drivingExceededBACLimit} night(s) the user said they would drive but BAC exceeded ` +
      `the legal limit. Address this directly in THE WEEK — name it, don't lecture.`
    : "";

  const bestBehaviorLine = (() => {
    if (bestBehaviorType === "hydration") {
      return `Best behavior this week: ${bestBehaviorNight} — they stayed on top of water ` +
        `(${bestBehaviorDetail}). Call this out specifically and tell them to keep doing it.`;
    }
    if (bestBehaviorType === "pace") {
      return `Best behavior this week: ${bestBehaviorNight} was their cleanest night ` +
        `(${bestBehaviorDetail}). Name it and explain why it's worth repeating.`;
    }
    return `No single standout positive behavior this week — they showed up for ${nightCount} nights ` +
      "and that's data worth working with. Find something small they did right " +
      "and call it out honestly. Even 'you ended at a reasonable time' counts.";
  })();

  return [
    "You are a knowledgeable friend looking back at the user's week.",
    "Write exactly 2 paragraphs separated by a blank line.",
    "Each paragraph MUST start with its label in ALL CAPS + colon.",
    "Do NOT recap stats — the user already sees the numbers. Tell the story.",
    "Never advise to drink less. No forward-looking advice for next week.\n",
    `User: ${userSex}, ${userWeightKg}kg, age ${userAge || "unknown"}.`,
    `Week: ${weekStart} to ${weekEnd} · ${nightCount} nights out.`,
    worstNight ? `Heaviest night: ${worstNight}.` : "",
    drivingNights > 0
      ? `Driving nights: ${drivingNights} (${drivingExceededBACLimit} above legal limit).`
      : "",
    drivingWarning, // placed before THE WEEK so the model sees it before writing that section
    "\nTHE WEEK: What actually happened — name the standout night and say what made it different " +
    "from the rest. 2-3 sentences. Honest, not preachy.",
    "\nWHAT YOU NAILED: " + bestBehaviorLine + " 1-2 sentences. Make them want to repeat it.",
  ].filter(Boolean).join("\n");
}

// eslint-disable-next-line require-jsdoc
function buildMonthlyPrompt(d) {
  const {
    userSex, userWeightKg, userAge, userHeightCm, userBMI,
    monthName, year,
    nightCount, totalDrinks, totalStdDrinks, totalCalories,
    peakBac, peakBacNight, avgBacPerNight,
    totalWater, soberDays,
    prevMonthNightCount,
    weekBreakdowns, drinkBreakdown,
    drivingNights, drivingExceededBACLimit,
    signatureMove, bestMonthNight,
  } = d;

  const weeklyLimit = userSex === "male" ? 14 : 7;
  const monthlyLimit = weeklyLimit * 4;
  const trend = prevMonthNightCount != null
    ? (nightCount > prevMonthNightCount ? "up"
      : nightCount < prevMonthNightCount ? "down" : "flat")
    : "unknown";
  const physique = userHeightCm
    ? `${userWeightKg}kg, ${userHeightCm}cm (BMI ${userBMI})`
    : `${userWeightKg}kg`;

  const weeks = (weekBreakdowns || [])
    .map((w, i) => `  Week ${i + 1}: ${w.nights} nights, ${w.drinks} drinks, peak BAC ${(w.peakBac || 0).toFixed(3)}`)
    .join("\n");

  const drivingLine = drivingNights > 0
    ? `Driving nights: ${drivingNights} (${drivingExceededBACLimit} above legal BAC limit)`
    : "";

  const drivingWarning = drivingExceededBACLimit > 0
    ? `SAFETY: On ${drivingExceededBACLimit} night(s) this month the user said they would drive ` +
      `but BAC exceeded the legal limit. Address this in BEHAVIORAL INSIGHT.`
    : "";

  const signatureMoveLine = (() => {
    switch (signatureMove) {
      case "front_loads":
        return "Pattern detected: the user consistently front-loads — most drinks come in the first " +
          "half of their nights. Name this pattern directly and explain how it affects their BAC curve.";
      case "late_drinker":
        return "Pattern detected: the user's nights consistently run late — last drinks after midnight. " +
          "Name this as their signature and say what it does to sleep and recovery quality.";
      case "mixes_drinks":
        return "Pattern detected: the user regularly mixes beer/wine and spirits in the same night. " +
          "Name this as their move and explain why mixing complicates how the body clears alcohol.";
      default:
        return "No single dominant pattern detected — if the numbers were reasonable, say so: " +
          "consistency itself is a form of control worth naming.";
    }
  })();

  const bestNightLine = bestMonthNight
    ? `Best night of the month: ${bestMonthNight} had the lowest peak BAC. Close this section by ` +
      `calling it out — name it as the standard worth repeating next month.`
    : "";

  return [
    coachPersona,
    "Write exactly 4 paragraphs separated by a blank line.",
    "No markdown, no bullets. Second person. Plain text only.",
    "Each paragraph starts with its label in ALL CAPS + colon.",
    "The 4th starts with OVERALL SYNTHESIS:\n",
    `User: ${userSex}, ${physique}, age ${userAge || "unknown"}.`,
    `Monthly guideline: ${monthlyLimit} standard drinks.\n`,
    `Month: ${monthName} ${year}`,
    `Nights out: ${nightCount} | Sober days: ${soberDays} | Trend vs last month: ${trend}`,
    `Total: ${totalDrinks} drinks (${(totalStdDrinks || totalDrinks).toFixed(1)} std)`,
    `Total calories: ${Math.round(totalCalories || 0)} kcal`,
    `Peak BAC: ${(peakBac || 0).toFixed(3)} on ${peakBacNight || "unknown"}`,
    `Avg BAC/night: ${(avgBacPerNight || 0).toFixed(3)}`,
    `Water: ${totalWater || 0} glasses total`,
    drinkBreakdown ? `Drink breakdown: ${drinkBreakdown}` : "",
    drivingLine,
    weeks ? `\nWeek-by-week:\n${weeks}` : "",
    "\nMEDICAL ANALYSIS: Full-month medical picture. Cumulative BAC exposure, organ load, " +
    "any red flags. Reference physique. Clinical and direct — this section earns its formality.\n",
    "NUTRITION & METABOLISM: Nutritional impact of the specific drinks consumed. " +
    "Caloric total, hydration pattern, one actionable goal for next month.\n",
    "BEHAVIORAL INSIGHT: " + signatureMoveLine + (bestNightLine ? " " + bestNightLine : "") + "\n",
    "OVERALL SYNTHESIS: Two sentences tying all three together. Honest and motivating. " +
    "Do not moralize or recommend drinking less.",
    drivingWarning,
  ].filter(Boolean).join("\n");
}

// eslint-disable-next-line require-jsdoc
function buildComparisonPrompt(d) {
  const {
    userSex, userWeightKg, userAge, userHeightCm, userBMI,
    eventA, eventB,
  } = d;

  const physique = userHeightCm ?
    `${userWeightKg}kg, ${userHeightCm}cm (BMI ${userBMI})` :
    `${userWeightKg}kg`;

  const nameA = eventA.name || "Night A";
  const nameB = eventB.name || "Night B";

  // eslint-disable-next-line require-jsdoc
  const fmt = (e) => {
    const drivingStr = e.drivingMode ?
      `Driving: YES (BAC ${e.drivedAboveLimit ? "exceeded" : "within"} limit)` :
      "";
    return [
      `Duration: ${e.durationMinutes} min`,
      `Drinks: ${e.drinkList} (${e.drinksPerHour}/hr)`,
      `Peak BAC: ${(e.peakBac || 0).toFixed(3)} at ${e.peakBacTime || "?"}`,
      `Mins above 0.08: ${e.minutesAboveLimit}`,
      `Water: ${e.waterCount} glasses (${e.hydrationLevel})`,
      `Calories: ${Math.round(e.totalCalories || 0)} kcal`,
      `Recovery: ${e.recoveryMinutes} min`,
      drivingStr,
    ].filter(Boolean).join(" | ");
  };

  const drivingWarning =
    (eventA.drivedAboveLimit || eventB.drivedAboveLimit) ?
      "SAFETY: One or both nights involved driving above legal BAC." +
      " Address this in BEHAVIORAL INSIGHT." : "";

  return [
    coachPersona,
    "Write exactly 3 paragraphs separated by a blank line.",
    "No markdown, no bullets. Second person. Plain text only.",
    "Each paragraph starts with its label in ALL CAPS + colon.",
    `Refer to the nights by their names: "${nameA}" and "${nameB}".\n`,
    `User: ${userSex}, ${physique}, age ${userAge || "unknown"}.\n`,
    `"${nameA}" — ${fmt(eventA)}`,
    `"${nameB}" — ${fmt(eventB)}\n`,
    "MEDICAL ANALYSIS: Which night was harder on the body and why?",
    "Compare BAC curves, drinking pace (drinks/hr is in the data),",
    "and recovery time. Reference physique. Concise.\n",
    "NUTRITION & METABOLISM: Compare hydration and caloric profiles.",
    "Which night was better handled metabolically?\n",
    "BEHAVIORAL INSIGHT: What does the contrast between these two nights",
    "reveal about pace and timing? Point to the specific difference in",
    "drinks/hour or duration. Then give ONE concrete technique the user",
    "can apply next time — not 'drink slower' in the abstract, but a",
    "named action: 'match the pace of your slower night', 'set a 20-min",
    "timer between drinks', 'eat before your second drink'. If one night",
    "showed genuinely good pacing, call it out as the standard to repeat.",
    drivingWarning,
  ].join("\n");
}

exports.generateRecoveryBrief = onDocumentCreated({
  document: "users/{uid}/night_recoveries/{eventId}",
  secrets: ["CLAUDE_API_KEY"],
}, async (event) => {
  const data = event.data.data();
  if (data.status !== "pending") return;

  const d = data.request_data;
  if (!d) return;

  const {
    userSex, userWeightKg, userAge,
    drinkList, peakBac, waterCount,
    hydrationLevel, severity,
  } = d;

  const hydrationGood =
    hydrationLevel === "great" || hydrationLevel === "moderate";
  const waterLabel = waterCount === 1 ? "glass" : "glasses";
  const waterSummary = hydrationGood ?
    `${waterCount} ${waterLabel} — solid hydration.` :
    `Only ${waterCount} ${waterLabel} — under-hydrated.`;

  const hydrationInstruction = hydrationGood ?
    "Acknowledge their hydration was solid and reinforce the habit. " +
    "Do NOT mention water reminders — they're doing well. 1-2 sentences." :
    "Give one concrete tip to improve next time. Mention that " +
    "Tracksip's water reminders help them stay on track. 1-2 sentences.";

  const prompt = [
    "You are a morning-after recovery coach.",
    "Tailor advice to what they actually drank — beer, wine, and spirits need different fixes.",
    "Output: 1 paragraph, 2-3 sentences, plain text, second person. No bullets, no labels, no moralizing.\n",
    "=== DATA ===",
    `${userSex} · ${userWeightKg}kg · age ${userAge || "unknown"}`,
    `Drinks: ${drinkList || "none logged"} · Peak BAC: ${(peakBac || 0).toFixed(3)}`,
    `Water: ${waterSummary} · Severity: ${severity}\n`,
    "Write one paragraph: name the 1-2 most effective recovery items for what they specifically",
    "drank (be drink-specific, not generic), mention one thing to avoid today, address hydration:",
    hydrationInstruction,
    "End with ONE concrete pacing tip for their next night out — a specific action",
    "(e.g., 'try spacing each drink at least 20 minutes apart next time') rather than",
    "a vague 'drink less'. Keep this to one short sentence.",
  ].join("\n");

  const client = new anthropic.Anthropic({
    apiKey: process.env.CLAUDE_API_KEY,
  });

  const message = await client.messages.create({
    model: "claude-haiku-4-5-20251001",
    max_tokens: 120,
    messages: [{role: "user", content: prompt}],
  });

  const report = message.content[0].text;
  const {eventId} = event.params;

  await event.data.ref.update({
    report,
    status: admin.firestore.FieldValue.delete(),
    request_data: admin.firestore.FieldValue.delete(),
  });

  console.log("Recovery brief written", {eventId});
});

exports.generateCoachReport = onDocumentCreated({
  document: "users/{uid}/ai_coach_reports/{reportId}",
  secrets: ["CLAUDE_API_KEY"],
}, async (event) => {
  const data = event.data.data();

  console.log("generateCoachReport triggered", {
    type: data.type,
    status: data.status,
  });

  if (data.status !== "pending") {
    console.log("Skipping: not pending");
    return;
  }

  const d = data.request_data;
  if (!d) {
    console.log("Skipping: no request_data");
    return;
  }

  const type = data.type;
  const {reportId} = event.params;
  console.log("Generating coach report", {type, reportId});

  let prompt;
  let maxTokens;
  if (type === "weekly") {
    prompt = buildWeeklyPrompt(d);
    maxTokens = 400;
  } else if (type === "monthly") {
    prompt = buildMonthlyPrompt(d);
    maxTokens = 550;
  } else if (type === "comparison") {
    prompt = buildComparisonPrompt(d);
    maxTokens = 400;
  } else {
    console.log("Unknown report type:", type);
    return;
  }

  const client = new anthropic.Anthropic({
    apiKey: process.env.CLAUDE_API_KEY,
  });

  const message = await client.messages.create({
    model: "claude-haiku-4-5-20251001",
    max_tokens: maxTokens,
    messages: [{role: "user", content: prompt}],
  });

  const report = message.content[0].text;

  await event.data.ref.update({
    report,
    status: admin.firestore.FieldValue.delete(),
    request_data: admin.firestore.FieldValue.delete(),
  });

  console.log("Coach report written", {type, reportId});
});
