# SalaryEWA – Earned Wage Access Payroll Contract

## Overview

SalaryEWA is a payroll smart contract that enables **Earned Wage Access (EWA)** on top of a standard monthly salary.  
Employers deposit ERC-20 tokens into the contract, employees accrue salary linearly over time, and can:

- Request an **advance** (up to 50% of their earned salary) once per pay period.
- Withdraw the remaining salary on or after payday.
- Be deactivated / reactivated by the employer when needed.

This repository uses:

- **Solidity** ^0.8.20
- **Foundry** (forge/cast) for build, test and deploy
- **OpenZeppelin Contracts v5** for Ownable, ReentrancyGuard, Pausable and SafeERC20
- **Edu Chain Testnet** as target network
- **PhiiCoin (PHII)** as example ERC-20 salary token

---

## Contracts

### 1. `PhiiCoin.sol`

Simple ERC-20 token used as the salary currency.

Key points:

- Inherits `ERC20` from OpenZeppelin.
- Mints a fixed initial supply to the deployer.
- 18 decimals.

```solidity
contract PhiiCoin is ERC20 {
    constructor(uint256 initialSupply) ERC20("Phii Coin", "PHII") {
        _mint(msg.sender, initialSupply);
    }
}
````

You can replace `PhiiCoin` with any other ERC-20 token on EduChain Testnet.

---

### 2. `SalaryEWA.sol`

Core EWA payroll contract.

```solidity
contract SalaryEWA is Ownable(msg.sender), Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant PAY_PERIOD = 30 days;
    IERC20 public immutable SALARY_TOKEN;

    struct Employee {
        uint256 monthlySalary;
        uint256 employmentStart;
        uint256 lastUpdate;
        uint256 accrued;
        uint256 withdrawn;
        uint256 refunded;
        uint256 lastAdvancePeriod;
        bool active;
        bool exists;
    }

    mapping(address => Employee) private employees;
}
```

#### Roles & Access Control

* `owner` (employer) is set in the constructor via `Ownable(msg.sender)`.
* `onlyEmployer` modifier gates admin functions:

  * `registerEmployee`, `updateEmployeeSalary`
  * `deactivateEmployee`, `reactivateEmployee`
  * `fund`, `refundEmployee`, `releaseSalary`
  * `pause`, `unpause`
* `onlyEmployee` / `onlyActiveEmployee` restrict employee actions:

  * `requestAdvance`
  * `withdraw`

#### Payroll Logic

* Salary accrues linearly per second based on `monthlySalary` and a `PAY_PERIOD` of 30 days.
* Accrual state is stored per employee:

  * `accrued` – total earned so far
  * `withdrawn` – total already paid out (including advances)
  * `refunded` – total deducted and sent back to the employer

Accrual is updated through `_updateAccrual(Employee storage emp)` before any operation that depends on the current balance.

#### Main Functions

##### Employer (Admin) Functions

* `registerEmployee(address employee, uint256 monthlySalary)`

  Registers a new employee with a monthly salary and initializes their accrual state.
  Only callable by the employer when not paused.

* `updateEmployeeSalary(address employee, uint256 newMonthlySalary)`

  Updates an employee’s monthly salary after first updating their current accrual.

* `deactivateEmployee(address employee)` / `reactivateEmployee(address employee)`

  Soft disable / enable an employee. Deactivated employees cannot request new advances but can still withdraw what they have already earned.

* `fund(uint256 amount)`

  Employer deposits salary tokens into the contract using `SafeERC20.safeTransferFrom`.
  Employer must approve the contract on the salary token beforehand.

* `releaseSalary(address employee)`

  Employer-triggered payout of all withdrawable salary for a given employee.

* `refundEmployee(address employee, uint256 amount)`

  Reduces the employee’s withdrawable balance and sends tokens back to the employer.
  The amount is tracked in the employee’s `refunded` field.

* `pause()` / `unpause()`

  Emergency stop for all critical state-changing functions (funding, advances, withdrawals, refunds, etc).

##### Employee Functions

* `requestAdvance(uint256 amount)`

  * Only for active employees.
  * Updates accrual.
  * Computes current pay period index from `employmentStart`.
  * Allows at most **one advance per period**:

    ```solidity
    require(emp.lastAdvancePeriod < periodIndex, "Already advanced");
    ```
  * Limits advance to **50% of withdrawable**:

    ```solidity
    uint256 withdrawableAmount = _withdrawable(emp);
    uint256 maxAdvance = withdrawableAmount / 2;
    require(amount <= maxAdvance, "Exceeds 50%");
    ```
  * Transfers tokens using `SafeERC20.safeTransfer` and updates `withdrawn`.

* `withdraw()`

  * For any employee (active or not).
  * Updates accrual and transfers all remaining withdrawable salary.

##### View & Helper Functions

* `previewWithdrawable(address employee) external view returns (uint256)`

  Returns the current withdrawable amount for a given employee, simulating accrual up to the current block timestamp.

* `isEmployee(address employee)` and `isActiveEmployee(address employee)`

  Helper functions for UI / off-chain services.

---

## Accounting Model

For each employee, the contract maintains:

* `monthlySalary` – agreed monthly amount
* `accrued` – total earned over time (linear)
* `withdrawn` – what has already been paid out (including advances)
* `refunded` – what has been removed and sent back to the employer
* `withdrawable = max(accrued - withdrawn - refunded, 0)`

The contract itself holds the actual ERC-20 balance (funded by the employer via `fund()`).

---

## Security

* Uses Solidity `^0.8.20` → built-in overflow and underflow checks.
* Uses OpenZeppelin:

  * `Ownable` – admin role / employer.
  * `Pausable` – emergency stop switch.
  * `ReentrancyGuard` – protects all functions that transfer tokens.
  * `SafeERC20` – safe calls to ERC-20 tokens.
* Validates inputs:

  * Non-zero addresses.
  * Amounts must be strictly greater than zero.
* Emits events for all major state changes, making the contract easy to index and monitor.

---

## Foundry Commands

Compile:

```bash
forge build
```

Run tests:

```bash
forge test
```

Deploy to EduChain Testnet (example):

```bash
export PRIVATE_KEY=0xYOUR_PRIVATE_KEY

forge script script/Deploy.s.sol:DeploySalaryEWAAll \
  --rpc-url educhain \
  --broadcast
```