import { Show } from "solid-js";
import { useWallet } from "../providers/WalletProvider";

export function Home() {
  const wallet = useWallet();

  return (
    <main>
      <Show when={wallet.ready()} fallback={<p>Loading...</p>}>
        <Show
          when={wallet.address()}
          fallback={
            <button onClick={wallet.connect} disabled={wallet.connecting()}>
              {wallet.connecting() ? "Connecting..." : "Connect"}
            </button>
          }
        >
          <p>{wallet.address()}</p>
          <button onClick={wallet.disconnect}>Disconnect</button>
        </Show>
        <Show when={wallet.error()}>
          <p>{wallet.error()}</p>
        </Show>
      </Show>
    </main>
  );
}
