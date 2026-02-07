/**
 * Ranker types for the recommendations engine.
 * Item attributes used for scoring: style/material/color/size and richer commerce
 * attributes such as brand, delivery complexity, condition, eco tags, features,
 * and price bucket (derived from priceAmount).
 */

export type ItemCandidate = { id: string } & Record<string, unknown>;

export type SessionContext = {
  preferenceWeights: Record<string, number>;
};

export type PersonaSignals = {
  itemScoresFromSimilarSessions?: Record<string, number>;
  popularAmongSimilar?: string[];
};

export type RankOptions = {
  limit: number;
  algorithmVersion?: string;
};

export type RankResult = {
  runId: string;
  algorithmVersion: string;
  itemIds: string[];
  itemScores: Record<string, number>;
};

export interface Ranker {
  rank(
    session: SessionContext,
    candidates: ItemCandidate[],
    options: RankOptions,
    personaSignals?: PersonaSignals
  ): RankResult;
}
