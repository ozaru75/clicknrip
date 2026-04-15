// Pool liquidity seeding script
//
// Transfers STRK directly to the pool contract so get_liquidity() returns a non-zero value
// pool.deposit() requires OPERATOR_ROLE (held only by Actions), so a direct ERC20 transfer
// is the correct way to seed liquidity. get_liquidity() = balance_of(pool) - locked_funds
// - team_unclaimed, so the transfer is counted immediately
//
// Usage: node scripts/fund_pool.mjs <dev> <amount>

import { execSync } from "child_process";
import { readFileSync } from "fs";
import { resolve } from "path";

// CLI

const PROFILES = ["dev"];
const root = new URL("..", import.meta.url).pathname;
const profile = process.argv[2];

const amountArg = process.argv[3];

if (!PROFILES.includes(profile) || !amountArg) {
  console.error(`Usage: node fund_pool.mjs <${PROFILES.join("|")}> <amount>`);
  console.error(`  amount: token units, e.g. 10 = 10 STRK`);
  process.exit(1);
}

const amountWei = (BigInt(amountArg) * 10n ** 18n).toString();

// Network config

const CONFIG = {
  dev: {
    token_address:
      "0x4718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d",
    sncast_profile: "dev-admin",
  },
};

// Manifest parsing

const cfg = CONFIG[profile];
const manifest = JSON.parse(
  readFileSync(resolve(root, `manifest_${profile}.json`), "utf8"),
);

const poolContract = manifest.external_contracts?.find((c) =>
  (c.tag ?? c.contract_name)?.includes("pool"),
);
if (!poolContract) throw new Error("pool not found in manifest");

const pool = poolContract.address;

// Transfer

const invoke = (label, fn, contract, calldata) => {
  const cmd = [
    "sncast",
    "--profile",
    cfg.sncast_profile,
    "invoke",
    "--contract-address",
    contract,
    "--function",
    fn,
    "--calldata",
    ...calldata,
  ].join(" ");

  console.log(`[${label}] ${cmd}`);
  try {
    const out = execSync(cmd, {
      cwd: root,
      encoding: "utf8",
      stdio: ["pipe", "pipe", "pipe"],
    });
    if (out) process.stdout.write(out);
  } catch (e) {
    if (e.stdout) process.stdout.write(e.stdout);
    if (e.stderr) process.stderr.write(e.stderr);
    throw new Error(`${label} failed`);
  }
};

console.log(`\npool:  ${pool}`);
console.log(`token: ${cfg.token_address}`);
console.log(`seeding ${amountArg} STRK (${amountWei} wei)\n`);

invoke("transfer STRK to pool", "transfer", cfg.token_address, [
  pool,
  amountWei,
  "0",
]);

console.log("\ndone");
