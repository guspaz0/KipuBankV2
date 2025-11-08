// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/*//////////////////
        Imports
//////////////////*/
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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
contract KipuBankV2 is Ownable, ReentrancyGuard {
    /*///////////////////////
        TYPE DECLARATIONS
    ///////////////////////*/
    using SafeERC20 for IERC20;

    /*//////////////////////////////
          Variables de estado
    ///////////////////////////////*/

    /// @notice Límite por transacción de retiro (en wei)
    uint256 public immutable withdrawLimitUSD = 1000;

    // contante para almacenar la dirección del token ETH en el sistema
    address constant ETH_ADDRESS = address(0);

    ///@notice constant variable to hold Data Feeds Heartbeat
    uint256 constant ORACLE_HEARTBEAT = 3600;

    uint8 constant DECIMAL_FACTOR = 6;

    ///@notice variable to store Chainlink Feeds address
    address public feeds; // Sepolia ETH/USD Oracle 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    // ESTRUCTURAS Y CATÁLOGO DE TOKENS (Soporte Multi-token) [5]
    struct TokenData {
        address priceFeedAddress;
        uint8 tokenDecimals;
        bool isAllowed;
    }
    // Array para almacenar los datos de los tokens permitidos
    address[] public allowedTokens;

    // Mapeo de la dirección del token -> Datos de configuración.
    mapping(address => TokenData) private s_tokenCatalog;

    /// @notice Mapping para relacionar las direcciones con la información de los usuarios
    mapping(address user => mapping(address token => uint256 amount))
        public balances;

    /// @notice Limite global de depositos en USD;
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
    error BankCapLimitExceeded(uint256 bankCap);

    /// @notice Error que se emite al intentar validar un address
    error Bank_invalidAddress(address _address);

    /// @notice Error que se emite al intentar agregar un token que ya existe dentro del catalogo
    error Bank_TokenAlreadySupported(address _address);

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

    /// @notice Evento que se emite cuando se agrega un token al catalogo.
    event TokenSupported(
        address indexed newTokenAddress,
        address priceFeedAddress,
        uint8 decimals
    );

    /*//////////////////////////////
            Modificadores
    ///////////////////////////////*/

    /**
     * @dev Constructor del contrato
     * @param _bankCap El límite máximo de fondos que el banco puede manejar (en USD)
     * @param _priceFeedAddress La dirección del feed de precios Chainlink ETH/USD
     */
    constructor(
        uint256 _bankCap,
        address _priceFeedAddress
    ) Ownable(msg.sender) {
        if (_bankCap == 0) revert ConstructorError("_bankCap");
        bankCap = _bankCap;
        feeds = _priceFeedAddress;
    }

    /*//////////////////////////////
            Funciones
    ///////////////////////////////*/

    /**
     * @dev Función para agregar un token al catalogo
     * @param tokenAddress La dirección del contrato ERC20
     * @param priceFeedAddress La dirección del feed
     * @param decimals Los decimales del token
     */
    function addSupportedToken(
        address tokenAddress,
        address priceFeedAddress,
        uint8 decimals
    ) external onlyOwner {
        /// A. CHECKS
        if (tokenAddress == address(0) || priceFeedAddress == address(0))
            revert Bank_invalidAddress(tokenAddress);
        if (s_tokenCatalog[tokenAddress].isAllowed)
            revert Bank_TokenAlreadySupported(tokenAddress);

        /// B. EFFECTS
        s_tokenCatalog[tokenAddress] = TokenData({
            priceFeedAddress: priceFeedAddress,
            tokenDecimals: decimals,
            isAllowed: true
        });
        allowedTokens.push(tokenAddress);

        /// C. INTERACTIONS
        emit TokenSupported(tokenAddress, priceFeedAddress, decimals);
    }

    /**
     * @dev Función para depositar ETH en la cuenta del usuario
     */
    function deposit(
        address _tokenAddress,
        uint256 _tokenAmount
    ) external payable {
        if (_tokenAddress == ETH_ADDRESS) {
            if (_tokenAmount != msg.value)
                revert DepositAmountMismatch(
                    msg.sender,
                    msg.value,
                    _tokenAmount
                );
            bool success = depositFallback();
            if (!success) revert DepositFailed(msg.sender, msg.value);
        }
        if (_tokenAddress != ETH_ADDRESS)
            depositToken(_tokenAddress, _tokenAmount);
    }

    function depositToken(
        address _tokenAddress,
        uint256 _tokenAmount
    ) internal bankCapCheck(_tokenAddress, _tokenAmount) {
        // CHECKS
        uint256 userBalance = balances[msg.sender][address(_tokenAddress)];

        // EFFECTS
        balances[msg.sender][address(_tokenAddress)] =
            userBalance + _tokenAmount;
        depositosCount++;

        // INTERACTIONS
        IERC20(_tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenAmount
        );
        emit Deposit(msg.sender, _tokenAmount, userBalance + _tokenAmount);
    }
    /// @notice Modificador para verificar si no se ah excedido el limite del banco y actualiza el balance
    modifier bankCapCheck(address _tokenAddress, uint256 _tokenAmount) {
        // CHECKS
        if (_tokenAddress != ETH_ADDRESS) {
            _tokenAmount = _toUSD(_tokenAddress, _tokenAmount);
        } else _tokenAmount = 0;
        uint256 newBalance = contractBalanceInUSD() + _tokenAmount;
        if (newBalance > bankCap) revert BankCapLimitExceeded(bankCap);
        _;
    }
    /**
     * @notice funcion interna para convertir la cantidad de USDC a ETH usando el oraculo del token especificado
     * @param token address del token a convertir
     * @param amount la cantidad de token a convertir
     * @return _convertedAmount la cantidad de USD resultante
     */
    function _toUSD(
        address token,
        uint256 amount
    ) internal view returns (uint256 _convertedAmount) {
        // CHECKS
        TokenData memory data = s_tokenCatalog[token];
        if (!data.isAllowed) revert Bank_invalidAddress(token);
        if (data.priceFeedAddress == address(0) || amount == 0) return 0;

        // INTERACTIONS
        AggregatorV3Interface dataFeed = AggregatorV3Interface(
            data.priceFeedAddress
        );
        (, int256 price, , uint256 updatedAt, ) = dataFeed.latestRoundData();

        if (price == 0) revert OracleCompromised();
        if (block.timestamp - updatedAt > ORACLE_HEARTBEAT) revert StalePrice();

        if (price <= 0) return 0;

        uint256 factor = 1 *
            10 ** (data.tokenDecimals + dataFeed.decimals() - DECIMAL_FACTOR);
        _convertedAmount = (amount * uint256(price)) / factor;
    }

    /**
     * @notice funcion externa para retirar tokens(ERC-20) o eth de la cuenta del usuario. la funcion se encarga de la conversion.
     * @param _tokenAddress La dirección del token(ERC-20) o direccion 0 en caso de eth.
     * @param _tokenAmount La cantidad a retirar de tokens ERC-20 o eth
     * @dev el usuario no deberia poder retirar mas de su balance de tokens
     * @dev el usuario no deberia poder retirar mas del umbral de retiro por transaccion (withdrawalLimit)
     */
    function withdraw(
        address _tokenAddress,
        uint256 _tokenAmount
    ) public nonReentrant {
        if (_tokenAmount == 0)
            revert WithdrawalAmountError(msg.sender, _tokenAmount);
        if (_tokenAddress == ETH_ADDRESS) withdrawEth(_tokenAmount);
        else withdrawToken(_tokenAddress, _tokenAmount);
    }

    function withdrawEth(uint256 amount) internal {
        // A. CHEKS
        uint256 userBalance = balances[msg.sender][ETH_ADDRESS];
        uint256 amountUSD = convertEthInUSD(amount);
        if (amountUSD > withdrawLimitUSD)
            revert WithdrawalLimitExceeded(msg.sender, amount);
        if (amount > userBalance)
            revert InsufficientUserBalance(amount, userBalance);

        // B. EFFECTS
        balances[msg.sender][ETH_ADDRESS] = userBalance - amount;
        withdrawalCount++;

        (bool success, bytes memory data) = msg.sender.call{value: amount}("");
        if (!success) revert WithdrawalTransferError(data);

        // C. INTERACTIONS
        emit Withdrawal(msg.sender, amount, userBalance - amount);
    }

    function withdrawToken(
        address _tokenAddress,
        uint256 _tokenAmount
    ) internal {
        // A. CHECKS
        uint256 userBalance = balances[msg.sender][address(_tokenAddress)];
        if (_tokenAmount > userBalance)
            revert InsufficientUserBalance(_tokenAmount, userBalance);

        // B. EFFECTS
        balances[msg.sender][address(_tokenAddress)] -= _tokenAmount;
        withdrawalCount++;

        // C. INTERACTIONS
        IERC20(_tokenAddress).safeTransfer(msg.sender, _tokenAmount);
        emit Withdrawal(msg.sender, _tokenAmount, userBalance - _tokenAmount);
    }

    /// @notice funcion privada para manejar el depósito de ETH en caso de que entre en las funciones fallback
    function depositFallback()
        private
        bankCapCheck(ETH_ADDRESS, msg.value)
        returns (bool)
    {
        if (msg.value == 0) return false;

        // A. CHECKS
        uint256 userBalance = balances[msg.sender][ETH_ADDRESS];

        // B. EFFECTS
        balances[msg.sender][ETH_ADDRESS] = userBalance + msg.value;

        // aumentar contador depositos
        depositosCount++;

        // C. INTERACTIONS (Emisión de evento)
        emit Deposit(msg.sender, msg.value, userBalance + msg.value);

        return true;
    }

    /**
     * @notice funcion extena para consultar el balance del contrato en USDC.
     * @return balance_ el monto de ETH en el contrato.
     */
    function contractBalanceInUSD() public view returns (uint256 balance_) {
        uint256 convertedUSDAmount = convertEthInUSD(address(this).balance);
        uint256 sum = 0;

        for (uint i = 0; i < allowedTokens.length; i++) {
            address tokenAddress = allowedTokens[i];
            uint256 tokenBalance = IERC20(tokenAddress).balanceOf(
                address(this)
            );
            sum += _toUSD(tokenAddress, tokenBalance);
        }
        balance_ = convertedUSDAmount + sum;
    }

    /**
     * @notice funcion interna para convertir la cantidad de ETH a USDC usando un oraculo.
     * @param _ethAmount el monto de ETH a convertir.
     * @return convertedAmount_ resultado del calculo.
     */
    function convertEthInUSD(
        uint256 _ethAmount
    ) internal view returns (uint256 convertedAmount_) {
        convertedAmount_ =
            (_ethAmount * chainlinkFeed()) / 10 ** (18 + DECIMAL_FACTOR);
    }

    /**
     * @notice funcion para consultar el precio de ETH en USD a través de un oráculo.
     * @return ethUSDPrice_ el precio provisto por el oráculo.
     * @dev es una implementacion simple y no sigue las mejores practicas.
     */
    function chainlinkFeed() internal view returns (uint256 ethUSDPrice_) {
        (
            ,
            int256 ethUSDPrice,
            ,
            uint256 updatedAt,
            uint256 answeredInRound
        ) = AggregatorV3Interface(feeds).latestRoundData();

        if (ethUSDPrice == 0) revert OracleCompromised();
        if (block.timestamp - updatedAt > ORACLE_HEARTBEAT) revert StalePrice();
        if (answeredInRound == 0) revert OracleCompromised(); // Check for answeredInRound
        ethUSDPrice_ = uint256(ethUSDPrice);
    }
    /**
     * @notice function para actualizar el Feed de precios Chainlink
     * @param _tokenAddress direccion del token
     * @param _feedAddress la direccion del nuevo feed de precios Chainlink.
     * @dev solo debe ser llamado por el propietario
     */
    function setFeeds(
        address _tokenAddress,
        address _feedAddress
    ) external onlyOwner {
        // CHECKS
        TokenData memory data = s_tokenCatalog[_tokenAddress];
        if (!data.isAllowed) revert Bank_invalidAddress(_tokenAddress);

        // EFFECTS
        data.priceFeedAddress = _feedAddress;

        // INTERACTIONS
        emit ChainlinkFeedUpdated(_feedAddress);
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
