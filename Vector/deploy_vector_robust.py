import argparse
import os
import sys
from google.cloud import aiplatform

def parse_args():
    parser = argparse.ArgumentParser(description="Robust Vector Search Deployment")
    
    # --- General ---
    parser.add_argument("--project_id", required=True, help="GCP Project ID")
    parser.add_argument("--region", required=True, help="GCP Region (e.g., us-central1)")
    parser.add_argument("--display_name", required=True, help="Base name for resources")
    
    # --- Index Configuration ---
    parser.add_argument("--dimensions", type=int, required=True, help="Vector dimensions (e.g., 768)")
    parser.add_argument("--index_type", choices=["tree-ah", "brute-force"], default="tree-ah", help="Algorithm type")
    parser.add_argument("--distance_measure", default="DOT_PRODUCT_DISTANCE", 
                        choices=["DOT_PRODUCT_DISTANCE", "COSINE_DISTANCE", "L2_SQUARED_DISTANCE"],
                        help="Metric for vector distance")
    parser.add_argument("--shard_size", default="SHARD_SIZE_MEDIUM", 
                        choices=["SHARD_SIZE_SMALL", "SHARD_SIZE_MEDIUM", "SHARD_SIZE_LARGE"],
                        help="Size of shards (affects cost/performance)")
    parser.add_argument("--gcs_uri", default=None, help="GCS URI for initial data (gs://...)")
    parser.add_argument("--approx_neighbors", type=int, default=150, help="Approx neighbors count (Tree-AH only)")
    parser.add_argument("--update_method", choices=["BATCH_UPDATE", "STREAM_UPDATE"], default="BATCH_UPDATE", help="Update method")

    # --- Network / Security ---
    parser.add_argument("--enable_psc", type=str, default="true", help="Enable Private Service Connect (true/false)")
    parser.add_argument("--allowlist_projects", default="", help="Comma-separated list of Project IDs allowed to connect")

    # --- Deployment (Compute) ---
    parser.add_argument("--machine_type", default="e2-standard-4", help="Machine type for deployment")
    parser.add_argument("--min_replicas", type=int, default=1, help="Min replica count")
    parser.add_argument("--max_replicas", type=int, default=1, help="Max replica count")

    return parser.parse_args()

def main():
    args = parse_args()
    
    # Initialize Vertex AI SDK
    aiplatform.init(project=args.project_id, location=args.region)
    
    index_name = f"{args.display_name}-index"
    endpoint_name = f"{args.display_name}-endpoint"
    deployed_id = f"{args.display_name}_deployed".replace("-", "_")
    
    print(f"🚀 Starting robust deployment for {args.display_name}...")

    # ==============================================================================
    # 1. CREATE INDEX (Robust Logic)
    # ==============================================================================
    existing_indexes = aiplatform.MatchingEngineIndex.list(filter=f'display_name="{index_name}"')
    
    if existing_indexes:
        my_index = existing_indexes[0]
        print(f"✅ Found existing Index: {my_index.resource_name}")
    else:
        print(f"🛠 Creating new {args.index_type} Index...")
        
        if args.index_type == "tree-ah":
            my_index = aiplatform.MatchingEngineIndex.create_tree_ah_index(
                display_name=index_name,
                contents_delta_uri=args.gcs_uri,
                dimensions=args.dimensions,
                approximate_neighbors_count=args.approx_neighbors,
                distance_measure_type=args.distance_measure,
                shard_size=args.shard_size,
                index_update_method=args.update_method,
                description="Deployed via Robust Python Automation"
            )
        else: # Brute Force
            my_index = aiplatform.MatchingEngineIndex.create_brute_force_index(
                display_name=index_name,
                contents_delta_uri=args.gcs_uri,
                dimensions=args.dimensions,
                distance_measure_type=args.distance_measure,
                shard_size=args.shard_size,
                index_update_method=args.update_method,
                description="Deployed via Robust Python Automation"
            )
        print(f"✅ Index Created: {my_index.resource_name}")

    # ==============================================================================
    # 2. CREATE ENDPOINT (Private Service Connect Logic)
    # ==============================================================================
    existing_endpoints = aiplatform.MatchingEngineIndexEndpoint.list(filter=f'display_name="{endpoint_name}"')
    
    if existing_endpoints:
        my_endpoint = existing_endpoints[0]
        print(f"✅ Found existing Endpoint: {my_endpoint.resource_name}")
    else:
        print("🛠 Creating new Endpoint...")
        
        # Parse Boolean for PSC
        psc_enabled = args.enable_psc.lower() == "true"
        
        # If PSC is enabled, public_endpoint MUST be False
        # If PSC is disabled, public_endpoint MUST be True (usually)
        public_ip = not psc_enabled
        
        allowlist = args.allowlist_projects.split(",") if args.allowlist_projects else []
        
        my_endpoint = aiplatform.MatchingEngineIndexEndpoint.create(
            display_name=endpoint_name,
            public_endpoint_enabled=public_ip,
            project_allowlist=allowlist if psc_enabled else None,
            description="Robust Endpoint"
        )
        print(f"✅ Endpoint Created: {my_endpoint.resource_name}")

    # ==============================================================================
    # 3. DEPLOY INDEX TO ENDPOINT
    # ==============================================================================
    # Check if this specific index is already on this endpoint
    is_deployed = any(d.id == deployed_id for d in my_endpoint.deployed_indexes)
    
    if is_deployed:
        print("✅ Index is already deployed.")
    else:
        print(f"🚀 Deploying Index to Endpoint (Machine: {args.machine_type})...")
        print("   This operation can take 20-40 minutes.")
        
        my_endpoint.deploy_index(
            index=my_index,
            deployed_index_id=deployed_id,
            machine_type=args.machine_type,
            min_replica_count=args.min_replicas,
            max_replica_count=args.max_replicas
        )
        print("✅ Deployment Complete.")

    # ==============================================================================
    # 4. FINAL OUTPUTS (For Network/DNS Teams)
    # ==============================================================================
    if args.enable_psc.lower() == "true":
        print("\n" + "="*60)
        print("📢 NETWORK CONFIGURATION REQUIRED")
        print("="*60)
        print(f"Target Project:    {args.project_id}")
        print(f"Region:            {args.region}")
        print(f"Endpoint ID:       {my_endpoint.resource_name}")
        
        # Try to extract Service Attachment if available in SDK properties
        # (Note: Some SDK versions require an extra 'describe' call or checking logs)
        print("Please check the GitHub Actions logs or GCP Console for the 'Service Attachment' URI")
        print("and create the PSC Forwarding Rule in the Shared VPC.")
        print("="*60)

if __name__ == "__main__":
    main()
