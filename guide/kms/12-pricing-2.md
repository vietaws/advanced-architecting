## Cost Calculation

### Your Scenario

Key usage: 20 minutes
Deletion waiting period: 7 days

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Breakdown

### 1. Active Usage (20 minutes)

20 minutes = 20/60 hours = 0.333 hours

Cost: 0.333 hours × $0.00137/hour = $0.00046


### 2. Deletion Waiting Period (7 days)

7 days = 7 × 24 hours = 168 hours

Cost: 168 hours × $0.00137/hour = $0.23


### Total Cost

Active usage:     $0.00046
Deletion period:  $0.23
─────────────────────────
Total:            $0.23046

Rounded: $0.23


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Timeline

Day 1, 10:00 AM - Create key
├── Billing starts: $0.00137/hour
│
Day 1, 10:20 AM - Schedule deletion (20 minutes later)
├── Key state: PendingDeletion
├── Billing continues: $0.00137/hour
├── Cost so far: $0.00046
│
Day 8, 10:20 AM - Key deleted (7 days later)
├── Billing stops
└── Total cost: $0.23


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Key Point

You pay for the ENTIRE deletion waiting period!

Even though you only "used" the key for 20 minutes, you're charged for:
- 20 minutes of active use
- 7 days of waiting for deletion

Total: $0.23

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## To Minimize Cost

If you want to minimize charges, use the minimum deletion waiting period (7 days):

bash
# Minimum waiting period
aws kms schedule-key-deletion \
  --key-id KEY-ID \
  --pending-window-in-days 7

# Cost: 7 days = $0.23


vs

bash
# Maximum waiting period
aws kms schedule-key-deletion \
  --key-id KEY-ID \
  --pending-window-in-days 30

# Cost: 30 days = $0.90


Savings: $0.67 by using 7 days instead of 30 days