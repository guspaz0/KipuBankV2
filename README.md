# KipuBank V2 - Guía de Uso

## Descripción
KipuBank V2 es un contrato inteligente que permite depositar y retirar tanto ETH como tokens ERC20.

El presente es una continuacion/actualizacion del contrato kipuBank, para ver las instrucciones de despliegue dirigirse al [repositorio KipuBank](https://github.com/guspaz0/kipu-bank), respetando los parametro del constructor de esta version.

## Límites del Sistema
- Cap máximo del banco: Se establece un limite de ethers que el banco puede almacenar.
- Dirección del oráculo de precios (Chainlink): 0x694AA1769357215DE4FAC081bf1f309aDC325306
- WithdrawLimit: Límite de retiro por transacción, inmutable. Se recomienda modificar, ya que por razones de desarrollo, se establecio un valor muy bajo para pruebas.
- Solo tiene soporte para una direccion de token ERC20, establecido durante el despliegue.

## Interacción con Tokens ERC20

1. **Obtener tokens ERC20**
   - Desplegar un contrato ERC20 propio, o
   - Intercambiar tokens en Uniswap (https://app.uniswap.org)

2. **Preparación para depositar**
   - Si desplegó su propio contrato, mintear tokens para las direcciones que interactuarán
   - Aprobar el gasto de tokens llamando a `approve(address spender, uint256 amount)`. 
     - spender: dirección del contrato KipuBankV2
     - amount: cantidad de tokens a aprobar
   
   **Si el contrato sigue el estandar ERC20, el método `approve` debe estar disponible.**

3. **Operaciones**
   - Operar con ether:
      - Depositar ether: llamar a  `depositEther(uint256 amount)`.
      - Retirar ether: llamar a `withdrawEther(uint256 amount)`.
   - Operar con tokens:
      - Depositar Token: llamar a `depositUSDC(uint256 _usdcAmount)`.
      - Retirar Token: llamar a `withdrawUSDC(uint256 _usdcAmount)`.

## Interacción con ETH

Las operaciones con ETH se realizan de manera directa enviando o solicitando ETH al contrato.

## Notas Importantes
- Verificar siempre los montos antes de realizar operaciones
- Asegurarse de tener suficiente balance antes de retirar
- No enviar fondos directamente al contrato sin usar las funciones apropiadas
- Llamar a `setFeeds(address _feed)` para actualizar el Oraculo. operacion restringida solo al Propietario del contrato `owner`.