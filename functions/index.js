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

  const emptyStomachInstruction = emptyStomach ?
    "IMPORTANT: The user drank on an empty stomach. In Para 2, make this your primary tip — drinking without eating first dramatically accelerates absorption and spikes BAC faster. Be direct and specific, not preachy." :
    "";

  // Para 2 instruction — pace-aware
  const para2Instruction = (() => {
    if (pace === "fast" && avgSipMinutes != null) {
      return `Para 2 — Pace was fast (avg ${avgSipMinutes} min/drink). Give ONE concrete pacing technique the user can use next time — name a specific action like "put the drink down between sips", "set a 20-minute timer per beer", or "finish each drink only after checking in with yourself". Do not say 'drink slower' in the abstract. 1 sentence.`;
    }
    if (pace === "slow") {
      return `Para 2 — The user paced themselves well (avg ${avgSipMinutes}+ min/drink), which genuinely reduces peak BAC. Briefly acknowledge this as a smart habit${exceededTarget ? ", then note one other area to improve" : ""}. 1 sentence.`;
    }
    return "Para 2 — One specific, actionable tip for next time. Not 'drink less' — a concrete behavior: timing, food, water, or pacing. 1 sentence.";
  })();

  const prompt = [
    "You are a harm-reduction coach — direct like a doctor, warm like a friend.",
    "The user already sees their stats. Do not restate them.",
    "Output: 2 paragraphs, plain text, second person, blank line between.",
    "No headers, no bullets, no filler, no moralizing.\n",
    "=== PROFILE ===",
    `${userSex} · ${userWeightKg}kg · age ${userAge || "unknown"}`,
    `30-day avg: ${avg} drinks/night\n`,
    "=== TONIGHT ===",
    `${nightName} · ${durationMinutes} min · ${drinkSummary}`,
    `Peak BAC ${peak} at ${peakBacTime || "N/A"} · ${minutesAboveLimit} min above 0.08`,
    `Water: ${waterCount} glasses (${hydrationLevel}) · ${cals} kcal`,
    `Recovery: ${recoveryMinutes} min after last drink`,
    foodSummary,
    paceLine,
    goalLine,
    "\n",
    emptyStomachInstruction,
    soberNight ?
      "Para 1 — What one sober night actually does for the body: sleep depth, liver clearance, hydration reset. 2 sentences.\n" +
      "Para 2 — One thing to build on or protect going forward. 1 sentence." :
      "Para 1 — Physiology: what this BAC curve did to their body given their weight/sex. Mention pace if it amplified the BAC spike. 2 sentences.\n" +
      para2Instruction,
  ].filter(Boolean).join("\n");

  const client = new anthropic.Anthropic({
    apiKey: process.env.CLAUDE_API_KEY,
  });

  const message = await client.messages.create({
    model: "claude-haiku-4-5-20251001",
    max_tokens: 180,
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
    userSex, userWeightKg, userAge, userHeightCm, userBMI,
    weekStart, weekEnd,
    nightCount, totalDrinks, totalStdDrinks, totalCalories,
    peakBac, peakBacNight, avgBacPerNight,
    totalWater, avg30DayDrinksPerNight,
    bestNight, worstNight, drinkBreakdown,
    drivingNights, drivingExceededBACLimit,
  } = d;

  const weeklyLimit = userSex === "male" ? 14 : 7;
  const avg30 = (avg30DayDrinksPerNight || 0).toFixed(1);
  const physique = userHeightCm ?
    `${userWeightKg}kg, ${userHeightCm}cm (BMI ${userBMI})` :
    `${userWeightKg}kg`;

  const drivingLine = drivingNights > 0 ?
    `Driving nights: ${drivingNights}` +
    ` (${drivingExceededBACLimit} above legal BAC limit)` : "";

  const drivingWarning = drivingExceededBACLimit > 0 ?
    `SAFETY: On ${drivingExceededBACLimit} night(s) the user said they` +
    " would drive but BAC exceeded the legal limit." +
    " Address this directly in BEHAVIORAL INSIGHT." : "";

  return [
    coachPersona,
    "Write exactly 3 paragraphs separated by a blank line.",
    "No markdown, no bullets. Second person. Plain text only.",
    "Each paragraph MUST start with its label in ALL CAPS + colon.\n",
    `User: ${userSex}, ${physique}, age ${userAge || "unknown"}.`,
    `Weekly guideline: ${weeklyLimit} standard drinks.\n`,
    `Week: ${weekStart} to ${weekEnd}`,
    `Nights out: ${nightCount} | Total drinks: ${totalDrinks}`,
    `Std drinks: ${(totalStdDrinks || totalDrinks).toFixed(1)}`,
    `Total calories: ${Math.round(totalCalories || 0)} kcal`,
    `Peak BAC: ${(peakBac || 0).toFixed(3)} on ${peakBacNight || "unknown"}`,
    `Avg BAC/night: ${(avgBacPerNight || 0).toFixed(3)}`,
    `Water glasses total: ${totalWater || 0}`,
    `30-day avg drinks/night: ${avg30}`,
    `Best night (fewest drinks): ${bestNight || "n/a"}`,
    `Hardest night (most drinks): ${worstNight || "n/a"}`,
    drinkBreakdown ? `Drink breakdown: ${drinkBreakdown}` : "",
    drivingLine,
    "\nMEDICAL ANALYSIS: Medical picture of the week — BAC peaks,",
    "back-to-back nights, organ load. Reference physique. Concise.\n",
    "NUTRITION & METABOLISM: Nutritional and metabolic impact of",
    "the specific drinks consumed. One concrete tip for next week.\n",
    "BEHAVIORAL INSIGHT: Identify the dominant pace pattern this week — were",
    "drinks spread across the night or front-loaded? If pace was fast (high",
    "drinks/hour), name ONE specific technique for next time: e.g.,",
    "'finish each drink in 20+ minutes', 'set your drink down between sips',",
    "'drink a full glass of water before your second drink'. If pacing was",
    "good, say so explicitly — it's worth reinforcing. End with one",
    "measurable commitment: a target drinks/hour, a cutoff time, or a",
    "water-per-drink rule.",
    drivingWarning,
  ].join("\n");
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
  } = d;

  const weeklyLimit = userSex === "male" ? 14 : 7;
  const monthlyLimit = weeklyLimit * 4;
  const trend = prevMonthNightCount != null ?
    (nightCount > prevMonthNightCount ? "up" :
      nightCount < prevMonthNightCount ? "down" : "flat") : "unknown";
  const physique = userHeightCm ?
    `${userWeightKg}kg, ${userHeightCm}cm (BMI ${userBMI})` :
    `${userWeightKg}kg`;

  const weeks = (weekBreakdowns || [])
      .map((w, i) => `  Week ${i + 1}: ${w.nights} nights,` +
          ` ${w.drinks} drinks,` +
          ` peak BAC ${(w.peakBac || 0).toFixed(3)}`)
      .join("\n");

  const drivingLine = drivingNights > 0 ?
    `Driving nights: ${drivingNights}` +
    ` (${drivingExceededBACLimit} above legal BAC limit)` : "";

  const drivingWarning = drivingExceededBACLimit > 0 ?
    `SAFETY: On ${drivingExceededBACLimit} night(s) this month the user` +
    " said they would drive but BAC exceeded the legal limit." +
    " Address this in BEHAVIORAL INSIGHT." : "";

  return [
    coachPersona,
    "Write exactly 4 paragraphs separated by a blank line.",
    "No markdown, no bullets. Second person. Plain text only.",
    "Each paragraph starts with its label in ALL CAPS + colon.",
    "The 4th starts with OVERALL SYNTHESIS:\n",
    `User: ${userSex}, ${physique}, age ${userAge || "unknown"}.`,
    `Monthly guideline: ${monthlyLimit} standard drinks.\n`,
    `Month: ${monthName} ${year}`,
    `Nights out: ${nightCount} | Sober days: ${soberDays}`,
    `Total: ${totalDrinks} drinks`,
    `(${(totalStdDrinks || totalDrinks).toFixed(1)} std)`,
    `Total calories: ${Math.round(totalCalories || 0)} kcal`,
    `Peak BAC: ${(peakBac || 0).toFixed(3)} on ${peakBacNight || "unknown"}`,
    `Avg BAC/night: ${(avgBacPerNight || 0).toFixed(3)}`,
    `Trend vs prev month: ${trend}`,
    `Water: ${totalWater || 0} glasses total`,
    drinkBreakdown ? `Drink breakdown: ${drinkBreakdown}` : "",
    drivingLine,
    weeks ? `\nWeek-by-week:\n${weeks}` : "",
    "\nMEDICAL ANALYSIS: Full-month medical picture. Cumulative BAC",
    "exposure, organ load, any red flags. Reference physique.\n",
    "NUTRITION & METABOLISM: Nutritional impact of the specific",
    "drinks consumed. Caloric total, hydration pattern,",
    "one actionable goal for next month.\n",
    "BEHAVIORAL INSIGHT: Identify the dominant pace or timing pattern across",
    "the month — were nights consistently front-loaded, or well-spread?",
    "If fast pace was a pattern (high drinks/hour, short nights with many",
    "drinks), name ONE technique to carry into next month with a concrete",
    "target: e.g., 'one drink per 20 minutes', 'no more than 2 drinks in",
    "the first hour'. If the user paced well this month, explicitly",
    "acknowledge it as a habit worth protecting. Close with one SMART goal",
    "(specific number, action, and timeframe).",
    drivingWarning + "\n",
    "OVERALL SYNTHESIS: Two sentences tying all three together.",
    "Honest and motivating.",
  ].join("\n");
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
