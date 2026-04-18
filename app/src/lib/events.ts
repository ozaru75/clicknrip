import type { WorldEvent, GameEntityModel } from "./torii";

export interface GuessResult {
  survived: boolean;
  deathTile: number;
  level: number;
}

export interface CashoutResult {
  payout: bigint;
}

function findGameModel(event: WorldEvent): GameEntityModel | undefined {
  return event.models.find((m) => m.__typename === "clicknrip_Game") as
    | GameEntityModel
    | undefined;
}

function matchesPlayer(event: WorldEvent, playerAddress: string): boolean {
  const game = findGameModel(event);
  if (!game) return false;
  try {
    return BigInt(game.player) === BigInt(playerAddress);
  } catch {
    return false;
  }
}

export function isGameCreatedEvent(
  event: WorldEvent,
  playerAddress: string,
): boolean {
  const game = findGameModel(event);
  return (
    !!game && matchesPlayer(event, playerAddress) && game.status === "Active"
  );
}

export function isGuessResolvedEvent(
  event: WorldEvent,
  playerAddress: string,
): boolean {
  return !!findGameModel(event) && matchesPlayer(event, playerAddress);
}

export function isGameEndedEvent(
  event: WorldEvent,
  playerAddress: string,
): boolean {
  const game = findGameModel(event);
  return (
    !!game && matchesPlayer(event, playerAddress) && game.status === "CashedOut"
  );
}

export function parseGameCreatedFromEvent(event: WorldEvent): {
  id: number;
  stake: bigint;
} {
  const game = findGameModel(event)!;
  return { id: game.id, stake: BigInt(game.stake) };
}

// deathTile is 0 here; caller populates it async via fetchLatestGuessResolved
export function parseGuessResultFromEvent(event: WorldEvent): GuessResult {
  const game = findGameModel(event)!;
  return {
    level: game.level,
    survived: game.status === "Active",
    deathTile: 0,
  };
}

// Returns null if the game entity is not in CashedOut status
export function parseCashoutResultFromEvent(
  event: WorldEvent,
): CashoutResult | null {
  const game = findGameModel(event);
  if (!game || game.status !== "CashedOut") return null;
  return { payout: BigInt(game.payout) };
}
