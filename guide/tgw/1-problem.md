## Problem

I have an aws architecture by using multi accounts and multi region setup. all the vpc connected via aws transit gateway. below is some info:

1. Region used: us-east-1 , ap-southeast-1
2. In us-east-1, there are 2 VPC (Each VPC in separated AWS Account)
    1. VPC A
    2. VPC B
3. in ap-southeast-1, there are 3 VPCs  (Each VPC in separated AWS Account)
    1. VPC C
    2. VPC D
    3. VPC Shared
    4. VPC Ingress (Inbound from Internet)
    5. VPC Egress (Outboud to Internet)
4. All inbound will be handled by VPC Ingress
5. All outbound will be handle via VPC Egress
6. VPC A, B, C, D will connect to Share VPC to access some common services: KMS, S3, DynamoDB
7. Application will be deployed in 2 AZs, determine the number of VPC endpoints for each service.
8. Here are data flow between VPC:
    1. VPC A to Shared VPC: Download 1GB per day, Upload 200MB per day
    2. VPC B to Shared VPC: Download 2GB per day, Upload 500MB per day
    3. VPC A to VPC B: Download 8GB per day, Upload 3GB per day
    4. VPC A to VPC C: Download 4GB per day, Upload 9GB per day
    5. VPC C to VPC Shared: Download 1TB per day, Upload 4GB per day
    6. VPC D to VPC Shared: Download 500GB per day, Upload 3TB per day
    7. VPC Ingress to VPC C and VPC D: 4TB per day (VPC C), 3TB per Day for VPC D
    8. VPC C and VPC D to VPC Egress: 10TB per day for VPC C, and 20 TB per day for VPC D
Please answer:
1. Number of AWS Transit Gateway for this architecture?
2. Number of Transit Gateway Peering
3. Number of Attachment per Transit Gateway
4. Cost of data transfer, transit gateway fee per Account (each VPC in separated account, VPC A will belong to Account A).
5. Suggest some optimization and best practice for real world scenario.
