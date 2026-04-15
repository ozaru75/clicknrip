import { createSignal, Show, createResource, createMemo, For } from "solid-js";
import { Amount, fromAddress } from "starkzap";
import { useWallet } from "@/providers/wallet";
import { config } from "@/config";
import { GAME_TOKEN, buildNewGameCall } from "@/lib/calls";
import { fetchActiveGame } from "@/lib/torii";
import { rowSizeForLevel, type ActiveGame } from "@/lib/game";

function GameBoard(props: { game: ActiveGame }) {
  const tileCount = () => rowSizeForLevel(props.game.level);

  return (
    <div>
      <p>Level {props.game.level}</p>
      <div>
        <For each={Array.from({ length: tileCount() }, (_, i) => i + 1)}>
          {(tile) => <button disabled>Box {tile}</button>}
        </For>
      </div>
    </div>
  );
}

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

  // Load active game from Torii when address changes
  const [gameResource, { refetch: refetchGame }] = createResource(
    () => address() ?? undefined,
    fetchActiveGame
  );

  // Loading state
  const gameLoading = () => gameResource.state === "pending";

  // Current game state (driven by Torii)
  const game = createMemo<ActiveGame | null>(() => {
    if (gameResource.state !== "ready") return null;
    return gameResource() ?? null;
  });

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

      // Refetch game state from Torii after tx confirms
      await refetchGame();
      setStakeInput("");
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

          <Show
            when={gameLoading()}
            fallback={
              <Show
                when={game()}
                fallback={
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
                }
              >
                {(g) => <GameBoard game={g()} />}
              </Show>
            }
          >
            <p>Loading game...</p>
          </Show>

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
