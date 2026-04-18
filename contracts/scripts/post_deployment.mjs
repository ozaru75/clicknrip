// Post-deployment setup script
//
// Run after `scarb run migrate-dev/sepolia/mainnet` to wire up the deployed contracts:
//   1. Grant OPERATOR_ROLE on Pool to Actions (allows Actions to lock/unlock reserves and payout)
//   2. Call update_config on Actions to set game parameters and contract addresses
//
// Usage: node scripts/post_deployment.mjs <dev|sepolia|mainnet>

import { execSync } from "child_process";
import { readFileSync } from "fs";
import { resolve } from "path";

// CLI

const PROFILES = ["dev", "sepolia", "mainnet"];
const root = new URL("..", import.meta.url).pathname;
const profile = process.argv[2];

if (!PROFILES.includes(profile)) {
  console.error(`Usage: node post_deployment.mjs <${PROFILES.join("|")}>`);
  process.exit(1);
}

// Network config

const CONFIG = {
  dev: {
    token_address:
      "0x4718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d",
    min_stake: "2000000000000000000", // 2 STRK
    team_fee_bps: "100", // 1%
    max_stake_bps: "1000", // 10% of pool
    sncast_profile: "dev-admin",
  },
  sepolia: {
    token_address: "",
    vrf_provider_address: "",
    min_stake: "",
    team_fee_bps: "",
    max_stake_bps: "",
    sncast_profile: "",
  },
  mainnet: {
    token_address: "",
    vrf_provider_address: "",
    min_stake: "",
    team_fee_bps: "",
    max_stake_bps: "",
    sncast_profile: "",
  },
};

// Manifest parsing

const cfg = CONFIG[profile];
const manifest = JSON.parse(
  readFileSync(resolve(root, `manifest_${profile}.json`), "utf8"),
);

const findContract = (list, name) =>
  list.find((c) => (c.tag ?? c.contract_name)?.includes(name));

const actionsContract = findContract(manifest.contracts, "actions");
const poolContract = findContract(manifest.external_contracts, "pool");
const mockVrngContract = findContract(manifest.external_contracts, "mock_vrng");
if (!actionsContract) throw new Error("actions not found in manifest");
if (!poolContract) throw new Error("pool not found in manifest");

const actions = actionsContract.address;
const pool = poolContract.address;
const vrngAddress = mockVrngContract?.address ?? cfg.vrf_provider_address;

// On-chain setup

// starknet_keccak("OPERATOR_ROLE"), matches selector!("OPERATOR_ROLE") in roles.cairo
const OPERATOR_ROLE =
  "0x3667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929";

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

console.log(`\nvrng: ${vrngAddress}`);
console.log(`pool: ${pool}`);
console.log(`actions: ${actions}\n`);

// Step 1: grant Actions the OPERATOR_ROLE on Pool so it can call
// lock_reserve, unlock_reserve, accrue_fee, payout, and deposit
invoke("grant OPERATOR_ROLE on Pool to Actions", "grant_role", pool, [
  OPERATOR_ROLE,
  actions,
]);

// Step 2: set game parameters and wire pool/vrng addresses into Actions config
// min_stake is u256 (low, high) -- high is always 0
invoke("update_config on Actions", "update_config", actions, [
  cfg.min_stake,
  "0",
  cfg.team_fee_bps,
  cfg.max_stake_bps,
  pool,
  vrngAddress,
]);

console.log("\ndone");
