# UNIRAE V2.22 static frontend deployment

Deploy the `vercel/` directory as the static frontend. This package does not host the API, PostgreSQL database, indexers, EVM contracts or DEX migration services; deploy those separately.

## Network mode

The UI defaults to testnet. To select mainnet, inject a reviewed configuration object **before the app's inline integration script** in `index.html`:

```html
<script>
window.UNIRAE_CONFIG = {
  environment: 'mainnet',
  apiBase: 'https://YOUR-API-HOST',
  v11Factories: {
    Ethereum: '0xREVIEWED_FACTORY_ADDRESS',
    'BNB Chain': '0xREVIEWED_FACTORY_ADDRESS',
    'Robinhood Chain': '0xREVIEWED_FACTORY_ADDRESS',
    'X Layer': '0xREVIEWED_FACTORY_ADDRESS'
  },
  nativeUsdFeeds: {
    Ethereum: '0xVERIFIED_CHAINLINK_FEED',
    'BNB Chain': '0xVERIFIED_CHAINLINK_FEED',
    'Robinhood Chain': '0xVERIFIED_CHAINLINK_FEED',
    'X Layer': '0xVERIFIED_CHAINLINK_FEED'
  }
};
</script>
```

Replace every placeholder with independently verified addresses for the target chain. Do not reuse addresses across chains unless the deployment is actually identical and verified. The app deliberately blocks launches if factory settings, platform recipient, oracle feed or fee parameters do not match its safety checks.

## Production blockers

A frontend deployment is not a production launch. The backend, database, indexers, contracts, fee vault, buyback executor, router, LP locker and migration coordinator must be deployed and verified independently. Run the complete release gate and independent audit before accepting mainnet transactions.
