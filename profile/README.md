# ☁️ X-Evor Toolkit

A cloud-neutral ecosystem for connectivity, AI interaction, and service orchestration.
From local acceleration to intelligent workflows, and finally to cloud-side delivery, X-Evor connects every layer into one unified system.

**Experience chain:** Xstream -> Xworkmate -> console.svc.plus

> Note: this is a user experience sequence, not an internal dependency graph.

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Go Report Card](https://goreportcard.com/badge/github.com/cloud-neutral-toolkit/rag-server.svc.plus)](https://goreportcard.com/report/github.com/cloud-neutral-toolkit/rag-server.svc.plus)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

## X-Evor Architecture Overview

```txt
Xstream / Xworkmate / Other Apps / Web
                  |
                  v
           services.svc.plus
                  |
      ---------------------------------------------------------
      |               |               |                      |
      v               v               v                      v
accounts.svc.plus  rag-server.svc.plus  more services  OpenClaw Gateway
      \               |               /                   
       \              |              /                    
        \             |             /                     
            postgresql.svc.plus
                    |
                    v
               vector data

gitops + iac_modules -> all services -> observability.svc.plus
```

## Ecosystem Repositories

| Repository | Role | Quick Access |
| :--- | :--- | :--- |
| **xstream.svc.plus** | Connectivity, proxy, and acceleration foundation | [Source](https://github.com/cloud-neutral-toolkit/xstream.svc.plus) |
| **xworkmate.svc.plus** | AI assistant app and experience layer | [Source](https://github.com/cloud-neutral-toolkit/xworkmate.svc.plus) |
| **console.svc.plus** | Online console and cloud service portal | [Visit Console](https://console.svc.plus/) |
| **rag-server.svc.plus** | Retrieval-augmented generation backend services | [Source](https://github.com/cloud-neutral-toolkit/rag-server.svc.plus) |
| **accounts.svc.plus** | Identity, login, and account infrastructure | [Source](https://github.com/cloud-neutral-toolkit/accounts.svc.plus) |

## Experience Snapshot

### Platform and Delivery View

<p align="center">
  <img src="../images/1.png" alt="X-Evor platform overview" width="45%" />
  <img src="../images/2.png" alt="End-to-end delivery path from local to cloud" width="45%" />
</p>

### Workflow and Adoption Path

<p align="center">
  <img src="../images/3.png" alt="Layered workflow across Xstream, Xworkmate, and console.svc.plus" width="45%" />
  <img src="../images/4.png" alt="Three-step onboarding path across the toolkit" width="45%" />
</p>

## How It Fits Together

1. **Xstream** provides the connectivity and acceleration layer.
2. **Xworkmate** builds on that foundation as the AI assistant and work interface.
3. **console.svc.plus** acts as the online control plane for accounts, services, orchestration, and cloud access.
4. **OpenClaw Gateway** extends the system by connecting AI-driven capabilities and external service interactions.
5. **accounts**, **rag-server**, and other backend services share a common service and data foundation.

Together, they form a practical path from connectivity, to AI productivity, to managed online services.

## Quick Start

1. Visit [console.svc.plus](https://console.svc.plus/) for the online entry point.
2. Explore [xworkmate.svc.plus](https://github.com/cloud-neutral-toolkit/xworkmate.svc.plus) for the AI assistant experience.
3. Use [xstream.svc.plus](https://github.com/cloud-neutral-toolkit/xstream.svc.plus) for acceleration and connectivity.

---

<div align="center">

<strong>X-Evor</strong><br/>
Connectivity, AI, and cloud services working as one system.

Copyright © 2024-2026 Cloud-Neutral Toolkit. Licensed under the Apache 2.0 License.

</div>
