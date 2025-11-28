# ==============================================================================
# PHASE 1: HARDENED NETWORK PLUMBING
# ==============================================================================

# --- 1. CONFIGURATION VARIABLES (EDIT THESE) ---
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Network Names
export MGMT_VPC_NAME="vpc-zscaler-mgmt"
export SERVICE_VPC_NAME="vpc-service-prod" # Existing Spoke VPC

# CIDRs
export MGMT_SUBNET_CIDR="10.100.1.0/24"
export SERVICE_SUBNET_NAME="sub-zscaler-service-${REGION}"
export SERVICE_SUBNET_CIDR="10.200.1.0/24"

# --- 2. SECURITY POLICY DEFINITIONS ---

# Internet Egress: STRICT HTTPS & DNS ONLY. 
# HTTP (80) is blocked. Malware C2 on port 80 will fail.
export ALLOWED_INTERNET_PORTS="tcp:443,udp:53,tcp:53"

# Corporate Inbound: What can On-Prem access in GCP?
# Adjust as needed (e.g. tcp:3389 for RDP, tcp:443 for Web Apps).
export ALLOWED_CORP_PORTS="tcp:443,tcp:3389"

# Health Checks: STRICT HTTPS.
# Zscaler ILB must use an SSL/TCP-443 Probe. HTTP-80 probe will fail.
export HEALTH_CHECK_PORT="tcp:443"

# --- 3. STANDARD RANGES (DO NOT CHANGE) ---
export IAP_RANGE="35.235.240.0/20"
export HEALTH_CHECK_RANGES="35.191.0.0/16,130.211.0.0/22"

# --- 4. ENVIRONMENT RANGES ---
export GCP_WORKLOAD_RANGES="10.0.0.0/8" 
export ON_PREM_RANGES="192.168.0.0/16,172.16.0.0/12" # From Cisco Hub
export ZSCALER_TAG="zscaler-cc"

# Initialize
gcloud config set project $PROJECT_ID

# ------------------------------------------------------------------------------
# A. INFRASTRUCTURE CREATION
# ------------------------------------------------------------------------------

echo ">> Creating Management Infrastructure..."
# Mgmt VPC
gcloud compute networks create $MGMT_VPC_NAME \
    --subnet-mode=custom \
    --bgp-routing-mode=global \
    --description="Dedicated Management VPC for Zscaler"

# Mgmt Subnet (With Flow Logs for Audit)
gcloud compute networks subnets create "${MGMT_VPC_NAME}-subnet" \
    --network=$MGMT_VPC_NAME \
    --region=$REGION \
    --range=$MGMT_SUBNET_CIDR \
    --enable-flow-logs \
    --logging-aggregation-interval=interval-5-sec \
    --logging-flow-sampling=0.5

# Cloud NAT (Mgmt Only - for Zscaler Updates)
gcloud compute routers create "${MGMT_VPC_NAME}-router" \
    --network=$MGMT_VPC_NAME \
    --region=$REGION

gcloud compute routers nats create "${MGMT_VPC_NAME}-nat" \
    --router="${MGMT_VPC_NAME}-router" \
    --region=$REGION \
    --auto-allocate-nat-external-ips \
    --nat-all-subnet-ip-ranges

echo ">> Creating Service Subnet (NIC1)..."
# Zscaler Service Interface Subnet
gcloud compute networks subnets create $SERVICE_SUBNET_NAME \
    --network=$SERVICE_VPC_NAME \
    --region=$REGION \
    --range=$SERVICE_SUBNET_CIDR \
    --enable-flow-logs \
    --logging-aggregation-interval=interval-5-sec \
    --logging-flow-sampling=0.5

# ------------------------------------------------------------------------------
# B. HARDENED FIREWALL RULES
# ------------------------------------------------------------------------------

echo ">> Applying Hardened Firewall Rules..."

# 1. SECURE SSH (IAP ONLY)
# No Public IPs allowed. SSH only via GCP Console/gcloud.
gcloud compute firewall-rules create "allow-iap-ssh-mgmt" \
    --network=$MGMT_VPC_NAME \
    --action=ALLOW --direction=INGRESS \
    --rules=tcp:22 \
    --source-ranges=$IAP_RANGE \
    --target-tags=$ZSCALER_TAG \
    --description="Allow SSH via Google Identity-Aware Proxy ONLY"

# 2. MANAGEMENT CLUSTERING
# Zscaler VMs need to talk to each other to sync state.
gcloud compute firewall-rules create "${MGMT_VPC_NAME}-allow-internal" \
    --network=$MGMT_VPC_NAME \
    --action=ALLOW --direction=INGRESS \
    --rules=all \
    --source-ranges=$MGMT_SUBNET_CIDR \
    --priority=1000

