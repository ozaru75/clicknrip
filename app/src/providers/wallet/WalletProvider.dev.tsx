import {
  createContext,
  createResource,
  useContext,
  type ParentProps,
} from "solid-js";
import {
  StarkZap,
  StarkSigner,
  fromAddress,
  type WalletInterface,
} from "starkzap";
import { config } from "@/config";

const DEV_ACCOUNT_ADDRESS =
  "0x2af9427c5a277474c079a1283c880ee8a6f0f8fbf73ce969c08d88befec1bba";
const DEV_PRIVATE_KEY =
  "0x1800000000300000180000000000030000000000003006001800006600";

const sdk = new StarkZap({
  network: config.network,
  rpcUrl: config.rpcUrl,
});

type WalletContextValue = {
  address: () => string | null;
  ready: () => boolean;
  connecting: () => boolean;
  error: () => string | null;
  connect: () => Promise<void>;
  disconnect: () => Promise<void>;
  wallet: () => WalletInterface | null;
};

const WalletContext = createContext<WalletContextValue>();

async function connectDevWallet(): Promise<WalletInterface> {
  return sdk.connectWallet({
    account: { signer: new StarkSigner(DEV_PRIVATE_KEY) },
    accountAddress: fromAddress(DEV_ACCOUNT_ADDRESS),
  });
}

export function WalletProvider(props: ParentProps) {
  const [walletResource, { refetch, mutate }] =
    createResource(connectDevWallet);

  const address = () => walletResource()?.address.toString() ?? null;

  const ready = () =>
    walletResource.state !== "unresolved" && walletResource.state !== "pending";
  const connecting = () =>
    walletResource.state === "pending" || walletResource.state === "refreshing";

  const error = () => {
    const e = walletResource.error;
    if (!e) return null;
    return e instanceof Error ? e.message : String(e);
  };

  async function connect() {
    await refetch();
  }

  async function disconnect() {
    mutate(undefined);
  }

  const wallet = () => walletResource() ?? null;

  return (
    <WalletContext.Provider
      value={{ address, ready, connecting, error, connect, disconnect, wallet }}
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
