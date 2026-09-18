// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract TokenLaunchpad {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAddress();
    error NotOwner();

    error InvalidPrice();
    error InvalidAllocation();
    error InvalidTime();
    error InvalidHardCap();
    error InvalidWalletLimit();
    error InvalidFee();

    error SaleDoesNotExist();
    error SaleNotStarted();
    error SaleEnded();
    error SaleNotEnded();

    error ZeroPayment();
    error IncorrectPayment();
    error WalletLimitExceeded();
    error HardCapExceeded();
    error AllocationExceeded();

    error NothingToClaim();
    error AlreadyClaimed();

    error AlreadyWithdrawn();
    error AlreadyRecovered();

    error TokenTransferFailed();
    error ETHTransferFailed();
    error ReentrantCall();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event SaleCreated(uint256 indexed saleId, address indexed creator, address indexed token);

    event TokensPurchased(uint256 indexed saleId, address indexed buyer, uint256 ethPaid, uint256 tokensPurchased);

    event TokensClaimed(uint256 indexed saleId, address indexed buyer, uint256 amount);

    event ProceedsWithdrawn(
        uint256 indexed saleId, address indexed creator, uint256 creatorAmount, uint256 platformFee
    );

    event UnsoldTokensRecovered(uint256 indexed saleId, address indexed creator, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 public constant BPS = 10_000;

    address public immutable owner;

    address public immutable feeRecipient;

    uint256 public immutable platformFeeBps;

    uint256 public nextSaleId;

    // 1 = unlocked
    // 2 = locked
    uint256 private locked = 1;

    /*//////////////////////////////////////////////////////////////
                                SALE
    //////////////////////////////////////////////////////////////*/

    struct Sale {
        address creator;
        IERC20 token;
        uint256 price;
        uint256 allocation;
        uint256 startTime;
        uint256 endTime;
        uint256 hardCap;
        uint256 walletLimit;
        uint256 totalRaised;
        uint256 totalTokensSold;
        bool proceedsWithdrawn;
        bool unsoldRecovered;
    }

    // Private to avoid generating a large automatic getter.
    mapping(uint256 => Sale) private sales;

    // saleId => buyer => ETH contributed
    mapping(uint256 => mapping(address => uint256)) public contributions;

    // saleId => buyer => token amount purchased
    mapping(uint256 => mapping(address => uint256)) public purchasedTokens;

    // saleId => buyer => claimed
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert NotOwner();
        }

        _;
    }

    modifier nonReentrant() {
        if (locked != 1) {
            revert ReentrantCall();
        }

        locked = 2;

        _;

        locked = 1;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _feeRecipient, uint256 _platformFeeBps) {
        if (_feeRecipient == address(0)) {
            revert ZeroAddress();
        }

        if (_platformFeeBps > BPS) {
            revert InvalidFee();
        }

        owner = msg.sender;

        feeRecipient = _feeRecipient;

        platformFeeBps = _platformFeeBps;
    }

    /*//////////////////////////////////////////////////////////////
                              CREATE SALE
    //////////////////////////////////////////////////////////////*/

    function createSale(
        address token,
        uint256 price,
        uint256 allocation,
        uint256 startTime,
        uint256 endTime,
        uint256 hardCap,
        uint256 walletLimit
    ) external onlyOwner nonReentrant returns (uint256 saleId) {
        _validateSale(token, price, allocation, startTime, endTime, hardCap, walletLimit);

        saleId = nextSaleId++;

        Sale storage sale = sales[saleId];

        sale.creator = msg.sender;
        sale.token = IERC20(token);
        sale.price = price;
        sale.allocation = allocation;
        sale.startTime = startTime;
        sale.endTime = endTime;
        sale.hardCap = hardCap;
        sale.walletLimit = walletLimit;

        bool success = IERC20(token).transferFrom(msg.sender, address(this), allocation);

        if (!success) {
            revert TokenTransferFailed();
        }

        emit SaleCreated(saleId, msg.sender, token);
    }

    /*//////////////////////////////////////////////////////////////
                                  BUY
    //////////////////////////////////////////////////////////////*/

    function buy(uint256 saleId) external payable {
        Sale storage sale = _getSale(saleId);

        if (block.timestamp < sale.startTime) {
            revert SaleNotStarted();
        }

        if (block.timestamp >= sale.endTime) {
            revert SaleEnded();
        }

        if (msg.value == 0) {
            revert ZeroPayment();
        }

        /*//////////////////////////////////////////////////////////
                            WALLET LIMIT
        //////////////////////////////////////////////////////////*/

        uint256 newContribution = contributions[saleId][msg.sender] + msg.value;

        if (newContribution > sale.walletLimit) {
            revert WalletLimitExceeded();
        }

        /*//////////////////////////////////////////////////////////
                              HARD CAP
        //////////////////////////////////////////////////////////*/

        uint256 newTotalRaised = sale.totalRaised + msg.value;

        if (newTotalRaised > sale.hardCap) {
            revert HardCapExceeded();
        }

        /*//////////////////////////////////////////////////////////
                         EXACT PAYMENT
        //////////////////////////////////////////////////////////*/

        /*
         * price represents the amount of wei
         * required to buy one whole token.
         *
         * Example:
         *
         * price = 0.001 ether
         *
         * 0.001 ETH = 1 token
         * 0.01 ETH  = 10 tokens
         * 1 ETH     = 1000 tokens
         */

        if (msg.value % sale.price != 0) {
            revert IncorrectPayment();
        }

        uint256 wholeTokens = msg.value / sale.price;

        /*
         * Current implementation assumes
         * the sale token has 18 decimals.
         */

        uint256 tokenAmount = wholeTokens * 1e18;

        uint256 newTokensSold = sale.totalTokensSold + tokenAmount;

        if (newTokensSold > sale.allocation) {
            revert AllocationExceeded();
        }

        /*//////////////////////////////////////////////////////////
                               EFFECTS
        //////////////////////////////////////////////////////////*/

        contributions[saleId][msg.sender] = newContribution;

        purchasedTokens[saleId][msg.sender] += tokenAmount;

        sale.totalRaised = newTotalRaised;

        sale.totalTokensSold = newTokensSold;

        emit TokensPurchased(saleId, msg.sender, msg.value, tokenAmount);
    }

    /*//////////////////////////////////////////////////////////////
                                CLAIM
    //////////////////////////////////////////////////////////////*/

    function claim(uint256 saleId) external nonReentrant {
        Sale storage sale = _getSale(saleId);

        if (block.timestamp < sale.endTime) {
            revert SaleNotEnded();
        }

        uint256 amount = purchasedTokens[saleId][msg.sender];

        if (amount == 0) {
            revert NothingToClaim();
        }

        if (hasClaimed[saleId][msg.sender]) {
            revert AlreadyClaimed();
        }

        // Effects before interaction.
        hasClaimed[saleId][msg.sender] = true;

        bool success = sale.token.transfer(msg.sender, amount);

        if (!success) {
            revert TokenTransferFailed();
        }

        emit TokensClaimed(saleId, msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                         WITHDRAW PROCEEDS
    //////////////////////////////////////////////////////////////*/

    function withdrawProceeds(uint256 saleId) external onlyOwner nonReentrant {
        Sale storage sale = _getSale(saleId);

        if (block.timestamp < sale.endTime) {
            revert SaleNotEnded();
        }

        if (sale.proceedsWithdrawn) {
            revert AlreadyWithdrawn();
        }

        // Effects before interactions.
        sale.proceedsWithdrawn = true;

        uint256 fee = (sale.totalRaised * platformFeeBps) / BPS;

        uint256 creatorAmount = sale.totalRaised - fee;

        if (creatorAmount > 0) {
            _sendETH(owner, creatorAmount);
        }

        if (fee > 0) {
            _sendETH(feeRecipient, fee);
        }

        emit ProceedsWithdrawn(saleId, owner, creatorAmount, fee);
    }

    /*//////////////////////////////////////////////////////////////
                      RECOVER UNSOLD TOKENS
    //////////////////////////////////////////////////////////////*/

    function recoverUnsoldTokens(uint256 saleId) external onlyOwner nonReentrant {
        Sale storage sale = _getSale(saleId);

        if (block.timestamp < sale.endTime) {
            revert SaleNotEnded();
        }

        if (sale.unsoldRecovered) {
            revert AlreadyRecovered();
        }

        sale.unsoldRecovered = true;

        /*
         * Only recover tokens that were
         * never sold.
         *
         * Sold tokens remain reserved
         * for buyers who haven't claimed.
         */

        uint256 unsold = sale.allocation - sale.totalTokensSold;

        if (unsold > 0) {
            bool success = sale.token.transfer(owner, unsold);

            if (!success) {
                revert TokenTransferFailed();
            }
        }

        emit UnsoldTokensRecovered(saleId, owner, unsold);
    }

    /*//////////////////////////////////////////////////////////////
                              GET SALE
    //////////////////////////////////////////////////////////////*/

    function getSale(uint256 saleId) external view returns (Sale memory) {
        if (saleId >= nextSaleId) {
            revert SaleDoesNotExist();
        }

        return sales[saleId];
    }

    /*//////////////////////////////////////////////////////////////
                       INTERNAL VALIDATION
    //////////////////////////////////////////////////////////////*/

    function _validateSale(
        address token,
        uint256 price,
        uint256 allocation,
        uint256 startTime,
        uint256 endTime,
        uint256 hardCap,
        uint256 walletLimit
    ) internal view {
        if (token == address(0)) {
            revert ZeroAddress();
        }

        if (price == 0) {
            revert InvalidPrice();
        }

        if (allocation == 0) {
            revert InvalidAllocation();
        }

        if (startTime <= block.timestamp || endTime <= startTime) {
            revert InvalidTime();
        }

        if (hardCap == 0) {
            revert InvalidHardCap();
        }

        if (walletLimit == 0 || walletLimit > hardCap) {
            revert InvalidWalletLimit();
        }
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getSale(uint256 saleId) internal view returns (Sale storage sale) {
        if (saleId >= nextSaleId) {
            revert SaleDoesNotExist();
        }

        sale = sales[saleId];
    }

    function _sendETH(address recipient, uint256 amount) internal {
        (bool success,) = payable(recipient).call{value: amount}("");

        if (!success) {
            revert ETHTransferFailed();
        }
    }
}
