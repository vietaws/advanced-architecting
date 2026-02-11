## Core Tag Schema (Apply to ALL Resources)

json
{
  "Environment": "production|staging|development",
  "CostCenter": "<department-code>",
  "Owner": "<team-email>",
  "Project": "<project-name>",
  "ManagedBy": "terraform|cloudformation|manual",
  "DataClassification": "public|internal|confidential|restricted"
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Account-Specific Tagging Strategy

### Account A (us-east-1 TGW Owner + VPC A)

#### Transit Gateway
json
{
  "Name": "tgw-us-east-1-prod",
  "Environment": "production",
  "CostCenter": "infrastructure",
  "Owner": "network-team@company.com",
  "Project": "multi-region-connectivity",
  "ManagedBy": "terraform",
  "Region": "us-east-1",
  "TGWRole": "regional-hub",
  "SharedWith": "account-b"
}


#### TGW Peering Attachment
json
{
  "Name": "tgw-peering-us-east-1-to-ap-southeast-1",
  "Environment": "production",
  "CostCenter": "infrastructure",
  "Owner": "network-team@company.com",
  "Project": "multi-region-connectivity",
  "ManagedBy": "terraform",
  "PeerRegion": "ap-southeast-1",
  "PeerAccount": "account-shared",
  "ConnectionType": "cross-region-peering"
}


#### VPC A
json
{
  "Name": "vpc-a-us-east-1-prod",
  "Environment": "production",
  "CostCenter": "application-team-a",
  "Owner": "team-a@company.com",
  "Project": "application-a",
  "ManagedBy": "terraform",
  "Region": "us-east-1",
  "VPCRole": "application",
  "DataClassification": "confidential"
}


#### VPC A TGW Attachment
json
{
  "Name": "tgw-attach-vpc-a",
  "Environment": "production",
  "CostCenter": "application-team-a",
  "Owner": "team-a@company.com",
  "Project": "application-a",
  "ManagedBy": "terraform",
  "AttachedVPC": "vpc-a-us-east-1-prod",
  "AttachedTGW": "tgw-us-east-1-prod",
  "RouteTable": "rt-application"
}


#### TGW Route Tables
json
{
  "Name": "tgw-rt-us-east-1-application",
  "Environment": "production",
  "CostCenter": "infrastructure",
  "Owner": "network-team@company.com",
  "Project": "multi-region-connectivity",
  "ManagedBy": "terraform",
  "RouteTablePurpose": "application-workloads",
  "AllowedDestinations": "vpc-b,shared-vpc,cross-region"
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Account B (VPC B only)

#### VPC B
json
{
  "Name": "vpc-b-us-east-1-prod",
  "Environment": "production",
  "CostCenter": "application-team-b",
  "Owner": "team-b@company.com",
  "Project": "application-b",
  "ManagedBy": "terraform",
  "Region": "us-east-1",
  "VPCRole": "application",
  "DataClassification": "internal"
}


#### VPC B TGW Attachment
json
{
  "Name": "tgw-attach-vpc-b",
  "Environment": "production",
  "CostCenter": "application-team-b",
  "Owner": "team-b@company.com",
  "Project": "application-b",
  "ManagedBy": "terraform",
  "AttachedVPC": "vpc-b-us-east-1-prod",
  "AttachedTGW": "tgw-us-east-1-prod",
  "TGWOwner": "account-a",
  "RouteTable": "rt-application"
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Account Shared (ap-southeast-1 TGW Owner + VPC Shared)

#### Transit Gateway
json
{
  "Name": "tgw-ap-southeast-1-prod",
  "Environment": "production",
  "CostCenter": "infrastructure",
  "Owner": "network-team@company.com",
  "Project": "multi-region-connectivity",
  "ManagedBy": "terraform",
  "Region": "ap-southeast-1",
  "TGWRole": "regional-hub",
  "SharedWith": "account-c,account-d,account-ingress,account-egress"
}


#### TGW Peering Attachment
json
{
  "Name": "tgw-peering-ap-southeast-1-to-us-east-1",
  "Environment": "production",
  "CostCenter": "infrastructure",
  "Owner": "network-team@company.com",
  "Project": "multi-region-connectivity",
  "ManagedBy": "terraform",
  "PeerRegion": "us-east-1",
  "PeerAccount": "account-a",
  "ConnectionType": "cross-region-peering"
}


#### VPC Shared
json
{
  "Name": "vpc-shared-ap-southeast-1-prod",
  "Environment": "production",
  "CostCenter": "shared-services",
  "Owner": "platform-team@company.com",
  "Project": "shared-services",
  "ManagedBy": "terraform",
  "Region": "ap-southeast-1",
  "VPCRole": "shared-services",
  "DataClassification": "internal",
  "Services": "kms,s3,dynamodb"
}


#### VPC Shared TGW Attachment
json
{
  "Name": "tgw-attach-vpc-shared",
  "Environment": "production",
  "CostCenter": "shared-services",
  "Owner": "platform-team@company.com",
  "Project": "shared-services",
  "ManagedBy": "terraform",
  "AttachedVPC": "vpc-shared-ap-southeast-1-prod",
  "AttachedTGW": "tgw-ap-southeast-1-prod",
  "RouteTable": "rt-shared-services"
}


#### VPC Endpoints (in Shared VPC)
json
{
  "Name": "vpce-kms-ap-southeast-1a",
  "Environment": "production",
  "CostCenter": "shared-services",
  "Owner": "platform-team@company.com",
  "Project": "shared-services",
  "ManagedBy": "terraform",
  "Service": "kms",
  "AvailabilityZone": "ap-southeast-1a",
  "EndpointType": "interface"
}


#### TGW Route Tables
json
[
  {
    "Name": "tgw-rt-ap-southeast-1-application",
    "Environment": "production",
    "CostCenter": "infrastructure",
    "Owner": "network-team@company.com",
    "Project": "multi-region-connectivity",
    "ManagedBy": "terraform",
    "RouteTablePurpose": "application-workloads",
    "AllowedDestinations": "shared-vpc,ingress,egress,cross-region"
  },
  {
    "Name": "tgw-rt-ap-southeast-1-shared-services",
    "Environment": "production",
    "CostCenter": "infrastructure",
    "Owner": "network-team@company.com",
    "Project": "multi-region-connectivity",
    "ManagedBy": "terraform",
    "RouteTablePurpose": "shared-services",
    "AllowedDestinations": "all-vpcs"
  },
  {
    "Name": "tgw-rt-ap-southeast-1-edge",
    "Environment": "production",
    "CostCenter": "infrastructure",
    "Owner": "network-team@company.com",
    "Project": "multi-region-connectivity",
    "ManagedBy": "terraform",
    "RouteTablePurpose": "ingress-egress",
    "AllowedDestinations": "application-vpcs-only"
  }
]


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Account C (VPC C only)

#### VPC C
json
{
  "Name": "vpc-c-ap-southeast-1-prod",
  "Environment": "production",
  "CostCenter": "application-team-c",
  "Owner": "team-c@company.com",
  "Project": "application-c",
  "ManagedBy": "terraform",
  "Region": "ap-southeast-1",
  "VPCRole": "application",
  "DataClassification": "confidential",
  "TrafficProfile": "high-volume"
}


#### VPC C TGW Attachment
json
{
  "Name": "tgw-attach-vpc-c",
  "Environment": "production",
  "CostCenter": "application-team-c",
  "Owner": "team-c@company.com",
  "Project": "application-c",
  "ManagedBy": "terraform",
  "AttachedVPC": "vpc-c-ap-southeast-1-prod",
  "AttachedTGW": "tgw-ap-southeast-1-prod",
  "TGWOwner": "account-shared",
  "RouteTable": "rt-application",
  "MonthlyDataVolume": "1TB+"
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Account D (VPC D only)

#### VPC D
json
{
  "Name": "vpc-d-ap-southeast-1-prod",
  "Environment": "production",
  "CostCenter": "application-team-d",
  "Owner": "team-d@company.com",
  "Project": "application-d",
  "ManagedBy": "terraform",
  "Region": "ap-southeast-1",
  "VPCRole": "application",
  "DataClassification": "internal",
  "TrafficProfile": "very-high-volume"
}


#### VPC D TGW Attachment
json
{
  "Name": "tgw-attach-vpc-d",
  "Environment": "production",
  "CostCenter": "application-team-d",
  "Owner": "team-d@company.com",
  "Project": "application-d",
  "ManagedBy": "terraform",
  "AttachedVPC": "vpc-d-ap-southeast-1-prod",
  "AttachedTGW": "tgw-ap-southeast-1-prod",
  "TGWOwner": "account-shared",
  "RouteTable": "rt-application",
  "MonthlyDataVolume": "3TB+"
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Account Ingress (VPC Ingress only)

#### VPC Ingress
json
{
  "Name": "vpc-ingress-ap-southeast-1-prod",
  "Environment": "production",
  "CostCenter": "infrastructure",
  "Owner": "network-team@company.com",
  "Project": "centralized-ingress",
  "ManagedBy": "terraform",
  "Region": "ap-southeast-1",
  "VPCRole": "ingress",
  "DataClassification": "public",
  "TrafficDirection": "inbound-from-internet"
}


#### VPC Ingress TGW Attachment
json
{
  "Name": "tgw-attach-vpc-ingress",
  "Environment": "production",
  "CostCenter": "infrastructure",
  "Owner": "network-team@company.com",
  "Project": "centralized-ingress",
  "ManagedBy": "terraform",
  "AttachedVPC": "vpc-ingress-ap-southeast-1-prod",
  "AttachedTGW": "tgw-ap-southeast-1-prod",
  "TGWOwner": "account-shared",
  "RouteTable": "rt-edge",
  "MonthlyDataVolume": "7TB+"
}


#### Application Load Balancer (in Ingress VPC)
json
{
  "Name": "alb-ingress-prod",
  "Environment": "production",
  "CostCenter": "infrastructure",
  "Owner": "network-team@company.com",
  "Project": "centralized-ingress",
  "ManagedBy": "terraform",
  "LoadBalancerType": "application",
  "Scheme": "internet-facing",
  "TargetVPCs": "vpc-c,vpc-d"
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Account Egress (VPC Egress only)

#### VPC Egress
json
{
  "Name": "vpc-egress-ap-southeast-1-prod",
  "Environment": "production",
  "CostCenter": "infrastructure",
  "Owner": "network-team@company.com",
  "Project": "centralized-egress",
  "ManagedBy": "terraform",
  "Region": "ap-southeast-1",
  "VPCRole": "egress",
  "DataClassification": "internal",
  "TrafficDirection": "outbound-to-internet",
  "TrafficProfile": "very-high-volume"
}


#### VPC Egress TGW Attachment
json
{
  "Name": "tgw-attach-vpc-egress",
  "Environment": "production",
  "CostCenter": "infrastructure",
  "Owner": "network-team@company.com",
  "Project": "centralized-egress",
  "ManagedBy": "terraform",
  "AttachedVPC": "vpc-egress-ap-southeast-1-prod",
  "AttachedTGW": "tgw-ap-southeast-1-prod",
  "TGWOwner": "account-shared",
  "RouteTable": "rt-edge",
  "MonthlyDataVolume": "30TB+"
}


#### NAT Gateways (in Egress VPC)
json
{
  "Name": "nat-egress-ap-southeast-1a",
  "Environment": "production",
  "CostCenter": "infrastructure",
  "Owner": "network-team@company.com",
  "Project": "centralized-egress",
  "ManagedBy": "terraform",
  "AvailabilityZone": "ap-southeast-1a",
  "MonthlyDataVolume": "15TB+"
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Allocation Tags (AWS Specific)

Enable these tags for AWS Cost Explorer and billing:

json
{
  "CostCenter": "required",
  "Environment": "required",
  "Project": "required",
  "Owner": "required"
}


### Activate in AWS Billing Console:
1. Go to AWS Billing Console → Cost Allocation Tags
2. Activate: CostCenter, Environment, Project, Owner
3. Wait 24 hours for tags to appear in Cost Explorer