/**
 * Pacing utilities for Featured Distribution campaign budget management.
 *
 * Given a campaign budget, start/end dates, and pacing strategy —
 * calculate how much budget to show per day/hour.
 */

export type PacingStrategy = "even" | "frontload" | "backload";

/**
 * Budget allocation per day (in cents).
 * Key = ISO date string (YYYY-MM-DD), Value = cents to show that day.
 */
export type PacingMap = Map<string, number>;

/**
 * Calculate the pacing map for a campaign.
 *
 * @param budgetCents - Total campaign budget in cents
 * @param startDate - Campaign start date
 * @param endDate - Campaign end date
 * @param strategy - Pacing strategy (even, frontload, backload)
 * @returns Map of date string (YYYY-MM-DD) to budget in cents for that day
 */
export function calculatePacing(
  budgetCents: number,
  startDate: Date,
  endDate: Date,
  strategy: PacingStrategy
): PacingMap {
  const pacingMap: PacingMap = new Map();

  if (budgetCents <= 0 || startDate > endDate) {
    return pacingMap;
  }

  // Get all days in the range (inclusive)
  const days = getDaysInRange(startDate, endDate);
  const totalDays = days.length;

  if (totalDays === 0) {
    return pacingMap;
  }

  switch (strategy) {
    case "even":
      distributeEvenly(pacingMap, days, budgetCents);
      break;
    case "frontload":
      distributeFrontload(pacingMap, days, budgetCents);
      break;
    case "backload":
      distributeBackload(pacingMap, days, budgetCents);
      break;
  }

  return pacingMap;
}

/**
 * Get all dates in a range (inclusive), as ISO date strings.
 */
function getDaysInRange(startDate: Date, endDate: Date): string[] {
  const days: string[] = [];
  const current = new Date(startDate);
  current.setHours(0, 0, 0, 0);
  const end = new Date(endDate);
  end.setHours(23, 59, 59, 999);

  while (current <= end) {
    days.push(toDateString(current));
    current.setDate(current.getDate() + 1);
  }

  return days;
}

/**
 * Convert Date to YYYY-MM-DD string.
 */
