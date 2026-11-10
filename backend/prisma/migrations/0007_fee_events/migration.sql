CREATE TABLE "FeeEvent" (
  "id" TEXT NOT NULL,
  "chainId" INTEGER NOT NULL,
  "vaultAddress" TEXT NOT NULL,
  "tokenAddress" TEXT NOT NULL,
  "actor" TEXT,
  "eventName" TEXT NOT NULL,
  "amount" TEXT NOT NULL DEFAULT '0',
  "creatorAmount" TEXT NOT NULL DEFAULT '0',
  "buybackAmount" TEXT NOT NULL DEFAULT '0',
  "platformAmount" TEXT NOT NULL DEFAULT '0',
  "txHash" TEXT NOT NULL,
  "logIndex" INTEGER NOT NULL,
  "blockNumber" BIGINT NOT NULL,
  "blockHash" TEXT NOT NULL,
  "timestamp" TIMESTAMP(3),
  "payload" JSONB NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "FeeEvent_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "FeeEvent_chainId_fkey" FOREIGN KEY ("chainId") REFERENCES "Chain"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "FeeEvent_chainId_txHash_logIndex_key" ON "FeeEvent"("chainId", "txHash", "logIndex");
CREATE INDEX "FeeEvent_chainId_tokenAddress_blockNumber_idx" ON "FeeEvent"("chainId", "tokenAddress", "blockNumber");
CREATE INDEX "FeeEvent_chainId_vaultAddress_blockNumber_idx" ON "FeeEvent"("chainId", "vaultAddress", "blockNumber");
