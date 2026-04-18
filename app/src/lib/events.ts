import { config } from "@/config";

export interface GuessResult {
  survived: boolean;
  deathTile: number;
  level: number;
}

export interface CashoutResult {
  payout: bigint;
}

type RawReceipt = {
  events?: Array<{ from_address: string; keys: string[]; data: string[] }>;
} & Record<string, unknown>;

// Dojo emits events from the World contract via world.emit_event
// keys: [event_selector, ...#[key] fields]
// GuessResolved: keys[1] = player, data = [id, level, guess, death_tile, survived] (5 felts)
// GameCreated:   keys[1] = player, data = [id, stake_low, stake_high]               (3 felts)
// GameEnded:     keys[1] = player, data = [id, status, payout_low, payout_high]     (4 felts)
// data.length uniquely identifies each event without needing the selector

function findPlayerWorldEvent(
  receipt: RawReceipt,
  playerAddress: string,
  dataLength: number,
) {
  if (!receipt.events) return null;
  const worldBigInt = BigInt(config.world);
  const playerBigInt = BigInt(playerAddress);
  return (
    receipt.events.find(
      (e) =>
        BigInt(e.from_address) === worldBigInt &&
        e.keys.length >= 2 &&
        BigInt(e.keys[1]) === playerBigInt &&
        e.data.length === dataLength,
    ) ?? null
  );
}

export function parseGuessResult(
  receipt: RawReceipt,
  playerAddress: string,
): GuessResult | null {
  const event = findPlayerWorldEvent(receipt, playerAddress, 5);
  if (!event) return null;
  return {
    level: Number(BigInt(event.data[1])),
    deathTile: Number(BigInt(event.data[3])),
    survived: BigInt(event.data[4]) !== 0n,
  };
}

export function parseCashoutResult(
  receipt: RawReceipt,
  playerAddress: string,
): CashoutResult | null {
  const event = findPlayerWorldEvent(receipt, playerAddress, 4);
  // status=2 means CashedOut; status=3 is Lost (no payout)
  if (!event || BigInt(event.data[1]) !== 2n) return null;
  const payout = BigInt(event.data[2]) + (BigInt(event.data[3]) << 128n);
  return { payout };
}
