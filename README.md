┌─────────────────────────────────────────────────────────────────┐
│ USER INITIATES SWAP │
├─────────────────────────────────────────────────────────────────┤
│ │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ STEP 1: \_beforeSwap() fires │ │
│ │ │ │
│ │ Inputs available: │ │
│ │ • tx.gasprice (what swapper is paying) │ │
│ │ • movingAverageGasPrice (historical average) │ │
│ │ │ │
│ │ TODO (not implemented yet): │ │
│ │ • Compare current vs average │ │
│ │ • Calculate dynamic fee │ │
│ │ • Return fee in the uint24 slot ──────────────────┐ │ │
│ └──────────────────────────────────────────────────────│────┘ │
│ │ │
│ ┌──────────────────────────────────────────────────────▼────┐ │
│ │ STEP 2: Swap Executes │ │
│ │ │ │
│ │ PoolManager uses the fee we returned to calculate │ │
│ │ how much the swapper pays to LPs │ │
│ └───────────────────────────────────────────────────────────┘ │
│ │
│ ┌───────────────────────────────────────────────────────────┐ │
│ │ STEP 3: \_afterSwap() fires │ │
│ │ │ │
│ │ • Calls updateMovingAverage() │ │
│ │ • Adds this tx's gas price to the running average │ │
│ │ • Increments count │ │
│ │ │ │
│ │ This prepares us for the NEXT swap's fee calculation │ │
│ └───────────────────────────────────────────────────────────┘ │
│ │
└─────────────────────────────────────────────────────────────────┘
