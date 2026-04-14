import { defineConfig, loadEnv } from "vite";
import solid from "vite-plugin-solid";
import { resolve } from "node:path";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "VITE_");
  const isDevnet = env.VITE_NETWORK === "devnet";

  return {
    plugins: [solid()],
    resolve: {
      alias: [
        // Network-specific wallet provider resolved first (exact match)
        {
          find: "@/providers/wallet",
          replacement: resolve(
            __dirname,
            isDevnet
              ? "src/providers/wallet/WalletProvider.dev.tsx"
              : "src/providers/wallet/WalletProvider.prod.tsx",
          ),
        },
        // Regex required: Vite 8 dev server only exact-matches string aliases;
        // regex aliases use .replace() which correctly handles prefix substitution
        { find: /^@\//, replacement: resolve(__dirname, "src") + "/" },
      ],
    },
  };
});
