import { nanoid } from "nanoid";
import { normalizeScore, scoreItemWithSignals } from "./scoreItem";
import type { ItemCandidate, PersonaSignals, RankOptions, RankResult, Ranker, SessionContext } from "./types";

const ALGORITHM_VERSION = "personal_plus_persona_v1";

const DEFAULT_ALPHA = 0.7; // alpha * personal + (1 - alpha) * persona
const MIN_ALPHA_WHEN_NO_PERSONAL = 0.2;

function getPersonaScore(
  candidateId: string,
  personaScores: Record<string, number>,
  popularAmongSimilar: string[]
): number {
  let personaScore = personaScores[candidateId] ?? 0;
  if (personaScore === 0 && popularAmongSimilar.length > 0) {
    const idx = popularAmongSimilar.indexOf(candidateId);
    if (idx >= 0) personaScore = Math.max(0, popularAmongSimilar.length - idx);
  }
  return personaScore;
}

/**
 * Blends personal score (from preferenceWeights) with persona score (from PersonaSignals).
 * When personaSignals is missing or empty, falls back to personal-only (same as PreferenceWeightsRanker).
 */
export function createPersonalPlusPersonaRanker(alpha: number = DEFAULT_ALPHA): Ranker {
  return {
    rank(
      session: SessionContext,
      candidates: ItemCandidate[],
      options: RankOptions,
      personaSignals?: PersonaSignals
    ): RankResult {
      const limit = Math.max(0, options.limit);
      const algorithmVersion = options.algorithmVersion ?? ALGORITHM_VERSION;
      const runId = nanoid(12);

      const personaScores = personaSignals?.itemScoresFromSimilarSessions ?? {};
      const popularAmongSimilar = personaSignals?.popularAmongSimilar ?? [];
      const hasPersona = Object.keys(personaScores).length > 0 || popularAmongSimilar.length > 0;
      const hasAnyPersonalWeights = Object.values(session.preferenceWeights).some(
        (value) => typeof value === "number" && value !== 0
      );

      const rawPersonaScores = candidates.map((c) =>
        getPersonaScore(c.id as string, personaScores, popularAmongSimilar)
      );
      const maxPersonaScore = rawPersonaScores.reduce((max, score) => Math.max(max, score), 0);

      const scored = candidates.map((c, idx) => {
        const { score: personalScoreRaw, signalCount } = scoreItemWithSignals(c, session.preferenceWeights);
        const personalScore = normalizeScore(personalScoreRaw, signalCount);
        const personaScoreRaw = rawPersonaScores[idx];
        const personaScore = maxPersonaScore > 0 ? personaScoreRaw / maxPersonaScore : 0;

        let effectiveAlpha = hasAnyPersonalWeights ? alpha : 0;
        if (signalCount === 0) {
          effectiveAlpha = Math.min(effectiveAlpha, MIN_ALPHA_WHEN_NO_PERSONAL);
        }

        const blend = hasPersona ? effectiveAlpha * personalScore + (1 - effectiveAlpha) * personaScore : personalScore;
        return { candidate: c, score: blend };
      });

      scored.sort((a, b) => {
        if (b.score !== a.score) return b.score - a.score;
        return (a.candidate.id as string).localeCompare(b.candidate.id as string);
      });

      const sliced = scored.slice(0, limit);
      const itemIds = sliced.map((s) => s.candidate.id as string);
      const itemScores: Record<string, number> = {};
      for (const s of sliced) {
        itemScores[s.candidate.id as string] = s.score;
      }

      return {
        runId,
        algorithmVersion,
        itemIds,
        itemScores,
      };
    },
  };
}

export const PersonalPlusPersonaRanker = createPersonalPlusPersonaRanker();
