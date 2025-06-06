# Module pictor_network

## Overview

The `pictor_network` module provides a decentralized job/task management system with the following features:

- **User Registration:** Users can register and manage their balances and credits.
- **Worker Registration:** Operators can register workers, who can then be assigned tasks.
- **Job and Task Management:** Operators can create jobs, add tasks, and assign them to workers.
- **Deposits and Withdrawals:** Users can deposit and withdraw supported coins.
- **Payment Handling:** Payments for tasks are managed and distributed upon job completion.
- **Operator and Admin Controls:** Access control is enforced for sensitive operations.

## Key Structures

- `UserInfo`: Stores user balance and credit.
- `Worker`: Represents a worker, including owner and stake.
- `Task`: Represents a task assigned to a worker.
- `Job`: Represents a job with multiple tasks.
- `GlobalData`: The main shared object holding all users, workers, jobs, and the coin vault.

## Main Functions (pictor_network)

- `init`: Initializes the `GlobalData` shared object.
- `set_coin_type`: Admin function to add a new supported coin type.
- `deposit_coin` / `withdraw_coin`: User functions to deposit or withdraw coins.
- `register_user`: Registers a new user.
- `op_register_worker`: Operator function to register a new worker.
- `op_create_job`: Operator function to create a new job.
- `op_add_task`: Operator function to add a task to a job.
- `op_complete_job`: Operator function to mark a job as completed and distribute payments.
- `op_credit_user`: Operator function to credit a user's account.

## Error Codes (pictor_network)

- `ESystemPaused`: The system is paused.
- `EUnAuthorized`: Unauthorized operation.
- `EUserNotRegistered`: User not registered.
- `EWorkerRegistered`: Worker already registered.
- `EWorkerNotRegistered`: Worker not registered.
- `EJobRegistered`: Job already registered.
- `EJobNotRegistered`: Job not registered.
- `EJobCompleted`: Job already completed.
- `EInsufficentBalance`: Insufficient balance.
- `ERecordExists`: Record already exists.

# Module pictor_manage 

The `pictor_manage` module provides role-based access control and network configuration for the Pictor Network.

## Key Structures

- `Auth`: Stores network configuration, role assignments, treasury address, pause state, and worker earning percentage.
- `AdminCap`, `OperatorCap`, `PauserCap`: Capability structs for admin, operator, and pauser roles.
- `RoleKey<phantom C>`: Used for dynamic role assignment in the `Bag`.

## Main Functions

- `init`: Initializes the `Auth` shared object and assigns admin and operator roles to the creator.
- `add_capability`, `remove_capability`: Admin-only functions to add or remove capabilities for users.
- `add_operator`, `remove_operator`: Admin-only functions to manage operator roles.
- `is_admin`, `is_operator`: Check if an address has admin or operator capability.
- `set_worker_earning_percentage`: Admin-only function to set the worker earning percentage.
- `set_treasury_address`: Admin-only function to set the treasury address.
- `set_pause_status`: Admin-only function to pause or unpause the network.
- `get_paused_status`, `get_treasury_address`, `calculate_worker_payment`: Utility functions for network state and calculations.

## Error Codes

- `EUnAuthorized`: Unauthorized operation.
- `ERecordExists`: Capability already exists.
- `ENoAuthRecord`: Capability does not exist.

## Deployment

1. Build and publish the module to the Sui blockchain.
2. Call the `init` function in both `pictor_manage` and `pictor_network` to create and share the `Auth` and `GlobalData` objects.
3. Call the `set_coin_type` function to register a coin type.
4. Call the `add_operator` to setup operators. 

## Testing

```
sui move test
```
