# KipuBankV2 Smart Contract

## Descripción
KipuBankV2 es un contrato inteligente diseñado para gestionar un banco simple donde los usuarios pueden depositar y retirar ETH. Este contrato permite múltiples tokens ERC-20 y utiliza Chainlink para obtener precios de mercado.

## Características

### Depósitos
- **ETH:** Los usuarios pueden depositar ETH directamente.
- **Tokens ERC-20:** Los usuarios pueden depositar tokens permitidos.

### Retiros
- **ETH:** Los usuarios pueden retirar ETH, con un límite por transacción para evitar retiros excesivos.
- **Tokens ERC-20:** Los usuarios pueden retirar tokens permitidos.

### Gestión de Tokens
- **Agregar Tokens:** El propietario puede agregar nuevos tokens al catálogo y asignarles feeds de precios Chainlink.
- **Consultas de Precio:** Utiliza Chainlink para obtener precios en tiempo real de ETH/USD y otros pares.

### Seguridad
- **Reentrancy Guard:** Protección contra ataques de reentradas.
- **Owner:** Solo el propietario del contrato puede agregar tokens y modificar feeds.

### Eventos
- **Deposit:** Se emite cuando se realiza un depósito.
- **Withdrawal:** Se emite cuando se realiza un retiro.
- **TokenSupported:** Se emite cuando se agrega un nuevo token al catálogo.
- **ChainlinkFeedUpdated:** Se emite cuando se actualiza el feed de precios Chainlink.

## Funciones

### Depósitos
```solidity
function deposit(address _tokenAddress, uint256 _tokenAmount) external payable;
```

### Retiros
```solidity
function withdraw(address _tokenAddress, uint256 _tokenAmount) public nonReentrant;
```

### Gestión de Tokens
```solidity
function addSupportedToken(address tokenAddress, address priceFeedAddress, uint8 decimals) external onlyOwner;
```

### Consultas y Actualizaciones
```solidity
function setFeeds(address _tokenAddress, address _feedAddress) external onlyOwner;
function contractBalanceInUSD() public view returns (uint256 balance_);
```

## Instalación

Clone the repository:
```bash
git clone <repository-url>
```

Install dependencies:
```bash
cd KipuBankV2
npm install
```

Deploy the contract:

Utiliza un entorno de desarrollo como Remix o Hardhat para desplegar el contrato en una red Ethereum.

## Licencia
Este proyecto está bajo la licencia MIT.