# Token Launchpad

## Contents

- [Purpose](#purpose)
- [Architecture](#architecture)
- [Sale State](#sale-state)
- [Access Control](#access-control)
- [Purchase Accounting](#purchase-accounting)
- [Time Window](#time-window)
- [Safety Checks](#safety-checks)
- [Foundry Proof](#foundry-proof)
- [Development](#development)

## Purpose

The Token Launchpad provides a controlled ERC-20 token-sale mechanism. A
sale creator configures the sale terms, buyers purchase tokens during a
defined window, buyers claim purchased tokens after the sale, and
proceeds can only be withdrawn after the sale ends.

## Architecture

```text
                    Token Launchpad
                          |
             +------------+------------+
             |                         |
        Sale Creator                 Buyers
             |                         |
      Creates sale                Purchase tokens
      Funds allocation            Track allocation
             |                         |
             +------------+------------+
                          |
                     Sale ends
                          |
              +-----------+-----------+
              |                       |
         Buyers claim          Owner withdraws
           tokens                 proceeds
                                      |
                              Recover unsold tokens
```

The launchpad is non-minting. The sale tokens already exist and are
transferred into the launchpad when the sale is created.

## Sale State

Each sale stores information such as:

- creator
- ERC-20 token
- token price
- token allocation
- start time
- end time
- hard cap
- per-wallet limit
- total tokens sold
- total proceeds
- buyer purchase information

The implementation uses a sale ID so multiple independent sales can be
managed by the same contract.

## Access Control

The deployer becomes the immutable contract owner.

```solidity
address public immutable owner;
```

Administrative actions such as sale creation, proceeds withdrawal, and
unsold-token recovery are restricted to the owner.

Ownership transfer was intentionally omitted to keep the access model
small and explicit.

## Purchase Accounting

The price represents the amount of wei required for one whole 18-decimal
token.

For example:

```text
Price = 0.001 ETH

0.001 ETH -> 1 token
0.010 ETH -> 10 tokens
1 ETH     -> 1000 tokens
```

Exact payment is enforced by checking that `msg.value` divides evenly by
the configured token price.

```solidity
if (msg.value % sale.price != 0) {
    revert IncorrectPayment();
}
```

The purchased token amount is then:

```text
(msg.value / price) * 1e18
```

This prevents ambiguous fractional purchases.

## Time Window

The active sale interval is:

```text
[startTime, endTime)
```

A purchase at exactly `startTime` is valid, while a purchase at exactly
`endTime` is rejected.

Claims, withdrawals, and unsold-token recovery become available once the
sale has ended.

## Safety Checks

Purchases enforce:

- active sale window
- correct payment
- hard cap
- per-wallet limit
- remaining token allocation

Buyer allocations are stored rather than transferring sale tokens
immediately. This separates the purchase phase from the claim phase.

## Foundry Proof

The test suite verifies:

- sale time windows
- multiple buyers
- hard-cap enforcement
- wallet limits
- post-sale claims
- unauthorized withdrawals

## Development

### Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/DeployTokenLaunchpad.s.sol:DeployTokenLaunchpad --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
