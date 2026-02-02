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

    const scored = candidates.map((c, index) => {
      const { score, signalCount } = scoreItemWithSignals(c, session.preferenceWeights);
      return {
        candidate: c,
        score: normalizeScore(score, signalCount),
        index,
      };
    });

    scored.sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      return a.index - b.index;
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
