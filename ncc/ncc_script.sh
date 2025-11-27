#################
#Configure Variables
# --- 1. PROJECT SETUP ---
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# --- 2. MANAGEMENT VPC (NEW) ---
# This VPC is for Zscaler Management traffic only (Updates, Logs).
export MGMT_VPC_NAME="vpc-zscaler-mgmt"
export MGMT_SUBNET_CIDR="10.100.1.0/24"

# --- 3. SERVICE VPC (EXISTING) ---
# The name of your existing Spoke VPC where workloads live.
export SERVICE_VPC_NAME="vpc-service-prod" 
export SERVICE_SUBNET_NAME="sub-zscaler-service-${REGION}"
export SERVICE_SUBNET_CIDR="10.200.1.0/24"

# --- 4. FIREWALL RANGES ---
# Google's IAP Range (Standard/Fixed). Allows SSH via Console without Public IPs.
export IAP_RANGE="35.235.240.0/20"

# Google's Health Check Ranges (Standard/Fixed). Required for Load Balancers.
export HEALTH_CHECK_RANGES="35.191.0.0/16,130.211.0.0/22"

# Internal GCP Workloads: IPs of the VMs inside GCP that need Internet Access.
export GCP_WORKLOAD_RANGES="10.0.0.0/8" 

# External Corporate Ranges: IPs from On-Prem/AWS/Azure coming via Cisco Hub.
export ON_PREM_RANGES="192.168.0.0/16,172.16.0.0/12" 

# Tag to identify Zscaler VMs (The Zscaler team must use this tag on their VMs)
export ZSCALER_TAG="zscaler-cc"

# Set the active project
gcloud config set project $PROJECT_ID

######################################################
# Create Management Infrastructure

# Create the dedicated Management VPC
# --subnet-mode=custom: We want full control over subnets.
# --bgp-routing-mode=global: Good practice for future scalability.
echo "Creating Management VPC..."
gcloud compute networks create $MGMT_VPC_NAME \
    --subnet-mode=custom \
    --bgp-routing-mode=global \
    --description="Dedicated Management VPC for Zscaler"

# Create the Management Subnet (NIC0)
# --enable-flow-logs: Critical for troubleshooting "Why is Zscaler not connecting?"
echo "Creating Management Subnet..."
gcloud compute networks subnets create "${MGMT_VPC_NAME}-subnet" \
    --network=$MGMT_VPC_NAME \
    --region=$REGION \
    --range=$MGMT_SUBNET_CIDR \
    --enable-flow-logs \
    --logging-aggregation-interval=interval-5-sec \
    --logging-flow-sampling=0.5

# Create Cloud Router & NAT for Management
# Zscaler needs this to download updates from the Zscaler Cloud.
echo "Creating Management Cloud Router & NAT..."
gcloud compute routers create "${MGMT_VPC_NAME}-router" \
    --network=$MGMT_VPC_NAME \
    --region=$REGION

gcloud compute routers nats create "${MGMT_VPC_NAME}-nat" \
    --router="${MGMT_VPC_NAME}-router" \
    --region=$REGION \
    --auto-allocate-nat-external-ips \
    --nat-all-subnet-ip-ranges \
    --enable-logging


####################################
#Create Service Infrastructure (In Existing VPC)

# Create the Service Subnet (NIC1) in your EXISTING Service VPC.
# This is where the Zscaler "LAN" interface lives.
echo "Creating Service Subnet in ${SERVICE_VPC_NAME}..."
gcloud compute networks subnets create $SERVICE_SUBNET_NAME \
    --network=$SERVICE_VPC_NAME \
    --region=$REGION \
    --range=$SERVICE_SUBNET_CIDR \
    --enable-flow-logs \
    --logging-aggregation-interval=interval-5-sec \
    --logging-flow-sampling=0.5



###########################
# Configure Firewalls (Security & IAP)
echo "Creating Firewall Rules..."

