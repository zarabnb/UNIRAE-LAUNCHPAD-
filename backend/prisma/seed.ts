import 'dotenv/config';
import { PrismaClient } from '@prisma/client';
const db = new PrismaClient();
const chains = [
  { id: 1, slug: 'ethereum-mainnet', name: 'Ethereum' },
  { id: 56, slug: 'bnb-mainnet', name: 'BNB Smart Chain' },
  { id: 4663, slug: 'robinhood-mainnet', name: 'Robinhood Chain' },
  { id: 196, slug: 'xlayer-mainnet', name: 'X Layer' },
  { id: 97, slug: 'bnb-testnet', name: 'BNB Chain Testnet' },
  { id: 11155111, slug: 'sepolia', name: 'Ethereum Sepolia' },
  { id: 46630, slug: 'robinhood-testnet', name: 'Robinhood Chain Testnet' },
  { id: 1952, slug: 'xlayer-testnet', name: 'X Layer Testnet' },
];
for (const chain of chains) {
  await db.chain.upsert({ where: { id: chain.id }, create: chain, update: chain });
}
console.log(`Seeded ${chains.length} UNIRAE EVM network records.`);
await db.$disconnect();