function toDateString(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

/**
 * Even distribution: each day gets an equal share.
 * Uses floor for daily amounts, remainder goes to last day.
 */
function distributeEvenly(pacingMap: PacingMap, days: string[], budgetCents: number): void {
  const dailyAmount = Math.floor(budgetCents / days.length);
  let remaining = budgetCents - dailyAmount * days.length;

  for (const day of days) {
    let amount = dailyAmount;
    // Add any leftover cents to the last day
    if (remaining > 0) {
      amount += 1;
      remaining -= 1;
    }
    pacingMap.set(day, amount);
  }
}

/**
 * Frontload: exponential decay - most budget at the start, tapering off.
 * Uses a power curve where earlier days get significantly more.
 *
 * Formula: day i gets budget proportional to (totalDays - i + 1)^alpha
 * with alpha tuned so the curve looks good (alpha = 1.5 gives nice decay).
 */
function distributeFrontload(pacingMap: PacingMap, days: string[], budgetCents: number): void {
  const totalDays = days.length;
  const alpha = 1.5; // tuning factor for decay steepness

  // Calculate weights
  const weights: number[] = [];
  let totalWeight = 0;

  for (let i = 0; i < totalDays; i++) {
    const weight = Math.pow(totalDays - i, alpha);
    weights.push(weight);
    totalWeight += weight;
  }

  // Distribute budget proportionally to weights
  let remaining = budgetCents;

  for (let i = 0; i < totalDays; i++) {
    const day = days[i];
    const proportion = weights[i] / totalWeight;
    let amount = Math.round(budgetCents * proportion);

    // Last day gets any leftover to ensure we distribute all budget
    if (i === totalDays - 1) {
      amount = remaining;
    }

    // Ensure non-negative
    amount = Math.max(0, Math.min(amount, remaining));
    pacingMap.set(day, amount);
    remaining -= amount;
  }
}

/**
 * Backload: inverse of frontload - most budget at the end, ramping up.
 * Uses exponential growth where later days get more.
 */
function distributeBackload(pacingMap: PacingMap, days: string[], budgetCents: number): void {
  const totalDays = days.length;
  const alpha = 1.5; // tuning factor for growth steepness

  // Calculate weights (reverse of frontload)
  const weights: number[] = [];
  let totalWeight = 0;

  for (let i = 0; i < totalDays; i++) {
    const weight = Math.pow(i + 1, alpha);
    weights.push(weight);
    totalWeight += weight;
  }

  // Distribute budget proportionally to weights
  let remaining = budgetCents;

  for (let i = 0; i < totalDays; i++) {
    const day = days[i];
    const proportion = weights[i] / totalWeight;
    let amount = Math.round(budgetCents * proportion);

    // Last day gets any leftover to ensure we distribute all budget
    if (i === totalDays - 1) {
      amount = remaining;
    }

    // Ensure non-negative
    amount = Math.max(0, Math.min(amount, remaining));
    pacingMap.set(day, amount);
    remaining -= amount;
  }
}

/**
 * Get the hourly breakdown for a specific day from the pacing map.
 * Useful when you need finer granularity than daily.
 *
 * @param dailyBudget - Budget allocated for the day (in cents)
 * @param strategy - Pacing strategy (affects hourly distribution)
 * @returns Map of hour (0-23) to budget in cents for that hour
 */
export function getHourlyBreakdown(
  dailyBudget: number,
  strategy: PacingStrategy
): Map<number, number> {
  const hourlyMap = new Map<number, number>();

  if (dailyBudget <= 0) {
    return hourlyMap;
  }

  switch (strategy) {
    case "even":
      // Even distribution across all 24 hours
      distributeEvenlyHours(hourlyMap, 24, dailyBudget);
      break;
    case "frontload":
      // More budget in early hours (8am-12pm peak)
      distributePeakHours(hourlyMap, dailyBudget, "morning");
      break;
    case "backload":
      // More budget in late hours (6pm-10pm peak)
      distributePeakHours(hourlyMap, dailyBudget, "evening");
      break;
  }

  return hourlyMap;
}

function distributeEvenlyHours(hourlyMap: Map<number, number>, hours: number, budget: number): void {
  const hourlyAmount = Math.floor(budget / hours);
  let remaining = budget - hourlyAmount * hours;

  for (let h = 0; h < hours; h++) {
    let amount = hourlyAmount;
    if (remaining > 0) {
      amount += 1;
      remaining -= 1;
    }
    hourlyMap.set(h, amount);
  }
}

type PeakTime = "morning" | "evening";

function distributePeakHours(hourlyMap: Map<number, number>, budget: number, peak: PeakTime): void {
  // 24 hours, distribute with peak at different times
  // Morning peak: 8am-12pm (hours 8-12)
  // Evening peak: 6pm-10pm (hours 18-22)

  const peakStart = peak === "morning" ? 8 : 18;
  const peakEnd = peak === "morning" ? 12 : 22;

  // Calculate weights: higher for peak hours
  const weights: number[] = [];
  let totalWeight = 0;

  for (let h = 0; h < 24; h++) {
    let weight: number;
    if (h >= peakStart && h < peakEnd) {
      weight = 3; // Peak hours get 3x weight
    } else if (h >= 6 && h < 23) {
      weight = 1; // Regular waking hours
    } else {
      weight = 0.2; // Night hours (11pm-6am) get much less
    }
    weights.push(weight);
    totalWeight += weight;
  }

  let remaining = budget;

  for (let h = 0; h < 24; h++) {
    const proportion = weights[h] / totalWeight;
    let amount = Math.round(budget * proportion);

    if (h === 23) {
      amount = remaining; // Last hour gets any leftover
    }

    amount = Math.max(0, Math.min(amount, remaining));
    hourlyMap.set(h, amount);
    remaining -= amount;
  }
}
