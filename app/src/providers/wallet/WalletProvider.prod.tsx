import {
  createContext,
  createMemo,
  createSignal,
  onMount,
  useContext,
  type ParentProps,
} from "solid-js";
import { StarkZap, type WalletInterface, type NetworkName } from "starkzap";

const sdk = new StarkZap({
  network: (import.meta.env.VITE_NETWORK as NetworkName) ?? "sepolia",
});

// TODO: populate once contract addresses are finalized
const GAME_POLICIES: never[] = [];

const STORAGE_KEY = "cnr_address";

type WalletContextValue = {
  address: () => string | null;
  ready: () => boolean;
  connecting: () => boolean;
  error: () => string | null;
  connect: () => Promise<void>;
  disconnect: () => Promise<void>;
};

const WalletContext = createContext<WalletContextValue>();

export function WalletProvider(props: ParentProps) {
  const [wallet, setWallet] = createSignal<WalletInterface | null>(null);
  const [ready, setReady] = createSignal(false);
  const [connecting, setConnecting] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);
  const [storedAddr, setStoredAddr] = createSignal<string | null>(
    localStorage.getItem(STORAGE_KEY),
  );

  // Show cached address instantly on load, switch to live wallet once probe settles
  const address = createMemo(
    () => wallet()?.address.toString() ?? storedAddr(),
  );

  function persistAddress(addr: string | null) {
    if (addr) {
      localStorage.setItem(STORAGE_KEY, addr);
    } else {
      localStorage.removeItem(STORAGE_KEY);
    }
    setStoredAddr(addr);
  }

  onMount(async () => {
    try {
      const w = await sdk.probeCartridge({ policies: GAME_POLICIES });
      if (w) {
        setWallet(w);
        persistAddress(w.address.toString());
      } else {
        persistAddress(null);
      }
    } catch {
      persistAddress(null);
    } finally {
      setReady(true);
    }
  });

  async function connect() {
    if (connecting()) return;
    setConnecting(true);
    setError(null);
    try {
      // connectCartridge never resolves if the user closes the popup without logging in
      let observer: MutationObserver | undefined;
      const w = await Promise.race([
        sdk.connectCartridge({ policies: GAME_POLICIES }),
        new Promise<null>((resolve) => {
          const container = document.querySelector(
            'iframe[id^="controller-"]',
          )?.parentElement;
          if (!container) return;
          observer = new MutationObserver(() => {
            if (container.style.display === "none") {
              observer!.disconnect();
              resolve(null);
            }
          });
          observer.observe(container, {
            attributes: true,
            attributeFilter: ["style"],
          });
        }),
      ]);
      observer?.disconnect();
      if (w) {
        setWallet(w);
        persistAddress(w.address.toString());
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Connection failed");
    } finally {
      setConnecting(false);
    }
  }

  async function disconnect() {
    try {
      await wallet()?.disconnect();
    } catch {
    } finally {
      setWallet(null);
      persistAddress(null);
      setError(null);
    }
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
