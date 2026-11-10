CREATE TABLE "DexPool" (
  "id" TEXT NOT NULL,
  "chainId" INTEGER NOT NULL,
  "tokenId" TEXT NOT NULL,
  "poolAddress" TEXT NOT NULL,
  "quoteToken" TEXT NOT NULL,
  "startBlock" BIGINT NOT NULL,
  "feeTier" INTEGER NOT NULL,
  "dex" TEXT NOT NULL DEFAULT 'uniswap-v3',
  "active" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "DexPool_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "DexPool_chainId_poolAddress_key" ON "DexPool"("chainId", "poolAddress");
CREATE INDEX "DexPool_chainId_tokenId_active_idx" ON "DexPool"("chainId", "tokenId", "active");
ALTER TABLE "DexPool" ADD CONSTRAINT "DexPool_chainId_fkey" FOREIGN KEY ("chainId") REFERENCES "Chain"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "DexPool" ADD CONSTRAINT "DexPool_tokenId_fkey" FOREIGN KEY ("tokenId") REFERENCES "Token"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
