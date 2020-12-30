// SPDX-License-Identifier: MIT
/// @author Nazariy Vavryk [nazariy@inbox.ru] - reNFT Labs [https://twitter.com/renftlabs]
pragma solidity >=0.6.0 <0.7.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract TestGame is Ownable, ERC721Holder, ReentrancyGuard {
    struct Nft {
        address adr;
        uint256 id;
    }
    struct Players {
        address payable[256] addresses;
        mapping(address => bool) contains;
        uint8 numPlayers;
    }
    mapping(address => bool) public testTest;
    address private chainlinkVrfCoordinator = 0xdD3782915140c8f3b190B5D67eAc6dc5760C46E9;
    address private chainlinkLinkToken = 0xa36085F69e2889c224210F603D836748e7dC0088;
    bytes32 private chainlinkKeyHash = 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4;
    uint256 private chainlinkCallFee = 0.1 * 10**18;
    uint256 public ticketPrice = 0.0001 ether;
    uint32 public timeBeforeGameStart = 1609718399;
    uint8[256] public playersOrder;
    uint256[8] public entropies;
    Players public players;
    Nft[256] public nfts;
    mapping(uint8 => uint8) public swaps;
    mapping(uint8 => uint8) public spaws;
    mapping(address => bool) public depositors;
    bool private initComplete = true;
    uint32 private lastAction;
    uint16 public thinkTime = 10800;
    uint8 public currPlayer = 0;

    modifier beforeGameStart() {
        require(now < timeBeforeGameStart, "game has now begun");
        _;
    }

    modifier afterGameStart() {
        require(now > timeBeforeGameStart + 1800, "game has not started yet");
        require(initComplete, "game has not initialized yet");
        _;
    }

    modifier onlyWhitelisted() {
        require(depositors[msg.sender], "you are not allowed to deposit");
        _;
    }

    function addDepositors(address[] calldata ds) external onlyOwner {
        for (uint256 i = 0; i < ds.length; i++) {
            depositors[ds[i]] = true;
        }
    }

    constructor() public {
        depositors[0x465DCa9995D6c2a81A9Be80fBCeD5a770dEE3daE] = true;
        depositors[0x426923E98e347158D5C471a9391edaEa95516473] = true;
        // each entropy is 32 chunks of uint8
        // so the below is sufficient randomness for 64 players
        // entropies = [
        //     11579208923731619542357098500868790785326984665640564039457584007913129639935,
        //     11579208923731619542357098008687907853269984665640564039457584007913129639935
        // ];
    }

    function deposit(ERC721[] calldata _nfts, uint256[] calldata tokenIds) public onlyWhitelisted {
        require(_nfts.length == tokenIds.length, "variable lengths");
        for (uint256 i = 0; i < _nfts.length; i++) {
            _nfts[i].transferFrom(msg.sender, address(this), tokenIds[i]);
        }
    }

    function buyTicket() public payable beforeGameStart nonReentrant {
        require(msg.value >= ticketPrice, "sent ether too low");
        require(players.numPlayers < 256, "total number of players reached");
        require(players.contains[msg.sender] == false, "cant buy more");
        players.contains[msg.sender] = true;
        players.addresses[players.numPlayers] = msg.sender;
        players.numPlayers++;
    }

    function unwrap(uint8 missed) external afterGameStart nonReentrant {
        uint256 currTime = now;
        require(currTime > lastAction, "timestamps are incorrect");
        uint256 elapsed = currTime - lastAction;
        uint256 playersSkipped = elapsed / thinkTime;
        if (missed != 0) {
            require(playersSkipped > 0, "zero players skipped");
            require(playersSkipped < 256, "too many players skipped");
            require(playersSkipped == missed, "playersSkipped not eq missed");
            currPlayer += missed;
            require(currPlayer < 256, "currPlayer exceeds 255");
        } else {
            require(playersSkipped == 0, "playersSkipped not zero");
        }
        require(players.addresses[playersOrder[currPlayer]] == msg.sender, "not your turn");
        currPlayer += 1;
        lastAction = uint32(currTime);
    }

    function steal(uint8 sender, uint8 from) external afterGameStart nonReentrant {
        require(players.addresses[playersOrder[currPlayer]] == players.addresses[sender], "not your order");
        require(players.addresses[sender] == msg.sender, "sender is not valid");
        require(spaws[from] == 0, "cant steal from them again");
        require(swaps[sender] == 0, "you cant steal again. Check out Verkhovna Rada.");
        swaps[sender] = from;
        spaws[from] = sender;
        currPlayer += 1;
        lastAction = uint32(now);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public override returns (bytes4) {
        revert("we are saving you your NFT, you are welcome");
    }

    function setTicketPrice(uint256 v) external onlyOwner {
        ticketPrice = v;
    }

    function player(uint8 i) external view returns (address, uint8) {
        return (players.addresses[i], players.numPlayers);
    }

    function testSetLastAction(uint32 _lastAction) external onlyOwner {
        lastAction = _lastAction;
    }

    function testSetPlayersOrder(uint8[256] calldata _playersOrder) external onlyOwner {
        playersOrder = _playersOrder;
    }
}
