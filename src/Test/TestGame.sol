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
        require(players.addresses[playersOrder[currPlayer]] == players.addresses[sender], "not your order");
        require(players.addresses[sender] == msg.sender, "sender is not valid");
        require(spaws[from] == 0, "cant steal from them again");
        require(swaps[sender] == 0, "you cant steal again. You can in Verkhovna Rada.");
        // console.log("sender %s, from %s", sender, from);
        swaps[sender] = from;
        spaws[from] = sender;
        currPlayer += missed + 1;
        lastAction = uint32(now);
    }

    /// @param orderPlayers - given the index of the player (from players)
    /// gives their turn number
    /// @param startIx - index from which to start looping the prizes
    /// @param endIx - index on which to end looping the prizes (exclusive)
    /// @dev start and end indices would be useful in case we hit
    /// the block gas limit, or we want to better control our transaction
    /// costs
    function finito(
        uint8[255] calldata orderPlayers,
        uint8 startIx,
        uint8 endIx
    ) external onlyOwner {
        require(startIx > 0, "there is no player at 0");
        // take into account the steals, the skips and unwraps
        // distribute the NFT prizes to their rightful owners
        // players: [0x123, 0x223, 0x465, 0xf21]. First, 0x123 bought, then 0x223 etc.
        // playersOrder: [4,1,3,2]. 4th buyer goes first, 1st buy goest second, ...
        // swaps: { 2: 1, 4: 3 }. Second player (0x223) stole from first, and
        // fourth stole from third. In essence, 2-1 swapped and then 4-3 swapped
        for (uint8 i = startIx; i < endIx; i++) {
            uint8 prizeIx = 0;
            // verify that the prize is correct
            uint8 stoleIx = swaps[i];
            uint8 stealerIx = spaws[i];
            // console.log("--------");
            // console.log("I am %s", players.addresses[i]);
            // console.log("stoleIx %s, stealerIx %s", stoleIx, stealerIx);
            if (stoleIx == 0 && stealerIx == 0) {
                // stole from no-one, means his prize is
                // his turn number. orderPlayers maps index
                // of player in players arr to their turn number
                // thus if players = [a,b,c,d] and we are interested
                // in player a, at index 0 and
                // playersOrder is [1,2,3,4]
                // then orderPlayers is trivially [0,1,2,3]
                // and so orderPlayers[index of a in players] will give us index in playersOrder
                // namely 0. i.e. orderPlayers[0] = 0;
                // and so prizeIx in this case would be 0;
                // * minus one for playersOrder offset, because it is 1-indexed
                prizeIx = orderPlayers[i] - 1;
                // console.log("1 - didnt steal | wasnt stolen from, prizeIx %s", prizeIx);
            }
            // if the player stole
            if (stoleIx != 0) {
                // need to check if the player that we steal from has stolen himself
                // prizeIx = orderPlayers[swaps[i]] - 1;
                bool end = false;
                while (!end) {
                    // swaps[i] tells us who we stole from
                    // we need to follow this link all the
                    // way to when the address has not stolen from
                    // we (a) stole from (b), (b) stole from (c), (c) didn't steal
                    // our prize is that of (c)
                    prizeIx = stoleIx - 1;
                    stoleIx = swaps[stoleIx];
                    if (stoleIx == 0) {
                        end = true;
                    }
                }
                // console.log("2 - stole | prizeIx %s", prizeIx);
            }
            // if the player was stolen from, then the prize they receive must be from their stealer
            // since i is the index of the player in players, we trivially have
            if (stealerIx != 0) {
                prizeIx = orderPlayers[spaws[i]] - 1;
                // console.log("3 - was stolen from | prizeIx %s", prizeIx);
            }
            // console.log("----");
            // transfer the prize
            // ERC721(nfts[prizeIx].adr).transferFrom(address(this), players.addresses[i], nfts[prizeIx].id);
            emit PrizeTransfer(players.addresses[i], nfts[prizeIx].adr, nfts[prizeIx].id, prizeIx);
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
