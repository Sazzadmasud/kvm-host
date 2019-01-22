jq . << EOF > ~/inrootenv.json
{
  "ssh-user": "root",
  "ssh-key": "$(cat ~/.ssh/id_rsa)",
  "power_manager": "nova.virt.baremetal.virtual_power_driver.VirtualPowerManager",
  "host-ip": "172.24.19.1",
  "arch": "x86_64",
  "nodes": [
    {
      "pm_addr": "172.24.19.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 1p /tmp/nodes.txt)"
      ],
      "cpu": "2",
      "memory": "4096",
      "disk": "60",
      "arch": "x86_64",
      "pm_user": "root"
    },
    {
      "pm_addr": "172.24.19.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 3p /tmp/nodes.txt)"
      ],
      "cpu": "4",
      "memory": "2048",
      "disk": "60",
      "arch": "x86_64",
      "pm_user": "root"
    }
  ]
}
EOF

