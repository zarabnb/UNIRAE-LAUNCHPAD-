CREATE TABLE "WalletNonce" (
  "id" TEXT NOT NULL,
  "address" TEXT NOT NULL,
  "nonce" TEXT NOT NULL,
  "domain" TEXT NOT NULL,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "usedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "WalletNonce_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "WalletNonce_nonce_key" ON "WalletNonce"("nonce");
CREATE INDEX "WalletNonce_address_expiresAt_idx" ON "WalletNonce"("address", "expiresAt");
