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
