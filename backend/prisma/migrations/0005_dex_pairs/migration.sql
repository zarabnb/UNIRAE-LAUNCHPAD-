CREATE TABLE "DexPair" (
  "id" TEXT NOT NULL,
  "chainId" INTEGER NOT NULL,
  "tokenId" TEXT NOT NULL,
  "pairAddress" TEXT NOT NULL,
  "quoteToken" TEXT NOT NULL,
  "migrationTxHash" TEXT NOT NULL,
  "migrationBlock" BIGINT NOT NULL,
  "migrationLogIndex" INTEGER NOT NULL,
  "blockHash" TEXT NOT NULL,
  "dex" TEXT NOT NULL DEFAULT 'uniswap-v2-compatible',
  "active" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "DexPair_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "DexPair_chainId_fkey" FOREIGN KEY ("chainId") REFERENCES "Chain"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "DexPair_tokenId_fkey" FOREIGN KEY ("tokenId") REFERENCES "Token"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "DexPair_chainId_pairAddress_key" ON "DexPair"("chainId", "pairAddress");
CREATE UNIQUE INDEX "DexPair_chainId_migrationTxHash_migrationLogIndex_key" ON "DexPair"("chainId", "migrationTxHash", "migrationLogIndex");
CREATE INDEX "DexPair_chainId_tokenId_active_idx" ON "DexPair"("chainId", "tokenId", "active");
