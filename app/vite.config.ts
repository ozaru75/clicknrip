import { defineConfig, loadEnv } from "vite";
import solid from "vite-plugin-solid";
import { resolve } from "node:path";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "VITE_");
  const isDevnet = env.VITE_NETWORK === "devnet";

  return {
    plugins: [solid()],
    resolve: {
      alias: {
        "@/providers/wallet": resolve(
          __dirname,
          isDevnet
            ? "src/providers/wallet/WalletProvider.dev.tsx"
            : "src/providers/wallet/WalletProvider.prod.tsx",
        ),
      },
    },
  };
});
