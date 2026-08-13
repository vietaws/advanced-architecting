# Advanced Features

## DNS Firewall
- Create a rule group blocking `malware-test.op.viet.vn`
- Attach to VPC A
- Show blocked response in CloudWatch Logs

## CNAME and Alias Records in PHZ
- Add `api.cloud.viet.vn CNAME app.cloud.viet.vn`
- Show alias behavior vs CNAME
- Contrast with public hosted zone behavior

## Resolver Rule Sharing via RAM
- Show how `op.viet.vn` Resolver Rule can be shared to other AWS accounts
- Use case: multiple accounts in an AWS Organization all resolving `op.viet.vn`

---