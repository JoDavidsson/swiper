import { nanoid } from "nanoid";
import { normalizeScore, scoreItemWithSignals } from "./scoreItem";
import type { ItemCandidate, PersonaSignals, RankOptions, RankResult, Ranker, SessionContext } from "./types";

const ALGORITHM_VERSION = "preference_weights_v1";

/**
 * Personal-only ranker: scores and sorts by SessionContext.preferenceWeights.
 * Ignores personaSignals. No Firestore; deterministic except for runId.
 */
export const PreferenceWeightsRanker: Ranker = {
  rank(
    session: SessionContext,
    candidates: ItemCandidate[],
    options: RankOptions,
    _personaSignals?: PersonaSignals
  ): RankResult {
    const limit = Math.max(0, options.limit);
    const algorithmVersion = options.algorithmVersion ?? ALGORITHM_VERSION;
    const runId = nanoid(12);

    // Generate deterministic random seed from runId for reproducible tie-breaking
    const seedRandom = (seed: string) => {
      let h = 0;
      for (let i = 0; i < seed.length; i++) {
        h = ((h << 5) - h + seed.charCodeAt(i)) | 0;
      }
      return () => {
        h = ((h << 13) ^ h) | 0;
        h = ((h >> 17) ^ h) | 0;
        h = ((h << 5) ^ h) | 0;
        return (h >>> 0) / 4294967296;
      };
    };
    const random = seedRandom(runId);

    const scored = candidates.map((c) => {
      const { score, signalCount } = scoreItemWithSignals(c, session.preferenceWeights);
      return {
        candidate: c,
        score: normalizeScore(score, signalCount),
        signalCount,
        tieBreaker: random(), // Random value for breaking ties
      };
    });

    scored.sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      return a.tieBreaker - b.tieBreaker; // Random tie-breaking instead of scraping order
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
