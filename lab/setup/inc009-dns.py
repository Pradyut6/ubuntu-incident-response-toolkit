
#!/usr/bin/env python3
"""INC-009: Isolated DNS responder and diagnostic client."""

import socket
import struct
import sys

HOST = "127.0.0.1"
PORT = 15353
ADDRESS = "192.0.2.53"

QUESTION = (
    b"\x0c" + b"uir-training"
    + b"\x07" + b"invalid"
    + b"\x00"
    + struct.pack("!HH", 1, 1)
)

TRANSACTION_ID = 0x9009

QUERY = (
    struct.pack("!HHHHHH", TRANSACTION_ID, 0x0100, 1, 0, 0, 0)
    + QUESTION
)


def make_response():
    header = struct.pack(
        "!HHHHHH", TRANSACTION_ID, 0x8500, 1, 1, 0, 0
    )

    answer = (
        b"\xc0\x0c"
        + struct.pack("!HHIH", 1, 1, 30, 4)
        + socket.inet_aton(ADDRESS)
    )

    return header + QUESTION + answer


def serve():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((HOST, PORT))

        print(f"DNS lab listening on {HOST}:{PORT}", flush=True)

        while True:
            packet, peer = sock.recvfrom(512)

            # Answer only the one fixed training query.
            if packet == QUERY:
                sock.sendto(make_response(), peer)


def check():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(1.5)

        try:
            sock.sendto(QUERY, (HOST, PORT))
            response, peer = sock.recvfrom(512)

        except (socket.timeout, OSError) as error:
            print(f"FAIL: DNS responder unavailable: {error}")
            return 1

        if peer != (HOST, PORT):
            print("FAIL: Unexpected responder address")
            return 1

        if response != make_response():
            print("FAIL: Unexpected DNS response")
            return 1

        print(
            f"PASS: uir-training.invalid resolved to {ADDRESS}"
        )
        print("PASS: DNS response verified")
        return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: inc009-dns.py serve|check")

    if sys.argv[1] == "serve":
        serve()
    elif sys.argv[1] == "check":
        sys.exit(check())
    else:
        sys.exit("Invalid command")
