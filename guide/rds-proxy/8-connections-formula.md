## RDS Maximum Connections by Engine

### PostgreSQL

Formula:
max_connections = (DBInstanceClassMemory / 9531392) - 1


| Instance Class | Memory (GB) | Max Connections |
|----------------|-------------|-----------------|
| db.t3.micro | 1 | 87 |
| db.t3.small | 2 | 177 |
| db.t3.medium | 4 | 367 |
| db.t3.large | 8 | 747 |
| db.t4g.micro | 1 | 87 |
| db.t4g.small | 2 | 177 |
| db.t4g.medium | 4 | 367 |
| db.m5.large | 8 | 901 |
| db.m5.xlarge | 16 | 1,802 |
| db.m5.2xlarge | 32 | 3,604 |
| db.m5.4xlarge | 64 | 7,209 |
| db.r5.large | 16 | 1,600 |
| db.r5.xlarge | 32 | 3,200 |
| db.r5.2xlarge | 64 | 6,400 |
| db.r5.4xlarge | 128 | 12,800 |

Check current value:
sql
SHOW max_connections;


Modify (via parameter group):
bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name my-pg-params \
  --parameters "ParameterName=max_connections,ParameterValue=500,ApplyMethod=pending-reboot"


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### MySQL

Formula:
max_connections = (DBInstanceClassMemory / 12582880)


| Instance Class | Memory (GB) | Max Connections |
|----------------|-------------|-----------------|
| db.t3.micro | 1 | 83 |
| db.t3.small | 2 | 166 |
| db.t3.medium | 4 | 332 |
| db.t3.large | 8 | 664 |
| db.t4g.micro | 1 | 83 |
| db.t4g.small | 2 | 166 |
| db.t4g.medium | 4 | 332 |
| db.m5.large | 8 | 664 |
| db.m5.xlarge | 16 | 1,329 |
| db.m5.2xlarge | 32 | 2,658 |
| db.m5.4xlarge | 64 | 5,316 |
| db.r5.large | 16 | 1,329 |
| db.r5.xlarge | 32 | 2,658 |
| db.r5.2xlarge | 64 | 5,316 |
| db.r5.4xlarge | 128 | 10,633 |

Check current value:
sql
SHOW VARIABLES LIKE 'max_connections';


Modify:
bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name my-mysql-params \
  --parameters "ParameterName=max_connections,ParameterValue=1000,ApplyMethod=immediate"


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### MariaDB

Formula: Same as MySQL
max_connections = (DBInstanceClassMemory / 12582880)


| Instance Class | Memory (GB) | Max Connections |
|----------------|-------------|-----------------|
| db.t3.micro | 1 | 83 |
| db.t3.small | 2 | 166 |
| db.t3.medium | 4 | 332 |
| db.m5.large | 8 | 664 |
| db.m5.xlarge | 16 | 1,329 |
| db.r5.large | 16 | 1,329 |
| db.r5.xlarge | 32 | 2,658 |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Oracle

Default: Based on processes parameter

Formula:
processes = (DBInstanceClassMemory / 9868951) + 30
sessions = processes × 1.5


| Instance Class | Memory (GB) | Processes | Sessions (Max Connections) |
|----------------|-------------|-----------|----------------------------|
| db.t3.small | 2 | 240 | 360 |
| db.t3.medium | 4 | 435 | 652 |
| db.t3.large | 8 | 825 | 1,237 |
| db.m5.large | 8 | 825 | 1,237 |
| db.m5.xlarge | 16 | 1,645 | 2,467 |
| db.m5.2xlarge | 32 | 3,285 | 4,927 |
| db.r5.large | 16 | 1,645 | 2,467 |
| db.r5.xlarge | 32 | 3,285 | 4,927 |
| db.r5.2xlarge | 64 | 6,565 | 9,847 |

Check current value:
sql
SELECT name, value FROM v$parameter WHERE name IN ('processes', 'sessions');


Modify:
bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name my-oracle-params \
  --parameters "ParameterName=processes,ParameterValue=1000,ApplyMethod=pending-reboot"


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### SQL Server

Depends on edition and version

Default: 0 (unlimited, but limited by memory)

| Instance Class | Memory (GB) | Practical Max Connections |
|----------------|-------------|---------------------------|
| db.t3.small | 2 | ~200 |
| db.t3.medium | 4 | ~400 |
| db.t3.large | 8 | ~800 |
| db.m5.large | 8 | ~1,000 |
| db.m5.xlarge | 16 | ~2,000 |
| db.m5.2xlarge | 32 | ~4,000 |
| db.r5.large | 16 | ~2,000 |
| db.r5.xlarge | 32 | ~4,000 |
| db.r5.2xlarge | 64 | ~8,000 |

