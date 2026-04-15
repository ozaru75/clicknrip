import { config } from "@/config";
import type { ActiveGame, GameStatus } from "./game";

async function toriiQuery<T>(
  query: string,
  variables: Record<string, unknown>
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

// Step 1: Get last_game_id from PlayerStats
const STATS_QUERY = `
  query GetPlayerStats($address: String!) {
    clicknripPlayerStatsModels(where: { playerEQ: $address }) {
      edges { node { last_game_id } }
    }
  }
`;

// Step 2: Get game details by id
// Game model is keyed by id (felt252)
const GAME_QUERY = `
  query GetGame($gameId: Int!) {
    clicknripGameModels(where: { idEQ: $gameId }) {
      edges { node { id status level } }
    }
  }
`;

export async function fetchActiveGame(address: string): Promise<ActiveGame | null> {
  try {
    // Step 1: Get last_game_id
    const statsData = await toriiQuery<{
      clicknripPlayerStatsModels: {
        edges: { node: { last_game_id: number } }[];
      };
    }>(STATS_QUERY, { address });

    const statsEdges = statsData.clicknripPlayerStatsModels.edges;
    const lastGameId = statsEdges[0]?.node.last_game_id ?? 0;

    // u32 default 0 = no game yet
    if (!lastGameId) {
      return null;
    }

    // Step 2: Get game by id
    const gameData = await toriiQuery<{
      clicknripGameModels: {
        edges: { node: { id: number; status: string; level: number } }[];
      };
    }>(GAME_QUERY, { gameId: lastGameId });

    const gameEdges = gameData.clicknripGameModels.edges;
    const gameNode = gameEdges[0]?.node;

    if (!gameNode) {
      return null;
    }

    const game: ActiveGame = {
      id: gameNode.id,
      level: gameNode.level,
      status: gameNode.status as GameStatus,
    };

    // Return only active games
    return game.status === "Active" ? game : null;
  } catch (error) {
    console.error("fetchActiveGame error:", error);
    throw error;
  }
}
