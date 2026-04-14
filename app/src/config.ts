import type { NetworkName } from "starkzap";

function required(key: string): string {
  const v = import.meta.env[key];
  if (!v) throw new Error(`${key} is not set`);
  return v;
}

export const config = {
  network: (import.meta.env.VITE_NETWORK ?? "devnet") as NetworkName,
  rpcUrl: import.meta.env.VITE_RPC_URL as string | undefined,
  actions: required("VITE_ACTIONS_ADDRESS"),
  pool: required("VITE_POOL_ADDRESS"),
  token: required("VITE_TOKEN_ADDRESS"),
  minStake: 2n * 10n ** 18n,
} as const;
