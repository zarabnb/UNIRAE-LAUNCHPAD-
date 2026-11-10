import { parseAbi } from 'viem';

// These signatures are copied from the V1.1 Solidity sources shipped in /contracts.
// Re-check against the deployed artifact before enabling a production indexer.
export const factoryEvents = parseAbi([
  'event TokenLaunched(address indexed token, address indexed curve, address indexed creator, string name, string symbol, uint256 supply)',
]);
export const curveEvents = parseAbi([
  'event Initialized(address indexed token, uint256 curveInventory)',
  'event Bought(address indexed buyer, uint256 tokenAmount, uint256 curveCost, uint256 fee)',
  'event Sold(address indexed seller, uint256 tokenAmount, uint256 grossNative, uint256 fee, uint256 netNative)',
  'event Graduated(uint256 marketCapUsdE8, uint256 timestamp)',
  'event MigrationCoordinatorConfigured(address indexed coordinator)',
  'event GraduationMigrated(address indexed coordinator, uint256 nativeAmount, uint256 tokenAmount)',
]);
export const tokenEvents = parseAbi([
  'event Transfer(address indexed from, address indexed to, uint256 value)',
  'event TaxCollected(address indexed from, address indexed to, uint256 tax, uint256 creatorAmount, uint256 burned)',
]);
