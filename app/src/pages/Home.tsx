import { createSignal, Show } from "solid-js";
import { Amount, fromAddress } from "starkzap";
import { useWallet } from "@/providers/wallet";
import { config } from "@/config";
import { GAME_TOKEN, buildNewGameCall } from "@/lib/calls";

export function Home() {
  const {
    address,
    ready,
    connecting,
    error: walletError,
    connect,
    disconnect,
    wallet,
  } = useWallet();

  const [stakeInput, setStakeInput] = createSignal("");
  const [pending, setPending] = createSignal(false);
  const [txHash, setTxHash] = createSignal<string | null>(null);
  const [gameError, setGameError] = createSignal<string | null>(null);

  async function newGame() {
    const w = wallet();
    if (!w) return;

    setPending(true);
    setGameError(null);
    setTxHash(null);

    try {
      const amount = Amount.parse(stakeInput(), GAME_TOKEN);
      if (amount.toBase() < config.minStake) {
        throw new Error("Minimum stake is 2 STRK");
      }

      const tx = await w
        .tx()
        .approve(GAME_TOKEN, fromAddress(config.pool), amount)
        .add(buildNewGameCall(amount.toBase()))
        .send();

      setTxHash(tx.hash);
      await tx.wait();
    } catch (e) {
      setGameError(e instanceof Error ? e.message : "Transaction failed");
    } finally {
      setPending(false);
    }
  }

  return (
    <main>
      <Show when={ready()} fallback={<p>Loading...</p>}>
        <Show
          when={address()}
          fallback={
            <button onClick={connect} disabled={connecting()}>
              {connecting() ? "Connecting..." : "Connect"}
            </button>
          }
        >
          <p>{address()}</p>
          <button onClick={disconnect}>Disconnect</button>

          <div>
            <input
              type="number"
              placeholder="Stake (STRK)"
              value={stakeInput()}
              onInput={(e) => setStakeInput(e.currentTarget.value)}
              disabled={pending()}
              min="2"
              step="0.1"
            />
            <button onClick={newGame} disabled={pending()}>
              {pending() ? "Pending..." : "New Game"}
            </button>
          </div>

          <Show when={txHash()}>
            <p>tx: {txHash()}</p>
          </Show>
          <Show when={gameError()}>
            <p>{gameError()}</p>
          </Show>
        </Show>

        <Show when={walletError()}>
          <p>{walletError()}</p>
        </Show>
      </Show>
    </main>
  );
}
