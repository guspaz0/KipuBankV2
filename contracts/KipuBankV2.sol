// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/*//////////////////
        Imports
//////////////////*/
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*///////////////////////
        Libraries
///////////////////////*/
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/*///////////////////////
        Interfaces
///////////////////////*/
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title KipuBank
 * @author Gustavo R. Paz
 * @dev Smart contract para gestionar un banco sencillo donde los usuarios pueden depositar y retirar ETH.
 */
contract KipuBankV2 is Ownable {
    /*///////////////////////
        TYPE DECLARATIONS
    ///////////////////////*/
    using SafeERC20 for IERC20;

    /*//////////////////////////////
          Variables de estado
    ///////////////////////////////*/

    /// @notice Límite por transacción de retiro (en wei)
    uint256 public immutable withdrawLimit = 1e14;

    ///@notice immutable variable to store the USDC address
    IERC20 immutable i_usdc;

    ///@notice constant variable to hold Data Feeds Heartbeat
    uint256 constant ORACLE_HEARTBEAT = 3600;
    ///@notice constant variable to gold the decimals factor
    uint256 constant DECIMAL_FACTOR = 1 * 10 ** 20;
    ///@notice constant variable to remove magic number
    uint256 constant ZERO = 0;

    ///@notice variable to store Chainlink Feeds address
    AggregatorV3Interface public feeds; //0x694AA1769357215DE4FAC081bf1f309aDC325306 Ethereum ETH/USD
    //0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238

    /// @notice Mapping para relacionar las direcciones con la información de los usuarios
    mapping(address user => mapping(address token => uint256 amount))
        public balances;

    /// @notice Limite global de depositos;
    uint256 public immutable bankCap;

    /// @notice contador retiros
    uint128 public withdrawalCount = 0;

    //@notice contador depositos
    uint128 public depositosCount = 0;

    /// @notice Indica si el contrato está bloqueado para nuevas transacciones.
    bool private lock = false;

    /*//////////////////////////////
            Errores
    ///////////////////////////////*/

    /// @notice Error personalizado para manejo de fondos insuficientes
    error InsufficientUserBalance(uint256 requested, uint256 available);

    /// @notice Error personalizado para manejo de valores no válidos
    error ValueError(uint256 value);

    /// @notice Error personalizado para manejo de llamadas no autorizadas
    error Reentrancy();

    /// @notice Error personalizado para manejo de excedentes del límite del banco
    error BankCapLimitExceeded(
        uint256 bankCap
    );

    /// @notice Error personalizado para manejo de errores en el limite de retiro
    error WithdrawalLimitExceeded(address caller, uint256 attemptedWithdrawal);

    /// @notice Error personalizado para manejo de errores en retiros con valor cero
    error WithdrawalAmountError(address caller, uint256 attemptedWithdrawal);

    /// @notice Error personalizado para manejo de retiros al transferir
    error WithdrawalTransferError(bytes reason);

    /// @notice Error personalizado para manejo de errores en los depositos
    error DepositAmountMismatch(
        address caller,
        uint256 expectedValue,
        uint256 _amount
    );

    /// @notice Error personalizado para manejo de errores en el los depositos
    error DepositFailed(address caller, uint256 value);

    /// @notice Error personalizado para manejo de errores en el los depositos fallbacks (receive)
    error ReceiveFallbackDepositError(address caller, uint256 value);

    /// @notice Error personalizado para manejo de errores en el los depositos fallbacks (fallback)
    error FallbackDepositError(address caller, uint256 value);

    /// @notice Error personalizado para manejo de errores en los parametros del constructor
    error ConstructorError(string parameter);

    ///@notice error emitido cuando el oracle devuelve un valor incorrecto
    error OracleCompromised();

    ///@notice error emitido cuando la ultima actualización del oraculo es mayor que el heartbeat
    error StalePrice();

    /*//////////////////////////////
            Eventos
    ///////////////////////////////*/

    /// @notice Evento que se emite cuando se realiza un depósito
    event Deposit(address indexed _user, uint256 _amount, uint256 _newBalance);

    /// @notice Evento que se emite cuando se realiza un retiro
    event Withdrawal(
        address indexed _user,
        uint256 _amount,
        uint256 _newBalance
    );

    /// @notice Evento que se emite cuando se actualiza la direccion del feed de precios Chainlink.
    event ChainlinkFeedUpdated(address _feed);

    /*//////////////////////////////
            Modificadores
    ///////////////////////////////*/

    /// @notice Modificador para prevenir la reentrancia
    modifier nonReentrant() {
        if (lock) revert Reentrancy();
        lock = true;
        _;
        lock = false;
    }
    /// @notice Modificador para verificar si no se ah excedido el limite del banco y actualiza el balance
    modifier bankCapCheck(uint256 _usdcAmount) {
        uint256 newBalance = contractBalanceInUSD() + _usdcAmount;
        if (newBalance > bankCap) revert BankCapLimitExceeded(bankCap);
        _;
    }

    /**
     * @dev Constructor del contrato
     * @param _bankCap El límite máximo de fondos que el banco puede manejar (en wei)
     * @param _feed Direccion del Oraculo para consultar el precio del USDC
     * @param _usdc Direccion del contrato ERC20 USDC
     * @param _owner Direccion del dueño del contrato
     */
    constructor(
        uint256 _bankCap,
        address _feed,
        address _usdc,
        address _owner
    ) Ownable(_owner) {
        if (_bankCap == 0) revert ConstructorError("_bankCap");
        bankCap = _bankCap;
        feeds = AggregatorV3Interface(_feed);
        i_usdc = IERC20(_usdc);
    }

    /*//////////////////////////////
            Funciones
    ///////////////////////////////*/

    /**
     * @dev Función para depositar ETH en la cuenta del usuario
     */
    function depositEther(uint256 _amount) external payable {
        if (_amount != msg.value)
            revert DepositAmountMismatch(msg.sender, msg.value, _amount);
        bool success = depositFallback();
        if (!success) revert DepositFailed(msg.sender, msg.value);
    }
    /**
     * @dev Función para depositar ETH en la cuenta del usuario
     */
    function depositUSDC(uint256 _usdcAmount) external bankCapCheck(_usdcAmount) {

        uint256 userBalance = balances[msg.sender][address(i_usdc)];

        balances[msg.sender][address(i_usdc)] = userBalance + _usdcAmount;

        emit Deposit(msg.sender, _usdcAmount, userBalance + _usdcAmount);

        i_usdc.safeTransferFrom(msg.sender, address(this), _usdcAmount);

        depositosCount++;
    }

    /**
     * @dev Función para retirar ETH de la cuenta del usuario
     * @param amount La cantidad a retirar (en wei)
     */
    function withdrawEther(uint256 amount) public nonReentrant {
        if (amount == 0) revert WithdrawalAmountError(msg.sender, amount);
        // Cache the balance to avoid multiple storage reads
        uint256 userBalance = balances[msg.sender][address(0)];

        if (amount > withdrawLimit)
            revert WithdrawalLimitExceeded(msg.sender, amount);
        if (amount > userBalance)
            revert InsufficientUserBalance(amount, userBalance);

        // Restar la cantidad retirada al balance del usuario
        balances[msg.sender][address(0)] = userBalance - amount;

        // Transferir la cantidad al usuario
        (bool success, bytes memory data) = msg.sender.call{value: amount}("");
        if (!success) revert WithdrawalTransferError(data);

        // Emitir evento de retiro
        emit Withdrawal(msg.sender, amount, userBalance - amount);

        // aumentar contador retiros
        withdrawalCount++;
    }
    /**
    * @notice funcion externa para retirar USDC de la cuenta del usuario
    * @param _amount La cantidad a retirar en USDC
    * @dev el usuario no deberia poder retirar mas de su balance en USDC
    * @dev el usuario no deberia poder retirar mas del umbral de retiro por transaccion (bankCap)
     */
    function withdrawUSDC(uint256 _amount) public nonReentrant {
        uint256 userBalance = balances[msg.sender][address(i_usdc)];

        if (_amount > userBalance) revert InsufficientUserBalance(_amount, userBalance);

        withdrawalCount++;
        balances[msg.sender][address(i_usdc)] -= _amount;

        emit Withdrawal(msg.sender,_amount, userBalance - _amount);

        i_usdc.safeTransfer(msg.sender,_amount);
    }

    /// @notice funcion privada para manejar el depósito de ETH en caso de que entre en las funciones fallback
    function depositFallback() private bankCapCheck(ZERO) returns (bool) {
        if (msg.value == 0) return false;

        uint256 userBalance = balances[msg.sender][address(0)];

        balances[msg.sender][address(0)] = userBalance + msg.value;

        // emitir evento deDeposito
        emit Deposit(msg.sender, msg.value, userBalance + msg.value);

        // aumentar contador depositos
        depositosCount++;
        return true;
    }

    /**
     * @notice funcion extena para consultar el balance del contrato en USDC.
     * @return balance_ el monto de ETH en el contrato.
     */
    function contractBalanceInUSD() public view returns (uint256 balance_) {
        uint256 convertedUSDAmount = convertEthInUSD(address(this).balance);

        balance_ = convertedUSDAmount + i_usdc.balanceOf(address(this));
    }

    /**
     * @notice function interna para convertir la cantidad de ETH a USDC usando un oraculo.
     * @param _ethAmount el monto de ETH a convertir.
     * @return convertedAmount_ resultado del calculo.
     */
    function convertEthInUSD(
        uint256 _ethAmount
    ) internal view returns (uint256 convertedAmount_) {
        convertedAmount_ = (_ethAmount * chainlinkFeed()) / DECIMAL_FACTOR;
    }

    /**
     * @notice funcion para consultar el precio de ETH en USD a través de un oráculo.
     * @return ethUSDPrice_ el precio provisto por el oráculo.
     * @dev es una implementacion simple y no sigue las mejores practicas.
     */
    function chainlinkFeed() internal view returns (uint256 ethUSDPrice_) {
        (, int256 ethUSDPrice, , uint256 updatedAt, ) = feeds
            .latestRoundData();

        if (ethUSDPrice == 0) revert OracleCompromised();
        if (block.timestamp - updatedAt > ORACLE_HEARTBEAT)
            revert StalePrice();

        ethUSDPrice_ = uint256(ethUSDPrice);
    }
    /**
     * @notice function para actualizar el Feed de precios Chainlink
     * @param _feed la direccion del nuevo feed de precios Chainlink.
     * @dev solo debe ser llamado por el propietario
     */
    function setFeeds(address _feed) external onlyOwner {
        feeds = AggregatorV3Interface(_feed);

        emit ChainlinkFeedUpdated(_feed);
    }

    /*///////////////////////////////
            Fallbacks
    ///////////////////////////////*/

    /// @notice Función para aceptar ETH directo (sin datos)
    receive() external payable {
        bool success = depositFallback();
        if (!success) revert ReceiveFallbackDepositError(msg.sender, msg.value);
    }

    /// @notice Fallback para llamadas con datos inesperados
    fallback() external payable {
        bool success = depositFallback();
        if (!success) revert FallbackDepositError(msg.sender, msg.value);
    }
}
