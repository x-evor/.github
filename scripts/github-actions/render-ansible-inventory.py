#!/usr/bin/env python3
from pathlib import Path
from string import Template
import sys


def main() -> None:
    if len(sys.argv) != 8:
        raise SystemExit(
            "usage: render-ansible-inventory.py <template-path> <output-path> <server-alias> <ssh-host> <ssh-user> <ssh-port> <private-key-file>"
        )

    template_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    rendered = Template(template_path.read_text()).substitute(
        server_alias=sys.argv[3],
        ssh_host=sys.argv[4],
        ssh_user=sys.argv[5],
        ssh_port=sys.argv[6],
        private_key_file=sys.argv[7],
    )
    output_path.write_text(rendered)


if __name__ == "__main__":
    main()
