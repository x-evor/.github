ui = true
disable_mlock = true

api_addr = "https://vault.svc.plus"
cluster_addr = "http://vault:8201"

storage "raft" {
  path = "/opt/vault/data"
  node_id = "vault-1"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable = true
}
