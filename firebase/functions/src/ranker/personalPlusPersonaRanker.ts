import { nanoid } from "nanoid";
import { scoreItem } from "./scoreItem";
import type { ItemCandidate, PersonaSignals, RankOptions, RankResult, Ranker, SessionContext } from "./types";

const ALGORITHM_VERSION = "personal_plus_persona_v1";

const DEFAULT_ALPHA = 0.7; // alpha * personal + (1 - alpha) * persona

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

      const scored = candidates.map((c) => {
        const personalScore = scoreItem(c, session.preferenceWeights);
        let personaScore = personaScores[c.id as string] ?? 0;
        if (personaScore === 0 && popularAmongSimilar.length > 0) {
          const idx = popularAmongSimilar.indexOf(c.id as string);
          if (idx >= 0) personaScore = Math.max(0, popularAmongSimilar.length - idx);
        }
        const blend = hasPersona ? alpha * personalScore + (1 - alpha) * personaScore : personalScore;
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