Check current value:
sql
SELECT @@MAX_CONNECTIONS;
-- Or
EXEC sp_configure 'user connections';


Note: SQL Server default is 0 (unlimited), actual limit depends on memory and workload.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Aurora PostgreSQL

Formula: Same as RDS PostgreSQL
max_connections = (DBInstanceClassMemory / 9531392) - 1


| Instance Class | Memory (GB) | Max Connections |
|----------------|-------------|-----------------|
| db.t3.medium | 4 | 367 |
| db.t3.large | 8 | 747 |
| db.t4g.medium | 4 | 367 |
| db.t4g.large | 8 | 747 |
| db.r5.large | 16 | 1,600 |
| db.r5.xlarge | 32 | 3,200 |
| db.r5.2xlarge | 64 | 6,400 |
| db.r5.4xlarge | 128 | 12,800 |
| db.r5.8xlarge | 256 | 25,600 |
| db.r5.12xlarge | 384 | 38,400 |
| db.r5.16xlarge | 512 | 51,200 |
| db.r6g.large | 16 | 1,600 |
| db.r6g.xlarge | 32 | 3,200 |
| db.r6g.2xlarge | 64 | 6,400 |

Check current value:
sql
SHOW max_connections;


Aurora Serverless v2:
- Connections scale with ACUs (Aurora Capacity Units)
- Formula: max_connections = (ACU × 9000000000 / 9531392) - 1
- Example: 2 ACU = ~1,888 connections

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Aurora MySQL

Formula: Same as RDS MySQL
max_connections = (DBInstanceClassMemory / 12582880)


| Instance Class | Memory (GB) | Max Connections |
|----------------|-------------|-----------------|
| db.t3.medium | 4 | 332 |
| db.t3.large | 8 | 664 |
| db.t4g.medium | 4 | 332 |
| db.t4g.large | 8 | 664 |
| db.r5.large | 16 | 1,329 |
| db.r5.xlarge | 32 | 2,658 |
| db.r5.2xlarge | 64 | 5,316 |
| db.r5.4xlarge | 128 | 10,633 |
| db.r5.8xlarge | 256 | 21,266 |
| db.r5.12xlarge | 384 | 31,899 |
| db.r5.16xlarge | 512 | 42,532 |
| db.r6g.large | 16 | 1,329 |
| db.r6g.xlarge | 32 | 2,658 |
| db.r6g.2xlarge | 64 | 5,316 |

Check current value:
sql
SHOW VARIABLES LIKE 'max_connections';


Aurora Serverless v2:
- Connections scale with ACUs
- Formula: max_connections = (ACU × 9000000000 / 12582880)
- Example: 2 ACU = ~1,430 connections

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Quick Reference Commands

### Check Max Connections

PostgreSQL / Aurora PostgreSQL:
sql
SHOW max_connections;
SELECT setting FROM pg_settings WHERE name = 'max_connections';


MySQL / Aurora MySQL / MariaDB:
sql
SHOW VARIABLES LIKE 'max_connections';
SELECT @@max_connections;


Oracle:
sql
SELECT value FROM v$parameter WHERE name = 'processes';
SELECT value FROM v$parameter WHERE name = 'sessions';


SQL Server:
sql
SELECT @@MAX_CONNECTIONS;
EXEC sp_configure 'user connections';


### Check Current Active Connections

PostgreSQL / Aurora PostgreSQL:
sql
SELECT count(*) FROM pg_stat_activity;


MySQL / Aurora MySQL:
sql
SHOW STATUS LIKE 'Threads_connected';
SELECT count(*) FROM information_schema.processlist;


Oracle:
sql
SELECT count(*) FROM v$session;


SQL Server:
sql
SELECT count(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1;


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary Comparison

| Engine | db.t3.medium | db.m5.large | db.r5.xlarge | Formula Divisor |
|--------|--------------|-------------|--------------|-----------------|
| PostgreSQL | 367 | 901 | 3,200 | 9,531,392 |
| MySQL | 332 | 664 | 2,658 | 12,582,880 |
| MariaDB | 332 | 664 | 2,658 | 12,582,880 |
| Oracle | 652 | 1,237 | 4,927 | 9,868,951 |
| SQL Server | ~400 | ~1,000 | ~4,000 | Memory-based |
| Aurora PostgreSQL | 367 | 1,600 | 3,200 | 9,531,392 |
| Aurora MySQL | 332 | 1,329 | 2,658 | 12,582,880 |

Key Insight: PostgreSQL and Aurora PostgreSQL generally support more connections per GB of memory than MySQL/Aurora 
MySQL.