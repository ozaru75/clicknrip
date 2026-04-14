import {
  createContext,
  createResource,
  useContext,
  type ParentProps,
} from "solid-js";
import { StarkZap, StarkSigner, type WalletInterface } from "starkzap";

const DEV_ACCOUNT_ADDRESS =
  "0x2af9427c5a277474c079a1283c880ee8a6f0f8fbf73ce969c08d88befec1bba";
const DEV_PRIVATE_KEY =
  "0x1800000000300000180000000000030000000000003006001800006600";

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
