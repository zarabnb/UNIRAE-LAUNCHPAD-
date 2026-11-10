ALTER TABLE "Token" ADD COLUMN "curveAddress" TEXT;
CREATE INDEX "Token_chainId_curveAddress_idx" ON "Token"("chainId", "curveAddress");
