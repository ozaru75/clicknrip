export type GameStatus = "None" | "Active" | "CashedOut" | "Lost";

export interface ActiveGame {
  id: number;
  level: number;
  status: GameStatus;
}

export interface GameConfig {
  levelMax: number;
  rowSizes: readonly number[];
  levelMultipliers: readonly number[];
}

// Game settings from contract (CONTRACTS.md: Key constants)
export const GAME_CONFIG: GameConfig = {
  levelMax: 25,
  rowSizes: [7, 6, 5, 4, 3, 4, 5, 6],  // cycles every 8 levels
  levelMultipliers: [110, 133, 166, 221, 332, 443, 554, 665, 775, 931, 1163, 1551, 2327, 3103, 3879, 4655, 5430, 6517, 8146, 10861, 16292, 21723, 27154, 32585, 38015],
} as const;

export function rowSizeForLevel(level: number): number {
  return GAME_CONFIG.rowSizes[(level - 1) & 7];
}
