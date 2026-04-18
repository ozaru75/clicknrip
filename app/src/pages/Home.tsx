import {
  createSignal,
  createEffect,
  Show,
  createResource,
  For,
} from "solid-js";
import { Amount, fromAddress } from "starkzap";
import { useWallet } from "@/providers/wallet";
import { config } from "@/config";
import {
  GAME_TOKEN,
  buildNewGameCall,
  buildVrngRequestCall,
  buildNewGuessCall,
  buildCashoutCall,
} from "@/lib/calls";
import {
  fetchActiveGame,
  fetchLatestGuessResolved,
  subscribeToWorldEvent,
  type WorldEvent,
} from "@/lib/torii";
import { rowSizeForLevel, GAME_CONFIG, type ActiveGame } from "@/lib/game";
import {
  isGameCreatedEvent,
  isGuessResolvedEvent,
  isGameEndedEvent,
  parseGameCreatedFromEvent,
  parseGuessResultFromEvent,
  parseCashoutResultFromEvent,
  type GuessResult,
  type CashoutResult,
} from "@/lib/events";

function formatStrk(wei: bigint): string {
  return (Number(wei) / 1e18).toFixed(4);
}

function GameBoard(props: {
  game: ActiveGame;
  onGuess: (tile: number) => void;
  onCashout: () => void;
  disabled: boolean;
}) {
  const tileCount = () => rowSizeForLevel(props.game.level);
  const multiplierBps = () =>
    GAME_CONFIG.levelMultipliers[props.game.level - 1] ?? 100;
  const multiplierDisplay = () => (multiplierBps() / 100).toFixed(2) + "x";
  const payoutDisplay = () =>
    formatStrk((props.game.stake * BigInt(multiplierBps())) / 100n) + " STRK";

  return (
    <div>
      <p>Level {props.game.level}</p>
      <p>
        Deposit: {formatStrk(props.game.stake)} STRK &middot; Multiplier:{" "}
        {multiplierDisplay()} &middot; Payout: {payoutDisplay()}
      </p>
      <div>
        <For each={Array.from({ length: tileCount() }, (_, i) => i + 1)}>
          {(tile) => (
            <button
              onClick={() => props.onGuess(tile)}
              disabled={props.disabled}
            >
              Box {tile}
            </button>
          )}
        </For>
      </div>
      <Show when={props.game.level > 1}>
        <button onClick={props.onCashout} disabled={props.disabled}>
          Cash out
        </button>
      </Show>
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
  const [actionPending, setActionPending] = createSignal(false);
  const [guessResult, setGuessResult] = createSignal<GuessResult | null>(null);
  const [cashoutResult, setCashoutResult] = createSignal<CashoutResult | null>(
    null,
  );
  const [txHash, setTxHash] = createSignal<string | null>(null);
  const [gameError, setGameError] = createSignal<string | null>(null);

  // Torii is source of truth for initial load only
  // In-session state is managed via game signal below
  const [gameResource] = createResource(
    () => address() ?? undefined,
    fetchActiveGame,
  );

  // Fetch STRK balance when wallet connects
  const [balanceResource, { refetch: refetchBalance }] = createResource(
    () => wallet() ?? undefined,
    (w) => w.balanceOf(GAME_TOKEN),
  );

  // Writable game state: seeded from Torii on load, updated from WS events
  // after each action; avoids Torii HTTP round-trips in the hot path
  const [game, setGame] = createSignal<ActiveGame | null>(null);

  createEffect(() => {
    if (!address()) {
      setGame(null);
      return;
    }
    if (gameResource.state === "ready") {
      setGame(gameResource() ?? null);
    }
  });

  // Show loading spinner only during initial Torii fetch
  const gameLoading = () => gameResource.state === "pending";

  function clearActionState() {
    setGuessResult(null);
    setCashoutResult(null);
    setGameError(null);
    setTxHash(null);
  }

  async function newGame() {
    const w = wallet();
    const addr = address();
    if (!w || !addr) return;

    setPending(true);
    clearActionState();

    // Subscribe before sending so we catch the GameCreated event from the
    // pending block, not waiting for finalization
    let sub: { event: Promise<WorldEvent>; cancel: () => void };
    try {
      sub = await subscribeToWorldEvent((e) => isGameCreatedEvent(e, addr));
    } catch (e) {
      setGameError(
        e instanceof Error ? e.message : "Failed to connect to Torii",
      );
      setPending(false);
      return;
    }

    try {
      const amount = Amount.parse(stakeInput(), GAME_TOKEN);
      if (amount.toBase() < config.minStake) {
        throw new Error("Minimum stake is 2 STRK");
      }

      const tx = await w
        .tx()
        .approve(GAME_TOKEN, fromAddress(config.pool), amount)
        .add(buildNewGameCall(amount.toBase()))
        .send()
        .catch((e: unknown) => {
          sub.cancel();
          throw e;
        });

      setTxHash(tx.hash);

      const event = await sub.event;
      const { id, stake } = parseGameCreatedFromEvent(event);
      setGame({ id, level: 1, status: "Active", stake });
      setStakeInput("");

      // Update balance after finalization (stake left the wallet)
      void tx
        .wait()
        .then(() => refetchBalance())
        .catch(() => {});
    } catch (e) {
      setGameError(e instanceof Error ? e.message : "Transaction failed");
    } finally {
      setPending(false);
    }
  }

  async function newGuess(tile: number) {
    const w = wallet();
    const addr = address();
    if (!w || !addr) return;

    setActionPending(true);
    clearActionState();

    let sub: { event: Promise<WorldEvent>; cancel: () => void };
    try {
      sub = await subscribeToWorldEvent((e) => isGuessResolvedEvent(e, addr));
    } catch (e) {
      setGameError(
        e instanceof Error ? e.message : "Failed to connect to Torii",
      );
      setActionPending(false);
      return;
    }

    try {
      const tx = await w
        .tx()
        .add(buildVrngRequestCall(addr))
        .add(buildNewGuessCall(tile))
        .send()
        .catch((e: unknown) => {
          sub.cancel();
          throw e;
        });

      setTxHash(tx.hash);

      const event = await sub.event;
      const result = parseGuessResultFromEvent(event);
      const currentGame = game();
      setGuessResult(result);

      if (result.survived) {
        setGame((g) => (g ? { ...g, level: result.level } : null));
      } else {
        setGame(null);
      }

      // Fetch death_tile from GuessResolved event (not in entity model)
      if (currentGame) {
        void fetchLatestGuessResolved(addr, currentGame.id).then((data) => {
          if (data)
            setGuessResult((r) =>
              r ? { ...r, deathTile: data.deathTile } : null,
            );
        });
      }
    } catch (e) {
      if (e instanceof DOMException && e.name === "AbortError") return;
      setGameError(e instanceof Error ? e.message : "Transaction failed");
    } finally {
      setActionPending(false);
    }
  }

  async function cashout() {
    const w = wallet();
    const addr = address();
    if (!w || !addr) return;

    setActionPending(true);
    clearActionState();

    let sub: { event: Promise<WorldEvent>; cancel: () => void };
    try {
      sub = await subscribeToWorldEvent((e) => isGameEndedEvent(e, addr));
    } catch (e) {
      setGameError(
        e instanceof Error ? e.message : "Failed to connect to Torii",
      );
      setActionPending(false);
      return;
    }

    try {
      const tx = await w
        .tx()
        .add(buildCashoutCall())
        .send()
        .catch((e: unknown) => {
          sub.cancel();
          throw e;
        });

      setTxHash(tx.hash);

      const event = await sub.event;
      const result = parseCashoutResultFromEvent(event);
      setCashoutResult(result);
      setGame(null);

      // Update balance after finalization (payout arrived)
      void tx
        .wait()
        .then(() => refetchBalance())
        .catch(() => {});
    } catch (e) {
      if (e instanceof DOMException && e.name === "AbortError") return;
      setGameError(e instanceof Error ? e.message : "Transaction failed");
    } finally {
      setActionPending(false);
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
                    <Show when={balanceResource()}>
                      {(b) => <p>Balance: {b().toFormatted()}</p>}
                    </Show>
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
                {(g) => (
                  <GameBoard
                    game={g()}
                    onGuess={newGuess}
                    onCashout={cashout}
                    disabled={actionPending()}
                  />
                )}
              </Show>
            }
          >
            <p>Loading game...</p>
          </Show>

          <Show when={guessResult()}>
            {(r) => (
              <p>
                {r().survived
                  ? `Survived! Death tile was ${r().deathTile}.`
                  : `Lost. Death tile was ${r().deathTile}.`}
              </p>
            )}
          </Show>
          <Show when={cashoutResult()}>
            {(r) => <p>Cashed out {formatStrk(r().payout)} STRK.</p>}
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
