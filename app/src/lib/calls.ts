import { fromAddress, type Call, type Token } from "starkzap";
import { config } from "@/config";

// Token descriptor for the game's ERC20 token
export const GAME_TOKEN: Token = {
  name: "STRK",
  symbol: "STRK",
  decimals: 18,
  address: fromAddress(config.token),
};

// u256 is encoded as two felts [low, high]
export function buildNewGameCall(stake: bigint): Call {
  return {
    contractAddress: fromAddress(config.actions),
    entrypoint: "new_game",
    calldata: [stake.toString(), "0"],
  };
}

// Source::Nonce(address) serializes as [variant=0, address]
export function buildVrngRequestCall(playerAddress: string): Call {
  return {
    contractAddress: fromAddress(config.vrng),
    entrypoint: "request_random",
    calldata: [fromAddress(config.actions), "0", playerAddress],
  };
}

export function buildNewGuessCall(guess: number): Call {
  return {
    contractAddress: fromAddress(config.actions),
    entrypoint: "new_guess",
    calldata: [guess.toString()],
  };
}

export function buildCashoutCall(): Call {
  return {
    contractAddress: fromAddress(config.actions),
    entrypoint: "cashout",
    calldata: [],
  };
}
