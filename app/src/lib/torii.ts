import { config } from "@/config";
import type { ActiveGame, GameStatus } from "./game";

// Entity model returned by entityUpdated subscription
export interface GameEntityModel {
  __typename: "clicknrip_Game";
  id: number;
  player: string;
  level: number;
  status: string;
  stake: string;
  payout: string;
}

export type EntityModel = GameEntityModel;

export interface WorldEvent {
  keys: string[];
  models: EntityModel[];
}

// Subscribe-before-send: resolves after connection_ack, before tx is sent
// The returned event promise resolves on the first matching entity update
export function subscribeToWorldEvent(
  predicate: (event: WorldEvent) => boolean,
): Promise<{ event: Promise<WorldEvent>; cancel: () => void }> {
  if (!config.toriiUrl) throw new Error("VITE_TORII_URL not configured");
  const wsUrl = config.toriiUrl.replace(/^http/, "ws") + "/graphql";

  let resolveEvent!: (e: WorldEvent) => void;
  let rejectEvent!: (e: unknown) => void;
  const eventPromise = new Promise<WorldEvent>((res, rej) => {
    resolveEvent = res;
    rejectEvent = rej;
  });

  return new Promise<{ event: Promise<WorldEvent>; cancel: () => void }>(
    (resolveReady, rejectReady) => {
      const ws = new WebSocket(wsUrl, "graphql-transport-ws");
      let subscribed = false;
      let eventSettled = false;

      function cancel(): void {
        if (eventSettled) return;
        eventSettled = true;
        ws.close();
        rejectEvent(new DOMException("Cancelled", "AbortError"));
      }

      function failEvent(err: Error): void {
        if (eventSettled) return;
        eventSettled = true;
        ws.close();
        rejectEvent(err);
      }

      ws.onopen = () => {
        ws.send(JSON.stringify({ type: "connection_init" }));
      };

      ws.onmessage = (msg: MessageEvent<string>) => {
        type Frame = { type: string; id?: string; payload?: unknown };
        let frame: Frame;
        try {
          frame = JSON.parse(msg.data) as Frame;
        } catch {
          return;
        }

        if (frame.type === "connection_ack") {
          ws.send(
            JSON.stringify({
              id: "1",
              type: "subscribe",
              payload: {
                query: `subscription { entityUpdated { keys models { __typename ... on clicknrip_Game { id player level status stake payout } } } }`,
              },
            }),
          );
          subscribed = true;
          resolveReady({ event: eventPromise, cancel });
          return;
        }

        if (frame.type === "next" && frame.id == "1") {
          type Payload = { data?: { entityUpdated?: WorldEvent } };
          const event = (frame.payload as Payload)?.data?.entityUpdated;
          if (event && predicate(event)) {
            if (!eventSettled) {
              eventSettled = true;
              ws.close();
              resolveEvent(event);
            }
          }
          return;
        }

        if (frame.type === "error") {
          const err = new Error("Torii subscription error");
          if (!subscribed) rejectReady(err);
          else failEvent(err);
        }
      };

      ws.onclose = (e) => {
        if (!eventSettled) {
          failEvent(new Error(`WebSocket closed (code: ${e.code})`));
        }
      };

      ws.onerror = () => {
        const err = new Error("Torii WebSocket error");
        if (!subscribed) rejectReady(err);
        else failEvent(err);
      };
    },
  );
}

async function toriiQuery<T>(
  query: string,
  variables: Record<string, unknown>,
): Promise<T> {
  if (!config.toriiUrl) {
    throw new Error("VITE_TORII_URL not configured");
  }

  const res = await fetch(`${config.toriiUrl}/graphql`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query, variables }),
  });

  if (!res.ok) {
    throw new Error(`Torii HTTP error: ${res.status}`);
  }

  const json = (await res.json()) as {
    data?: T;
    errors?: { message: string }[];
  };

  if (json.errors?.length) {
    throw new Error(`Torii GraphQL error: ${json.errors[0].message}`);
  }

  if (!json.data) {
    throw new Error("No data in Torii response");
  }

  return json.data;
}

const STATS_QUERY = `
  query GetPlayerStats($address: String!) {
    clicknripPlayerStatsModels(where: { playerEQ: $address }) {
      edges { node { last_game_id } }
    }
  }
`;

const GAME_QUERY = `
  query GetGame($gameId: Int!) {
    clicknripGameModels(where: { idEQ: $gameId }) {
      edges { node { id status level stake } }
    }
  }
`;

export async function fetchActiveGame(
  address: string,
): Promise<ActiveGame | null> {
  const statsData = await toriiQuery<{
    clicknripPlayerStatsModels: {
      edges: { node: { last_game_id: number } }[];
    };
  }>(STATS_QUERY, { address });

  const lastGameId =
    statsData.clicknripPlayerStatsModels.edges[0]?.node.last_game_id ?? 0;
  if (!lastGameId) return null;

  const gameData = await toriiQuery<{
    clicknripGameModels: {
      edges: {
        node: {
          id: number;
          status: string;
          level: number;
          stake: string;
        };
      }[];
    };
  }>(GAME_QUERY, { gameId: lastGameId });

  const gameNode = gameData.clicknripGameModels.edges[0]?.node;
  if (!gameNode) return null;

  const game: ActiveGame = {
    id: gameNode.id,
    level: gameNode.level,
    status: gameNode.status as GameStatus,
    stake: BigInt(gameNode.stake),
  };

  return game.status === "Active" ? game : null;
}

// death_tile is not in the Game entity; fetched async from GuessResolved event
const GUESS_RESOLVED_QUERY = `
  query GetGuessResolved($address: String!, $gameId: Int!) {
    clicknripGuessResolvedModels(where: { playerEQ: $address, idEQ: $gameId }) {
      edges { node { death_tile survived level } }
    }
  }
`;

export async function fetchLatestGuessResolved(
  address: string,
  gameId: number,
): Promise<{ deathTile: number; survived: boolean; level: number } | null> {
  try {
    const data = await toriiQuery<{
      clicknripGuessResolvedModels: {
        edges: {
          node: { death_tile: number; survived: boolean; level: number };
        }[];
      };
    }>(GUESS_RESOLVED_QUERY, { address, gameId });
    const edges = data.clicknripGuessResolvedModels.edges;
    if (!edges.length) return null;
    const node = edges[edges.length - 1].node;
    return {
      deathTile: node.death_tile,
      survived: node.survived,
      level: node.level,
    };
  } catch {
    return null;
  }
}
