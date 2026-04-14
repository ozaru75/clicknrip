import {
  createContext,
  createResource,
  useContext,
  type ParentProps,
} from "solid-js";
import { StarkZap, StarkSigner, type WalletInterface } from "starkzap";

const DEV_ACCOUNT_ADDRESS =
  "0x127fd5f1fe78a71f8bcd1fec63e3fe2f0486b6ecd5c86a0466c3a21fa5cfcec";
const DEV_PRIVATE_KEY =
  "0xc5b2fcab997346f3ea1c00b002ecf6f382c5f9c9659a3894eb783c5320f912";

const sdk = new StarkZap({
  network: "devnet",
  rpcUrl: import.meta.env.VITE_RPC_URL,
});

type WalletContextValue = {
  address: () => string | null;
  ready: () => boolean;
  connecting: () => boolean;
  error: () => string | null;
  connect: () => Promise<void>;
  disconnect: () => Promise<void>;
};

const WalletContext = createContext<WalletContextValue>();

async function connectDevWallet(): Promise<WalletInterface> {
  return sdk.connectWallet({
    account: { signer: new StarkSigner(DEV_PRIVATE_KEY) },
    accountAddress: DEV_ACCOUNT_ADDRESS,
  });
}

export function WalletProvider(props: ParentProps) {
  const [wallet, { refetch, mutate }] = createResource(connectDevWallet);

  const address = () => wallet()?.address.toString() ?? null;

  const ready = () =>
    wallet.state !== "unresolved" && wallet.state !== "pending";
  const connecting = () =>
    wallet.state === "pending" || wallet.state === "refreshing";

  const error = () => {
    const e = wallet.error;
    if (!e) return null;
    return e instanceof Error ? e.message : String(e);
  };

  async function connect() {
    await refetch();
  }

  async function disconnect() {
    mutate(undefined);
  }

  return (
    <WalletContext.Provider
      value={{ address, ready, connecting, error, connect, disconnect }}
    >
      {props.children}
    </WalletContext.Provider>
  );
}

export function useWallet(): WalletContextValue {
  const ctx = useContext(WalletContext);
  if (!ctx) throw new Error("useWallet must be used inside WalletProvider");
  return ctx;
}
