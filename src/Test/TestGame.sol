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
    event Received(address, uint256);
    event PrizeTransfer(address to, address nftishka, uint256 id, uint256 prizeIx);
    struct Nft {
        address adr;
        uint256 id;
    }
    struct Players {
        address[256] addresses;
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
    uint8[255] public playersOrder;
    uint256[8] public entropies;
    Players public players;
    Nft[255] public nfts;
    mapping(uint8 => uint8) public swaps;
    mapping(uint8 => uint8) public spaws;
    mapping(address => bool) public depositors;
    bool private initComplete = true;
    uint32 public lastAction;
    uint16 public thinkTime = 10800;
    uint8 public currPlayer = 0;

    modifier onlyWhitelisted() {
        require(depositors[msg.sender], "you are not allowed to deposit");
        _;
    }

    function addDepositors(address[] calldata ds) external onlyOwner {
        for (uint256 i = 0; i < ds.length; i++) {
            depositors[ds[i]] = true;
        }
    }

    modifier youShallNotPatheth(uint8 missed) {
        uint256 currTime = now;
        require(currTime > lastAction, "timestamps are incorrect");
        uint256 elapsed = currTime - lastAction;
        uint256 playersSkipped = elapsed / thinkTime;
        // someone has skipped their turn. We track this on the front-end
        if (missed != 0) {
            require(playersSkipped > 0, "zero players skipped");
            require(playersSkipped < 255, "too many players skipped");
            require(playersSkipped == missed, "playersSkipped not eq missed");
            require(currPlayer < 256, "currPlayer exceeds 255");
        } else {
            require(playersSkipped == 0, "playersSkipped not zero");
        }
        require(players.addresses[playersOrder[currPlayer + missed]] == msg.sender, "not your turn");
        _;
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

    function buyTicket() public payable nonReentrant {
        require(msg.value >= ticketPrice, "sent ether too low");
        require(players.numPlayers < 256, "total number of players reached");
        require(players.contains[msg.sender] == false, "cant buy more");
        players.contains[msg.sender] = true;
        players.addresses[players.numPlayers + 1] = msg.sender;
        players.numPlayers++;
    }

    function unwrap(uint8 missed) external nonReentrant youShallNotPatheth(missed) {
        currPlayer += missed + 1;
        lastAction = uint32(now);
    }

    /// @param _sender - index from playersOrder arr that you are stealing from
    /// @param _from - index from playersOrder who to steal from
    /// @param missed - how many players missed their turn since lastAction
    function steal(
        uint8 _sender,
        uint8 _from,
        uint8 missed
    ) external nonReentrant youShallNotPatheth(missed) {
        require(_sender > _from, "cant steal from someone who unwrapped after");
        // console.log("_sender %s, _from %s", _sender, _from);
        uint8 sender = playersOrder[_sender]; // strictly greater than zero
        uint8 from = playersOrder[_from]; // strictly greater than zero
        require(sender > 0, "strictly greater than zero sender");
        require(from > 0, "strictly greater than zero from");
        require(currPlayer + missed < 256, "its a pickle, no doubt about it");
        require(players.addresses[playersOrder[currPlayer + missed]] == players.addresses[sender], "not your order");
        require(players.addresses[sender] == msg.sender, "sender is not valid");
        require(spaws[from] == 0, "cant steal from them again");
        require(swaps[sender] == 0, "you cant steal again. You can in Verkhovna Rada.");
        // console.log("sender %s, from %s", sender, from);
        swaps[sender] = from;
        spaws[from] = sender;
        currPlayer += missed + 1;
        lastAction = uint32(now);
    }

    /// @param startIx - index from which to start looping the prizes
    /// @param endIx - index on which to end looping the prizes (exclusive)
    /// @dev start and end indices would be useful in case we hit
    /// the block gas limit, or we want to better control our transaction
    /// costs
    /// swaps \in {1, 255}. 0 signifies absence. I stole from
    /// spaws is an image of swaps.
    function finito(
        uint8[256] calldata op,
        uint8 startIx,
        uint8 endIx
    ) external onlyOwner {
        require(startIx > 0, "there is no player at 0");
        for (uint8 i = startIx; i < endIx; i++) {
            uint8 playerIx = playersOrder[i - 1];
            uint8 prizeIx;
            uint8 stoleIx = swaps[playerIx];
            uint8 stealerIx = spaws[playerIx];
            if (stoleIx == 0 && stealerIx == 0) {
                prizeIx = playersOrder[i - 1] - 1;
            } else if (stealerIx != 0) {
                prizeIx = op[stealerIx - 1];
            } else {
                bool end = false;
                while (!end) {
                    prizeIx = stoleIx;
                    stoleIx = swaps[stoleIx];
                    if (stoleIx == 0) {
                        end = true;
                    }
                }
                prizeIx = op[prizeIx - 1];
            }
            // event PrizeTransfer(address to, address nftishka, uint256 id, uint256 prizeIx);
            emit PrizeTransfer(players.addresses[playerIx], nfts[prizeIx].adr, nfts[prizeIx].id, prizeIx);
            // emit PrizeTransfer();
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public override returns (bytes4) {
        revert("we are saving you your NFT, you are welcome");
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
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

    function testSetPlayersOrder(uint8[255] calldata _playersOrder) external onlyOwner {
        playersOrder = _playersOrder;
    }

    function withdrawERC721(ERC721 nft, uint256 tokenId) external onlyOwner {
        nft.transferFrom(address(this), msg.sender, tokenId);
    }

    function withdrawERC20(ERC20 token) external onlyOwner {
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function withdrawEth() external onlyOwner {
        msg.sender.transfer(address(this).balance);
    }
}
