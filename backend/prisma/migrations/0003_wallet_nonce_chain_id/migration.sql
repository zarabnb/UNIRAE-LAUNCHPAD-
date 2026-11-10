-- Chain-bind new wallet challenges. Existing unused challenges are invalidated.
DELETE FROM "WalletNonce";
ALTER TABLE "WalletNonce" ADD COLUMN "chainId" INTEGER NOT NULL DEFAULT 97;
ALTER TABLE "WalletNonce" ALTER COLUMN "chainId" DROP DEFAULT;
CREATE INDEX "WalletNonce_chainId_expiresAt_idx" ON "WalletNonce"("chainId", "expiresAt");
