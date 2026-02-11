I want to build an architecture #002 for hybrid dns demonstration. below is detail:
- VPC A (CIDR: 10.1.0.0/16) to demonstrate VPC on Cloud
- VPC OP (CIDR: 10.2.0.0/16) to demonstrate on-premise infrastructure
- VPA and VPC OP will be connected via VPC Peering for cost saving and simplify network management. In the real case it will be connected via VPN or Direct Connect.

Task list:
1. Build EC2 on VPC A privately
2. Create S3 Bucket in same region with VPC A (ap-southeast-1)
3. EC2 can connect to S3 bucket via Gateway endpoint
4. Create an DNS server on Amazon EC2 at VPC OP 
5. Build a EC2 app on VPC OP to demonstrate an on-premise server to connect to Cloud (VPC A)
6. All inbound and outbound dns resolution will be handled by On-premise DNS at Task 4
7. Using Route 53 private hosted and inbound/outbound resolver to setup this architecture
8. Cost consideration for this architecture