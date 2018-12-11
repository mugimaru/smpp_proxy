# SmppProxy

SMPP 3.4 compliant proxy.

SmppProxy is aimed to provide third parties a temporary access to MC with different credentials,
optional source/destination addresses whitelist and RPS limit.

## Docs

build docs with

    mix docs

Start with `docs/index.html`

## Usage

build escript

    mix escript.build

rut it

    ./smpp_proxy  --mc-id panda --mc-password pwd --esme-id panda --esme-password pwd2 --esme-port 5051 --mc-port 5050 --rate_limit 10rps --debug

run `./smpp_proxy --help` to print available options.
