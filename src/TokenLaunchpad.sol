// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract TokenLaunchpad {
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

    event SaleCreated(uint256 indexed saleId, address indexed creator, address indexed token);

    event TokensPurchased(uint256 indexed saleId, address indexed buyer, uint256 ethPaid, uint256 tokensPurchased);

    event TokensClaimed(uint256 indexed saleId, address indexed buyer, uint256 amount);

    event ProceedsWithdrawn(
        uint256 indexed saleId, address indexed creator, uint256 creatorAmount, uint256 platformFee
    );

    event UnsoldTokensRecovered(uint256 indexed saleId, address indexed creator, uint256 amount);

    uint256 public constant BPS = 10_000;

    address public immutable owner;

    address public immutable feeRecipient;

    uint256 public immutable platformFeeBps;

    uint256 public nextSaleId;

    uint256 private locked = 1;

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

    mapping(uint256 => Sale) private sales;

    mapping(uint256 => mapping(address => uint256)) public contributions;

    mapping(uint256 => mapping(address => uint256)) public purchasedTokens;

    mapping(uint256 => mapping(address => bool)) public hasClaimed;

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

        uint256 newContribution = contributions[saleId][msg.sender] + msg.value;

        if (newContribution > sale.walletLimit) {
            revert WalletLimitExceeded();
        }

        uint256 newTotalRaised = sale.totalRaised + msg.value;

        if (newTotalRaised > sale.hardCap) {
            revert HardCapExceeded();
        }

        if (msg.value % sale.price != 0) {
            revert IncorrectPayment();
        }

        uint256 wholeTokens = msg.value / sale.price;

        uint256 tokenAmount = wholeTokens * 1e18;

        uint256 newTokensSold = sale.totalTokensSold + tokenAmount;

        if (newTokensSold > sale.allocation) {
            revert AllocationExceeded();
        }

        contributions[saleId][msg.sender] = newContribution;

        purchasedTokens[saleId][msg.sender] += tokenAmount;

        sale.totalRaised = newTotalRaised;

        sale.totalTokensSold = newTokensSold;

        emit TokensPurchased(saleId, msg.sender, msg.value, tokenAmount);
    }

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

    function recoverUnsoldTokens(uint256 saleId) external onlyOwner nonReentrant {
        Sale storage sale = _getSale(saleId);

        if (block.timestamp < sale.endTime) {
            revert SaleNotEnded();
        }

        if (sale.unsoldRecovered) {
            revert AlreadyRecovered();
        }

        sale.unsoldRecovered = true;

        uint256 unsold = sale.allocation - sale.totalTokensSold;

        if (unsold > 0) {
            bool success = sale.token.transfer(owner, unsold);

            if (!success) {
                revert TokenTransferFailed();
            }
        }

        emit UnsoldTokensRecovered(saleId, owner, unsold);
    }

    function getSale(uint256 saleId) external view returns (Sale memory) {
        if (saleId >= nextSaleId) {
            revert SaleDoesNotExist();
        }

        return sales[saleId];
    }

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