# 3. WORKLOADS -> ZSCALER (STRICT EGRESS)
# Only HTTPS and DNS allowed out to Zscaler.
gcloud compute firewall-rules create "allow-workloads-to-zscaler" \
    --network=$SERVICE_VPC_NAME \
    --action=ALLOW --direction=INGRESS \
    --rules=$ALLOWED_INTERNET_PORTS \
    --source-ranges=$GCP_WORKLOAD_RANGES \
    --target-tags=$ZSCALER_TAG \
    --description="Allow Workloads to access Zscaler on HTTPS/DNS only" \
    --enable-logging \
    --priority=1000

# 4. ZSCALER -> WORKLOADS (RETURN TRAFFIC)
# Allow Zscaler to reply to the workloads.
gcloud compute firewall-rules create "allow-zscaler-to-workloads" \
    --network=$SERVICE_VPC_NAME \
    --action=ALLOW --direction=INGRESS \
    --rules=tcp,udp \
    --source-tags=$ZSCALER_TAG \
    --destination-ranges=$GCP_WORKLOAD_RANGES \
    --priority=1000

# 5. HEALTH CHECKS (STRICT HTTPS)
# This allows the L4 ILB to probe the Zscaler VM. 
# MUST be Port 443.
gcloud compute firewall-rules create "allow-google-health-checks" \
    --network=$SERVICE_VPC_NAME \
    --action=ALLOW --direction=INGRESS \
    --rules=$HEALTH_CHECK_PORT \
    --source-ranges=$HEALTH_CHECK_RANGES \
    --target-tags=$ZSCALER_TAG \
    --priority=900 \
    --description="Allow Google LB Probes on Port 443"

# 6. CISCO HUB INBOUND
# Allow On-Prem users to reach apps in this VPC.
gcloud compute firewall-rules create "allow-corporate-inbound" \
    --network=$SERVICE_VPC_NAME \
    --action=ALLOW --direction=INGRESS \
    --rules=$ALLOWED_CORP_PORTS \
    --source-ranges=$ON_PREM_RANGES \
    --priority=1000 \
    --description="Allow specific Corp Apps from On-Prem via Cisco Hub"


#################################################
# ==============================================================================
# EXPLICIT DENY INGRESS (LOGGING ENABLED)
# ==============================================================================

export SERVICE_VPC_NAME="vpc-service-prod" 
export MGMT_VPC_NAME="vpc-zscaler-mgmt" 
export PROJECT_ID="your-project-id"

gcloud config set project $PROJECT_ID

# 1. Deny Ingress - Service VPC (Workloads)
# Catches lateral movement attempts or rogue internet traffic.
echo ">> Creating Explicit Deny Ingress for Service VPC..."
gcloud compute firewall-rules create "deny-service-ingress-all" \
    --network=$SERVICE_VPC_NAME \
    --action=DENY \
    --direction=INGRESS \
    --rules=all \
    --source-ranges=0.0.0.0/0 \
    --priority=65000 \
    --enable-logging \
    --description="Explicitly Block and Log all unauthorized ingress traffic"

# 2. Deny Ingress - Management VPC (Zscaler Mgmt)
# Protects the Zscaler management interfaces from unauthorized probing.
echo ">> Creating Explicit Deny Ingress for Mgmt VPC..."
gcloud compute firewall-rules create "deny-mgmt-ingress-all" \
    --network=$MGMT_VPC_NAME \
    --action=DENY \
    --direction=INGRESS \
    --rules=all \
    --source-ranges=0.0.0.0/0 \
    --priority=65000 \
    --enable-logging \
    --description="Explicitly Block and Log all unauthorized ingress traffic"

echo ">> Deny Rules Applied. Unauthorized traffic will now appear in Cloud Logging."

#################################
# Phase 2: The Routing

# ==============================================================================
# PHASE 2: ACTIVATE TRAFFIC (ROUTING)
# ==============================================================================

# --- INPUT REQUIRED ---
# Ask the Zscaler team for this. 
# Format: projects/<PROJ>/regions/<REGION>/forwardingRules/<NAME>
export ILB_FORWARDING_RULE="PASTE_THEIR_ILB_LINK_HERE" 
export SERVICE_VPC_NAME="vpc-service-prod"
export PROJECT_ID="your-project-id"

gcloud config set project $PROJECT_ID

echo ">> Creating Forced Egress Route..."

# Create the Default Route (0.0.0.0/0)
# Priority 800: This is CRITICAL.
# The Cisco Hub (via BGP) usually imports routes with Priority 1000.
# Setting this to 800 ensures Zscaler WINS for Internet traffic, 
# preventing "tromboning" back to on-prem.
gcloud compute routes create "route-egress-via-zcc-ilb" \
    --network=$SERVICE_VPC_NAME \
    --destination-range="0.0.0.0/0" \
    --next-hop-ilb=$ILB_FORWARDING_RULE \
    --priority=800 \
    --description="Forces Internet traffic to Zscaler ILB (Wins against Cisco Hub)"

echo ">> Routing Complete. Traffic is now active."