# --- A. SECURE SSH (IAP) ---
# Allows you to SSH into Zscaler/VMs using the "SSH" button in Console.
# No Public IPs required.
gcloud compute firewall-rules create "allow-iap-ssh-mgmt" \
    --network=$MGMT_VPC_NAME \
    --action=ALLOW --direction=INGRESS \
    --rules=tcp:22 \
    --source-ranges=$IAP_RANGE \
    --target-tags=$ZSCALER_TAG \
    --description="Allow SSH via Google Identity-Aware Proxy"

# --- B. MANAGEMENT INTERNAL ---
# Allow Zscaler components to talk to each other in the Mgmt VPC.
gcloud compute firewall-rules create "${MGMT_VPC_NAME}-allow-internal" \
    --network=$MGMT_VPC_NAME \
    --action=ALLOW --direction=INGRESS \
    --rules=all \
    --source-ranges=$MGMT_SUBNET_CIDR \
    --priority=1000

# --- C. WORKLOADS -> ZSCALER (CRITICAL) ---
# Allows your GCP Apps to send traffic to Zscaler for inspection.
gcloud compute firewall-rules create "allow-workloads-to-zscaler" \
    --network=$SERVICE_VPC_NAME \
    --action=ALLOW --direction=INGRESS \
    --rules=all \
    --source-ranges=$GCP_WORKLOAD_RANGES \
    --target-tags=$ZSCALER_TAG \
    --description="Allow GCP workloads to hit Zscaler NIC" \
    --enable-logging \
    --priority=1000

# --- D. ZSCALER -> WORKLOADS (RETURN TRAFFIC) ---
# Allows Zscaler to reply to your apps.
gcloud compute firewall-rules create "allow-zscaler-to-workloads" \
    --network=$SERVICE_VPC_NAME \
    --action=ALLOW --direction=INGRESS \
    --rules=all \
    --source-tags=$ZSCALER_TAG \
    --destination-ranges=$GCP_WORKLOAD_RANGES \
    --priority=1000

# --- E. HEALTH CHECKS (CRITICAL) ---
# If you miss this, the Load Balancer will assume Zscaler is dead and drop traffic.
gcloud compute firewall-rules create "allow-google-health-checks" \
    --network=$SERVICE_VPC_NAME \
    --action=ALLOW --direction=INGRESS \
    --rules=tcp \
    --source-ranges=$HEALTH_CHECK_RANGES \
    --target-tags=$ZSCALER_TAG \
    --priority=900

# --- F. CISCO HUB INBOUND ---
# Allows traffic from On-Prem/AWS (via Cisco) to reach your GCP apps.
gcloud compute firewall-rules create "allow-corporate-inbound" \
    --network=$SERVICE_VPC_NAME \
    --action=ALLOW --direction=INGRESS \
    --rules=all \
    --source-ranges=$ON_PREM_RANGES \
    --priority=1000 \
    --description="Allow inbound traffic from Cisco Hub/On-Prem"


#######################################################

/*Phase 2: The Routing (Run After Zscaler Deployment)
STOP here until the Zscaler team (or deployment script) has finished. You need the Forwarding Rule ID they create.

Once you have it (e.g., projects/my-proj/regions/us-central1/forwardingRules/zscaler-ilb */

# --- CONFIGURATION ---
# Paste the Link the Zscaler team gives you here:
export ILB_FORWARDING_RULE="PASTE_THEIR_ILB_LINK_HERE" 

# --- CREATE FORCED EGRESS ROUTE ---
# This route forces 0.0.0.0/0 (Internet) to Zscaler.
# --priority=800: This is lower (better) than the default 1000.
# It ensures this route wins against the Cisco Router if the Cisco accidentally
# advertises a default route.
echo "Creating Forced Egress Route..."
gcloud compute routes create "route-egress-via-zcc-ilb" \
    --network=$SERVICE_VPC_NAME \
    --destination-range="0.0.0.0/0" \
    --next-hop-ilb=$ILB_FORWARDING_RULE \
    --priority=800 \
    --description="Forces Internet traffic to Zscaler ILB (Wins against Cisco Hub)"

echo "Routing Complete. Internet traffic is now flowing through Zscaler."

