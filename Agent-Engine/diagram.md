graph TD
    A[Agent Engine Runtime<br>(Google tenant project)] -->|PSC Interface| B[Network Attachment<br>(Host Project)]
    B --> C[Dedicated PSC-I Subnet<br>(Shared via Shared VPC)]
    C --> D[Host VPC<br>(non-prod or prod)]
    D --> E[GKE / Cloud Run / VMs<br>(Service Project A - LOB1)]
    D --> F[GKE / Cloud Run / VMs<br>(Service Project B - LOB2)]
    style B fill:#e3f2fd
    style C fill:#e8f5e9


    
