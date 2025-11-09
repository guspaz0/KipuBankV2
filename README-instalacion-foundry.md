# instrucciones para foundry

## Requisitos:
- Instalacion dependencias:
```bash
forge install foundry-rs/forge-std
forge install openzeppelin/openzeppelin-contracts
forge install smartcontractkit/chainlink-local
forge install smartcontractkit/foundry-chainlink-toolkit

```

- remapping dependencias:

```bash
forge remappings
```
o bien, **recomendado**, crear archivo `foundry.toml` en la raiz del proyecto con los siguientes contenidos:
```toml
# Ejemplo de remappings en foundry.toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
remappings = [
    "@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/",
    "@chainlink/contracts/=lib/foundry-chainlink-toolkit/src/",
    "@chainlink-local/src/=lib/chainlink-local/src/",
    "forge-std=lib/forge-std/src"
]
```

## Desarrollo:

- Correr tests:
```bash
forge test
```

