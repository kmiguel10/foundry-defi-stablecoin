1. (Anchored Stability) Anchored or Pegged to $1.00
    a. Chainlink Price feed
    b. Set a function to exchange ETH & BTC -> $$$
2. Stability Mechanism (Minting) : Algorithmic (Decentralized)
    a. People can only mint stablecoins with enough collateral (coded)
3. Collateral: Exogenous (Cryto)
    a. wETH (ERC20 version)
    b. wBTC (ERC20 version)


1. What are our invariant/properties?
- Fuzz testing (invariant) video
- Invariants are properties of the system that should always hold (remain constant/unchanged)

What are stateless and stateful fuzzing tests?
- Stateless fuzzing is when the next test discards the properties of the last test, starting a new test. Stateful test is when the final state of the previous run is the starting state of the next run.

Foundry Fuzzing = stateless fuzzing
Foundry invariant = stateful fuzzing
